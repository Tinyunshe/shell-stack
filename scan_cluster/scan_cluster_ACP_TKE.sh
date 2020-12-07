#!/bin/bash
# 版本 Version 2.0
# 按正规环境修改：
# 1. 平台token值
# 2. acp平台访问ip
# 3. http协议类型
# 4. clusters接口url路径

function file_handler() {

    local FILE_NAME=$1

    if [ -e ${FILE_NAME} ];then > ${FILE_NAME};else touch ${FILE_NAME};fi

}

function url_handler() {

    local URL=$1

    if ! curl -sk ${URL} -H "Authorization:Bearer ${TOKEN}" &> /dev/null;then printf "ERROR ${URL} connect failed";exit 1;fi

}

function ssh_check() {

    local IPS_LIST=$*

    file_handler ssh_error.txt
    for i in ${IPS_LIST};do
        if ! ssh -o ConnectTimeout=3 -o ConnectionAttempts=5 -o PasswordAuthentication=no -o StrictHostKeyChecking=no ${i} "echo ping";then
            printf "${i} ssh connect timeout\n" >> ssh_error.txt
            continue
        fi
    done

    if [ -s ssh_error.txt ];then 
        printf "ERROR ssh connection has problem\nssh faild machine list:\n"
        cat ssh_error.txt
        read -p "Skip the ssh failed machines continue to scan the cluster? (yes/no)" p
        if [ ${p} != "yes" ];then exit 1;fi
    else 
        printf "ssh all ok\n"
    fi

}

function ssh_exec() {

    local HOST=$1

    if [[ -s ssh_error.txt && $(awk '{print $1}' ssh_error.txt|grep -w "${HOST}") ]];then
        printf "ssh_error\n" >> host_cpurate.txt
        printf "ssh_error\n" >> host_mem.txt
        printf "${HOST}: ssh_error\n" >> host_disk.txt
        printf "${HOST}: ssh_error\n" >> host_time.txt
        return 1
    fi

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
    DISK_DATA=$(ssh ${HOST} df -hT / /var/lib/docker /alauda-data /alauda_data /alaudadata /cpaas /data 2> /dev/null|awk -v n=${HOST} 'BEGIN {print n":"} NR>1{print $NF,$(NF-1)}'|xargs|column -t)
    echo "${DISK_DATA}" >> host_disk.txt
    ssh ${HOST} "echo ${HOST}: $(date '+%Y-%m-%d %H:%M:%S')" >> host_time.txt
    ssh ${HOST} "uptime | awk '{print \$NF}'" >> host_cpurate.txt
    ssh ${HOST} "bash /tmp/check_mem.sh && rm -f /tmp/check_mem.sh" >> host_mem.txt

}

function host_num() {

    HOST_COUNT=$(cat ${CLUSTER_JSON}|jq '.items[].metadata.name'|tr -d '"'|wc -l)

    file_handler host_num.txt
    printf "${HOST_COUNT}\n" > host_num.txt

}

function host_jq_handler() {

    HOST_LIST=$(cat ${CLUSTER_JSON}|jq '.items[].metadata.name'|tr -d '"')

    file_handler host_ip.txt
    file_handler host_cpu.txt
    for h in ${HOST_LIST};do
        RESOURCE_URL="${HTTP_TYPE}://${ACP_IP}/kubernetes/${h}/api/v1/nodes"
        url_handler ${RESOURCE_URL}
        file_handler ${h}_host_ip.txt
        curl -sk ${RESOURCE_URL} -H "Authorization:Bearer ${TOKEN}" | jq . > ${h}.json
        CPU_NUM=$(cat ${h}.json | jq '.items[].status.capacity.cpu' | tr -d '"')
        IPS=$(cat ${h}.json | jq '.items[].status.addresses[0].address' | tr -d '"')
        printf "${CPU_NUM}\n" >> host_cpu.txt
        printf "${IPS}\n" >> ${h}_host_ip.txt && sed -i "s#^#${h} #" ${h}_host_ip.txt
        cat ${h}_host_ip.txt >> host_ip.txt
    done

    host_num

}

function host_ssh_handler() {

    IPS_LIST=$(awk '{print $NF}' host_ip.txt)

    file_handler host_mem.txt
    file_handler host_cpurate.txt
    file_handler host_disk.txt
    file_handler host_time.txt

    ssh_check ${IPS_LIST}

    for c in ${IPS_LIST};do
        if ! ssh_exec ${c};then continue;fi
    done

}

function cluster_handler() {

    CLUSTER_JSON="cluster.json"

    url_handler ${CLUSTER_URL}
    curl -sk ${CLUSTER_URL}  -H "Authorization:Bearer ${TOKEN}"  | jq . > ${CLUSTER_JSON}

}

function display() {

    paste host_ip.txt host_cpu.txt host_cpurate.txt host_mem.txt| sed '1iname address cpu_num cpu_load memory' |column -t > ret.txt
    printf "Cluster Status: \n";cat ret.txt
    printf "\nDisk Useage: \n";cat host_disk.txt
    printf "\nAll machines time: \n";cat host_time.txt
    printf "\nTotal Cluster number: \n";cat host_num.txt

}

function main() {

    set -eu

    cluster_handler
    host_jq_handler
    host_ssh_handler
    display|more
    
}

ACP_IP="192.168.1.10"
HTTP_TYPE="http"
CLUSTER_URL="${HTTP_TYPE}://${ACP_IP}/apis/platform.tkestack.io/v1/clusters"
TOKEN="eyJhbGciOiJSUzI1NiIsImtpZCI6IjMyZWQ5NmZiM2U0YzkyYmExNDM4ZDQxOTcxMTA2YTdjZTlmNjE0NjIifQ.eyJpc3MiOiJodHRwczovLzE5Mi4xNjguMS4xMC9kZXgiLCJzdWIiOiJDaVF3T0dFNE5qZzBZaTFrWWpnNExUUmlOek10T1RCaE9TMHpZMlF4TmpZeFpqVTBOallTQld4dlkyRnMiLCJhdWQiOiJhbGF1ZGEtYXV0aCIsImV4cCI6MTc1NzE1MDUwNiwiaWF0IjoxNTk5NDcwNTA2LCJub25jZSI6ImFsYXVkYS1jb25zb2xlIiwiYXRfaGFzaCI6IlBtTEc0UTFESGgxaGM2V0hmamNRQ2ciLCJlbWFpbCI6ImFkbWluQGNwYWFzLmlvIiwiZW1haWxfdmVyaWZpZWQiOnRydWUsIm5hbWUiOiLnrqHnkIblkZgiLCJleHQiOnsiaXNfYWRtaW4iOnRydWUsImNvbm5faWQiOiJsb2NhbCJ9fQ.qyKGpAg2XBOs9tGChnLyA6C_NOiXTr96JwBoZTieV3cxGqJwildrSMWHwSJQD4Mxs8qic1ujJChNjaUYhpmMCaFyCKf4xiEkFXahrVPJ_Rwnqhdv5vm1hrj_rdalinSxxakD_-HZdlFyk3APqGHQJLkMKlSGUAVI1q0UuRFbaZbO5SwP82InJp845Ecoe6IraA41TtIoMCHhWoSr-wAU7n1oa1NubwXNNKHF_ITR1E2XXLosDDllfSP_KJqIlXj5eT1Cdi-e6BPuNbtMj-pEzF2nKVPS4G1v5ihsN-4Sa8NEZuSW_FWq8eK7u9HgLPMYPQPTG-EiUeusF0HGSmfuQw"

main