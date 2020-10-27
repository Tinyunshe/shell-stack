#!/bin/bash
# 按正规环境修改：
# token值
# acp访问ip
# 接口url路径

function file_handler() {
    local FILE_NAME=$1
    if [ -e ${FILE_NAME} ];then > ${FILE_NAME};else touch ${FILE_NAME};fi
}

function url_handler() {
    local URL=$1
    if ! curl -sk ${URL} -H "Authorization:Bearer ${TOKEN}" &> /dev/null;then printf "Error ${URL} connect failed";exit 1;fi
}

function ssh_handler() {
    local HOST=$1
    if ! ssh -o ConnectTimeout=3 -o ConnectionAttempts=5 -o PasswordAuthentication=no -o StrictHostKeyChecking=no ${HOST} "echo ping";then
        printf "${HOST} ssh connect timeout\n" >> ssh_error.txt
        return 1
    fi
}

function host_ssh() {
    local HOST=$1

cat > check_mem.sh << EOF
#!/bin/bash
set -u

InfoFile="/proc/meminfo"
[[ -f \$InfoFile ]] || { echo "\$InfoFile not exist,please check"; exit 124; }

TotalMem="\$(grep '^MemTotal:' /proc/meminfo|grep  -o '[0-9]\{1,\}')"
RealFreeMem=\`cat /proc/meminfo |grep MemAvailable|awk '{print \$2}'\`
RealUsedMem=\`expr \$TotalMem - \$RealFreeMem\`
echo -e "\${RealUsedMem}\t\${TotalMem}"|awk '{printf "%2.2f\n",\$1/\$2*100}'
EOF

    scp check_mem.sh ${HOST}:/tmp &> /dev/null
    printf "${HOST}\n" >> host_disk.txt ;ssh ${HOST}  "df -hT / /cpaas /var/lib/docker|awk 'NR>1{print \$NF,\$(NF-1)}'|column -t" >> host_disk.txt 2> /dev/null
    echo "---" >> host_disk.txt
    ssh ${HOST} "cat /proc/cpuinfo|grep process| wc -l"  >> host_cpu.txt
    ssh ${HOST} "uptime | awk '{print \$NF}'" >> host_cpurate.txt
    ssh ${HOST} "bash /tmp/check_mem.sh && rm -f /tmp/check_mem.sh" >> host_mem.txt
}

function host_num() {

    HOST_COUNT=$(cat ${CLUSTER_JSON}|jq '.items[].metadata.name'|tr -d '"'|wc -l)

    file_handler host_num.txt
    printf "${HOST_COUNT}\n" > host_num.txt
}

function host_ips() {

    HOST_LIST=$(cat ${CLUSTER_JSON}|jq '.items[].metadata.name'|tr -d '"')

    file_handler host_ip.txt
    for h in ${HOST_LIST};do
        RESOURCE_URL="http://${ACP_IP}/kubernetes/${h}/api/v1/nodes"
        url_handler ${RESOURCE_URL}
        file_handler ${h}_host_ip.txt
        curl -sk http://${ACP_IP}/kubernetes/${h}/api/v1/nodes -H "Authorization:Bearer ${TOKEN}" | jq . > ${h}.json
        IPS=$(cat ${h}.json | jq '.items[].status.addresses[0].address' | tr -d '"')
        printf "${IPS}\n" >> ${h}_host_ip.txt && sed -i "s#^#${h} #" ${h}_host_ip.txt
        cat ${h}_host_ip.txt >> host_ip.txt
    done

}

function host_handler() {

    IPS_LIST=$(awk '{print $NF}' host_ip.txt)

    file_handler host_cpu.txt
    file_handler host_mem.txt
    file_handler host_disk.txt
    file_handler host_cpurate.txt
    file_handler host_mem.txt
    file_handler ssh_error.txt

    for i in ${IPS_LIST};do
        if ! ssh_handler ${i};then continue;fi
    done
    if [ -s ssh_error.txt ];then 
        printf "Error ssh connect questions\nssh faild machine list\n"
        cat ssh_error.txt
        read -p "Skip ssh faild machine? (yes/no)" p
        if [[ $p == "yes" ]];then for i in $(awk '{print $1}' ssh_error.txt) ;do sed  -i "/$i/d" host_ip.txt ;done;else exit 1;fi
    else 
        printf "ssh all ok\n"
    fi
    for c in $(awk '{print $NF}' host_ip.txt);do
        host_ssh ${c}
    done

    paste host_ip.txt host_cpu.txt host_cpurate.txt host_mem.txt| sed '1iname address cpu_num cpu_load memory' |column -t > ret.txt
    host_num
}

function cluster_handler() {

    CLUSTER_JSON="cluster.json"
    CLUSTER_URL="http://${ACP_IP}/apis/platform.tkestack.io/v1/clusters"

    url_handler ${CLUSTER_URL}
    curl -sk ${CLUSTER_URL}  -H "Authorization:Bearer ${TOKEN}"  | jq . > ${CLUSTER_JSON}

}

function main() {

    set -eu

    cluster_handler
    host_ips
    host_handler
    
    printf "Cluster Status: \n";cat ret.txt
    printf "Disk Useage: \n";cat host_disk.txt
    printf "All Cluster number: \n";cat host_num.txt
}

ACP_IP="192.168.1.10"
TOKEN="eyJhbGciOiJSUzI1NiIsImtpZCI6IjMyZWQ5NmZiM2U0YzkyYmExNDM4ZDQxOTcxMTA2YTdjZTlmNjE0NjIifQ.eyJpc3MiOiJodHRwczovLzE5Mi4xNjguMS4xMC9kZXgiLCJzdWIiOiJDaVF3T0dFNE5qZzBZaTFrWWpnNExUUmlOek10T1RCaE9TMHpZMlF4TmpZeFpqVTBOallTQld4dlkyRnMiLCJhdWQiOiJhbGF1ZGEtYXV0aCIsImV4cCI6MTc2MDc3MzMwNiwiaWF0IjoxNjAzMDg5NzA2LCJub25jZSI6ImFsYXVkYS1jb25zb2xlIiwiYXRfaGFzaCI6Im1ib2Vmc3VHd29HbzhuNEN1QUdXUEEiLCJlbWFpbCI6ImFkbWluQGNwYWFzLmlvIiwiZW1haWxfdmVyaWZpZWQiOnRydWUsIm5hbWUiOiLnrqHnkIblkZgiLCJleHQiOnsiaXNfYWRtaW4iOnRydWUsImNvbm5faWQiOiJsb2NhbCJ9fQ.iRFJw8JTu9eAw_QrzIh9ayh1J1WLY0Z1M4OYLKpOmqXl9oS6XN-YrhNnw3YTSq770OsZWcM85uAqdi4LTGZQ_DsmanQs3_6ZDZ4Ano6zv5VEISRPAVbg82JV6JVJ__Ee68Kg-CQnRCY5HeE6D3vO0WL5t9pofhGWp2q-zq6CFGL_CPMMQW0bKnRPQxk7f-Dl7a-roGKDfoyQJH4Lpx-SrYOunqNWM6z9mpTILYWwf8VYSkEwKGLHFo0zOWFAl9UUJe_jqavCaIwJqLA-B_IzJNnPFkqRUyR5Z1VVIwam8xxRFmLVhdy_NX4eJilnLO_y7WRlgdLJqdwfM79-C8de3g"

main