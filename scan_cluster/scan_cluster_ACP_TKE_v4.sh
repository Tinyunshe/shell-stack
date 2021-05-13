#!/bin/bash
# Version 4.0

function log::info() {

    printf "\033[32mINFO   \033[0m $(date '+%Y-%m-%d %H:%M:%S.%N')] ${@}\n"

}

function log::error() {

    printf "\033[31mERROR  \033[0m $(date '+%Y-%m-%d %H:%M:%S.%N')] ${@}\n"

}

function log::warning() {

    printf "\033[33mWARNING\033[0m $(date '+%Y-%m-%d %H:%M:%S.%N')] ${@}\n"

}

function check::run_check() {

    ## Basic operation environment check
    local package=(jq sshpass)

    # user check
    if (($(id|awk -F '[()= ]+' '{print $2}') != 0));then log:error "user must be root!";exit 1;fi
    log::info "uid check"
    # package check
    for p in ${package[@]};do if ! command -v ${p} &> /dev/null;then log::error "${p} not exist, ${p} installation is required";exit 1;fi;done
    log::info "package check"

}

function check::file_check() {

    ## Data file check
    local FILE_NAME=${1}

    if [ -e ${FILE_NAME} ];then > ${FILE_NAME};else touch ${FILE_NAME};fi

}

function check::url_check() {

    ## HTTP response code check
    ## If $2 is skip, it will be ignored and can continue
    local URL=${1}
    local ACTION=${2:-'false'}
    local HTTP_CODE=$(curl -s -k -m 5 -o /dev/null -w %{http_code} ${URL} -H "Authorization:Bearer ${TOKEN}")

    if [ "${ACTION}" == "skip" ];then
        if ((${HTTP_CODE} >= 308 || ${HTTP_CODE} == 000 ));then log::error "${URL} connect failed, http code: ${HTTP_CODE}, skip";return 1;fi
    else
        if ((${HTTP_CODE} >= 308 || ${HTTP_CODE} == 000 ));then log::error "${URL} connect failed, http code: ${HTTP_CODE}";exit 1;fi
    fi
   
}

function ssh_handler::check() {

    ## SSH checks all server
    ## 1. no password login
    ## 2. try password login
    local IPS_LIST=$*

    for i in ${IPS_LIST};do
        if ssh -o ConnectTimeout=2 -o ConnectionAttempts=2 -o PasswordAuthentication=no -o StrictHostKeyChecking=no ${i} "echo ping" &> /dev/null;then
            log::info "${i} ping pong"
            continue
        else 
            if [[ -n ${SSH_PASSWORD_FILE} && -s ${SSH_PASSWORD_FILE} ]];then
                log::warning "${i} ssh authorized failed"
                c=1
                for pwd in $(cat ${SSH_PASSWORD_FILE});do
                    log::warning "trying ${c} password"
                    if sshpass -p "${pwd}" ssh -o ConnectTimeout=2 -o ConnectionAttempts=2 -o StrictHostKeyChecking=no ${i} "echo ping" &> /dev/null;then
                        log::info "${i} trying ssh password ping pong" && printf "${i} ${pwd}\n" >> ${SSH_TMP_TXT}
                        continue 2
                    fi
                    let "c++"
                done
            fi
            log::error "${i} ssh failed" && printf "${i}\n" >> ${SSH_ERROR_TXT}
        fi
    done

}

function ssh_handler::ask() {

    ## There is a server with SSH failure. Ask if you want to continue
    if [ -s ${SSH_ERROR_TXT} ];then 
        log::warning "ssh connection has problem\n\nSSH failed machine list:"
        cat ${SSH_ERROR_TXT} && printf "\n"
        log::warning "skip the ssh failed machines continue to scan the cluster? (yes/no)" && read -p "-> " p
        if [ ${p} != "yes" ];then exit 1;fi
    else 
        log::info "ssh all ok"
    fi

}

function ssh_handler::exec_fetch_metrics() {

    ## SSH to each server to get index data
    local HOST=${1}

    ## If the server fails in the SSH check phase, the print indicator is listed as ssh_error

    log::info "ssh ${HOST} exec fetching"
    if [[ -s ${SSH_ERROR_TXT} && $(grep -w "${HOST}" ${SSH_ERROR_TXT}) ]];then
        printf "ssh_error\n" >> ${HOST_CPU_RATE_TXT}
        printf "ssh_error\n" >> ${HOST_MEM_TXT}
        printf "${HOST}: ssh_error\n" >> ${HOST_DISK_TXT}
        printf "${HOST}: ssh_error\n" >> ${HOST_TIME_TXT}
        return 1
    fi

    ## If there is a server trying to log in with a password during the SSH check phase, the password variable will be assigned
    set +u
    if [[ -s ${SSH_TMP_TXT} && $(grep -w ${HOST} ${SSH_TMP_TXT}) ]];then
        local SSH_TMP_PASS=$(grep -w "${HOST}" ${SSH_TMP_TXT}|awk '{print $NF}')
    else
        unset SSH_TMP_PASS
    fi

    ## Get data
    DISK_DATA=$(sshpass -p "${SSH_TMP_PASS}" ssh -o StrictHostKeyChecking=no ${HOST} df -hT / /var/lib/docker /alauda-data /alauda_data /alaudadata /cpaas /data 2> /dev/null|awk -v n=${HOST} 'BEGIN {print n":"} NR>1{print $NF,$(NF-1)}'|xargs|column -t)
    echo "${DISK_DATA}" >> ${HOST_DISK_TXT}
    sshpass -p "${SSH_TMP_PASS}" ssh -o StrictHostKeyChecking=no ${HOST} "echo ${HOST}: $(date '+%Y-%m-%d %H:%M:%S')" >> ${HOST_TIME_TXT}
    sshpass -p "${SSH_TMP_PASS}" ssh -o StrictHostKeyChecking=no ${HOST} "uptime | awk '{print \$NF}'" >> ${HOST_CPU_RATE_TXT}
    sshpass -p "${SSH_TMP_PASS}" ssh -o StrictHostKeyChecking=no ${HOST} free -m|awk -F '[ :]+' 'NR==2{printf "%d%\n", ($2-$7)/$2*100}' >> ${HOST_MEM_TXT}
    set -u

}

function ssh_handler::exec_check_cert_file() {

    ## SSH each server check cert file
    local HOST=${1}

    log::info "ssh ${HOST} check cert file"
    if [[ -s ${SSH_ERROR_TXT} && $(grep -w "${HOST}" ${SSH_ERROR_TXT}) ]];then
        sed -i "/${HOST}/a ssh_error" ${THEY_ARE_MASTER_TXT}
        return
    fi

    set +u
    if [[ -s ${SSH_TMP_TXT} && $(grep -w ${HOST} ${SSH_TMP_TXT}) ]];then
        local SSH_TMP_PASS=$(grep -w "${HOST}" ${SSH_TMP_TXT}|awk '{print $NF}')
    else
        unset SSH_TMP_PASS
    fi

    check::file_check ${DATE_DIR}/${HOST}_date_A.txt
    check::file_check ${DATE_DIR}/${HOST}_date_B.txt
    sshpass -p "${SSH_TMP_PASS}" ssh ${HOST} "for item in \$(find /etc/kubernetes/pki -maxdepth 2 -name '*.crt');do printf \"\${item} \";openssl x509 -in \$item -dates -noout |xargs ;done" | \
    awk -F '[= ]+' '{print $1,$6,$3,$4,$5,"->",$(NF-1),$9,$10,$11}' > ${DATE_DIR}/${HOST}_date_B.txt

    set -u

    while read line;do
        GET_CMD=$(printf "${line}"|awk '{print $(NF-2),$(NF-1),$NF,$(NF-3)}')
        EXPIRED_DATE=$(date -d "${GET_CMD}" +%s)
        TODAY_DATE=$(date '+%s')
        DIFF_DATE=$(( (${EXPIRED_DATE}-${TODAY_DATE})/86400 ))

        if ((${DIFF_DATE} <= 15));then
            printf "\033[31m%s\033[0m %s %s %s %s %s %s %s %s %s\n" ${line} >> ${DATE_DIR}/${HOST}_date_A.txt
        elif ((${DIFF_DATE} <= 60));then
            printf "\033[33m%s\033[0m %s %s %s %s %s %s %s %s %s\n" ${line} >> ${DATE_DIR}/${HOST}_date_A.txt
        else
            printf "${line}\n" >> ${DATE_DIR}/${HOST}_date_A.txt
        fi
    done < ${DATE_DIR}/${HOST}_date_B.txt

    > ${DATE_DIR}/${HOST}_date_B.txt
    cat ${DATE_DIR}/${HOST}_date_A.txt |column -t > ${DATE_DIR}/${HOST}_date_B.txt
    printf "\n" >> ${DATE_DIR}/${HOST}_date_B.txt

    sed -i "/${HOST}/r ${DATE_DIR}/${HOST}_date_B.txt" ${THEY_ARE_MASTER_TXT}

}

function jq_handler::host_num() {

    ## Calculate the number of clusters by returning JSON of cluster interface
    HOST_COUNT=$(cat ${CLUSTER_JSON}|jq -r '.items[].metadata.name'|wc -l)

    printf "${HOST_COUNT}\n" > ${HOST_NUM_TXT}

}

function jq_handler::cluster_json() {

    ## Get the return JSON of the container platform cluser interface
    ## JQ intercepts each cluster name
    log::info "geting ${CLUSTER_URL} cluster interface"
    check::url_check ${CLUSTER_URL}
    curl -sk ${CLUSTER_URL}  -H "Authorization:Bearer ${TOKEN}"  | jq . > ${CLUSTER_JSON}
    cat ${CLUSTER_JSON}|jq -r '.items[].metadata.name' > ${HOST_LIST_TXT}

}

function scan-server::cut_nodes_json() {

    ## Get the returned JSON of nodes interface of container platform by traversing the cluster name
    ## JQ intercepts the index data of each server
    for h in $(cat ${HOST_LIST_TXT});do
        NODES_URL="${PRE_URL}/kubernetes/${h}/api/v1/nodes"
        log::info "geting ${NODES_URL} nodes interface"

        if ! check::url_check ${NODES_URL} skip;then 
            continue
        fi
        
        check::file_check ${DATE_DIR}/${h}_host_ip.txt
        curl -sk ${NODES_URL} -H "Authorization:Bearer ${TOKEN}" | jq . > ${DATE_DIR}/${h}.json

        CPU_NUM=$(cat ${DATE_DIR}/${h}.json | jq -r '.items[].status.capacity.cpu')
        IPS=$(cat ${DATE_DIR}/${h}.json | jq -r '.items[].status.addresses[0].address')

        printf "${CPU_NUM}\n" >> ${HOST_CPU_NUM_TXT}
        printf "${IPS}\n" >> ${DATE_DIR}/${h}_host_ip.txt && sed -i "s#^#${h} #" ${DATE_DIR}/${h}_host_ip.txt
        cat ${DATE_DIR}/${h}_host_ip.txt >> ${HOST_IP_TXT}
    done

}

function scan-server::ssh_host() {

    ## SSH check
    IPS_LIST=$(awk '{print $NF}' ${HOST_IP_TXT})

    ssh_handler::check ${IPS_LIST}

    ssh_handler::ask

    ## SSH to each server to obtain index data
    for c in ${IPS_LIST};do
        if ! ssh_handler::exec_fetch_metrics ${c};then continue;fi
    done

    ## Merge the data into ret.txt
    paste ${HOST_IP_TXT} ${HOST_CPU_NUM_TXT} ${HOST_CPU_RATE_TXT} ${HOST_MEM_TXT}| sed '1icluster_name address cpu_num cpu_load memory' |column -t > ${RET_TXT}

}

function scan-server::display() {

    ## Display scan data
    sleep 3;log::info "displaying it now"
    printf "Server Status: \n";cat ${RET_TXT}
    printf "\nDisk Useage: \n";cat ${HOST_DISK_TXT} |column -t
    printf "\nAll machines time: \n";cat ${HOST_TIME_TXT} |column -t
    printf "\nTotal Cluster number: \n";cat ${HOST_NUM_TXT}

}

function scan-server::start() {

    ## Initialize global variables
    log::info "start scan-server program"

    ## Environmental inspection before operation
    check::run_check

    ## Mkdir scan dir
    ## Initialize patrol file data in patrol directory
    DATE_DIR="/tmp/scan-server-$(date +'%y%m%d%H%M%S')"
    if [ ! -e ${DATE_DIR} ];then mkdir -p ${DATE_DIR};fi

    CLUSTER_JSON="${DATE_DIR}/cluster.json";check::file_check ${CLUSTER_JSON}
    HOST_LIST_TXT="${DATE_DIR}/host_list.txt";check::file_check ${HOST_LIST_TXT}
    RET_TXT="${DATE_DIR}/ret.txt";check::file_check ${RET_TXT}
    HOST_IP_TXT="${DATE_DIR}/host_ip.txt";check::file_check ${HOST_IP_TXT}
    HOST_CPU_NUM_TXT="${DATE_DIR}/host_cpu_num.txt";check::file_check ${HOST_CPU_NUM_TXT}
    HOST_CPU_RATE_TXT="${DATE_DIR}/host_cpu_rate.txt";check::file_check ${HOST_CPU_RATE_TXT}
    HOST_MEM_TXT="${DATE_DIR}/host_mem.txt";check::file_check ${HOST_MEM_TXT}
    HOST_NUM_TXT="${DATE_DIR}/host_num.txt";check::file_check ${HOST_NUM_TXT}
    HOST_DISK_TXT="${DATE_DIR}/host_disk.txt";check::file_check ${HOST_DISK_TXT}
    HOST_TIME_TXT="${DATE_DIR}/host_time.txt";check::file_check ${HOST_TIME_TXT}
    SSH_ERROR_TXT="${DATE_DIR}/ssh_error.txt";check::file_check ${SSH_ERROR_TXT}
    SSH_TMP_TXT="${DATE_DIR}/ssh_tmp.txt";check::file_check ${SSH_TMP_TXT}

}

function scan-cert-file::find_master() {

    for m in $(cat ${HOST_LIST_TXT});do
        NODES_URL="${PRE_URL}/kubernetes/${m}/api/v1/nodes"
        log::info "geting ${NODES_URL} nodes interface"

        if ! check::url_check ${NODES_URL} skip;then 
            continue
        fi
        curl -sk ${NODES_URL} -H "Authorization:Bearer ${TOKEN}" | jq . > ${DATE_DIR}/${m}.json

        paste <(cat ${DATE_DIR}/${m}.json |jq  -r '.items[].status.addresses[0].address') \
        <(cat ${DATE_DIR}/${m}.json | jq  -r '.items[].metadata.labels | has("node-role.kubernetes.io/master")') | \
        grep -v "false" |sed "1i${m}:" |awk '{print $1}' >> ${THEY_ARE_MASTER_TXT}
    done

}

function scan-cert-file::ssh_host() {

    IPS_LIST=$(grep -v : ${THEY_ARE_MASTER_TXT})

    ssh_handler::check ${IPS_LIST}

    ssh_handler::ask

    for e in ${IPS_LIST};do
        if ! ssh_handler::exec_check_cert_file ${e};then continue;fi
    done

}

function scan-cert-file::start() {
    
    log::info "start scan-cert-file program"

    check::run_check

    DATE_DIR="/tmp/scan-cert-file-$(date +'%y%m%d%H%M%S')"
    if [ ! -e ${DATE_DIR} ];then mkdir -p ${DATE_DIR};fi

    CLUSTER_JSON="${DATE_DIR}/cluster.json";check::file_check ${CLUSTER_JSON}
    HOST_LIST_TXT="${DATE_DIR}/host_list.txt";check::file_check ${HOST_LIST_TXT}
    THEY_ARE_MASTER_TXT="${DATE_DIR}/they_are_master.txt";check::file_check ${THEY_ARE_MASTER_TXT}
    SSH_ERROR_TXT="${DATE_DIR}/ssh_error.txt";check::file_check ${SSH_ERROR_TXT}
    SSH_TMP_TXT="${DATE_DIR}/ssh_tmp.txt";check::file_check ${SSH_TMP_TXT}

}

function init::get_opts() {

    ## Script options
    > /tmp/opts.txt
    ARGS=$(getopt -o h:t:f: --long host:,token:,password-file:,scan-server,scan-cert-file,kubectl,clean,help -- "$@" 2> /tmp/opts.txt)
    if [ -s /tmp/opts.txt ];then log::error "args error, use --help to see usage";exit 1;fi

    eval set -- ${ARGS}
    while :;do
        case "$1" in
            -h|--host) CLUSTER_URL=${2};shift 2;;
            -t|--token) TOKEN=${2};shift 2;;
            -f|--password-file) SSH_PASSWORD_FILE=${2};shift 2;;
            --clean) CLEAN_DATA="true";shift;;
            --scan-server) SCAN_SERVER="true";shift;;
            --scan-cert-file) SCAN_CERT_FILE="true";shift;;
            # --kubectl) SCAN_KUBE=true;shift;;
            --help) printf "
bash scan.sh [options].. {flags}    

    --scan-server : get host ip address, cpu, memory, disk, time and other data
    --scan-cert-file : get kubernetes cert of master host, about expired
    -h,--host : cluster interface of TKE or ACP platform url address
    -t,--token : platform token
    -f,--password-file : if the cluster can not log in without password, you can specify the password file to try to login
    --clean : clean up data directory
    --help : help information    

"
              exit;;
              --) shift;break;;
           esac
        done

}

function init::over() {

    if [ "${CLEAN_DATA}s" == "trues" ];then
        if [[ -n ${DATE_DIR} && -e ${DATE_DIR} ]];then
            rm -rf ${DATE_DIR}
            log::info "clean up data directory: ${DATE_DIR}"
        else
            log::info "${DATE_DIR} not exist"
        fi
    fi

}

function init::env() {

    init::get_opts $*

    if [ -z ${CLUSTER_URL} ];then log::error "platform url address not set";exit 1;fi
    if [ -z ${TOKEN} ];then log::error "token not set";exit 1;fi
    SSH_PASSWORD_FILE=${SSH_PASSWORD_FILE:-''}
    PRE_URL=${CLUSTER_URL%%/a*}

    if [ "${SCAN_SERVER}s" == "trues" ];then
        set -eu
        scan-server::start
        jq_handler::cluster_json
        scan-server::cut_nodes_json
        jq_handler::host_num
        scan-server::ssh_host
        scan-server::display|more
        set +eu
        return
    fi

    if [ "${SCAN_CERT_FILE}s" == "trues" ];then
        set -eu
        scan-cert-file::start
        jq_handler::cluster_json
        scan-cert-file::find_master
        scan-cert-file::ssh_host
        cat ${THEY_ARE_MASTER_TXT}|more
        set +eu
        return
    fi

}

function main() {

    init::env $*
    init::over

}

main $*