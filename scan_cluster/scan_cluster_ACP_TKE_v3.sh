#!/bin/bash
# 版本 Version 3.0

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

## 基础运行条件检查
    local package=(jq sshpass)

    # user check
    if (($(id|awk -F '[()= ]+' '{print $2}') != 0));then log:error "user must be root!";exit 1;fi
    log::info "uid check"
    # package check
    for p in ${package[@]};do if ! command -v ${p} &> /dev/null;then log::error "${p} not exist, ${p} installation is required";exit 1;fi;done
    log::info "package check"

}

function check::file_check() {

## 数据文件检查
    local FILE_NAME=$1

    if [ -e ${FILE_NAME} ];then > ${FILE_NAME};else touch ${FILE_NAME};fi

}

function check::url_check() {

##  http返回码检查
    local URL=$1
    local HTTP_CODE=$(curl -s -k -m 5 -o /dev/null -w %{http_code} ${URL} -H "Authorization:Bearer ${TOKEN}")

    if ((${HTTP_CODE} >= 308 || ${HTTP_CODE} == 000 ));then log::error "${URL} connect failed, http code: ${HTTP_CODE}";exit 1;fi
   
}

function ssh_handler::check() {

## ssh检查各个服务器
## 1. 免密登陆检查
## 2. 尝试密码登陆检查
## 3. 以上两种方式登陆检查不通过的话将进入交互询问
## 4. 交互询问选择是否跳过ssh失败的服务器(yes/no)
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

    if [ -s ${SSH_ERROR_TXT} ];then 
        log::warning "ssh connection has problem\n\nSSH failed machine list:"
        cat ${SSH_ERROR_TXT} && printf "\n"
        log::warning "skip the ssh failed machines continue to scan the cluster? (yes/no)" && read -p "-> " p
        if [ ${p} != "yes" ];then exit 1;fi
    else 
        log::info "ssh all ok"
    fi

}

function ssh_handler::exec_fetch() {

## ssh到各个服务器获取指标数据
    local HOST=$1

## 如果在ssh检查阶段失败的服务器，将打印指标列为ssh_error
    log::info "ssh ${HOST} exec fetching"
    if [[ -s ${SSH_ERROR_TXT} && $(grep -w "${HOST}" ${SSH_ERROR_TXT}) ]];then
        printf "ssh_error\n" >> ${HOST_CPU_RATE_TXT}
        printf "ssh_error\n" >> ${HOST_MEM_TXT}
        printf "${HOST}: ssh_error\n" >> ${HOST_DISK_TXT}
        printf "${HOST}: ssh_error\n" >> ${HOST_TIME_TXT}
        return 1
    fi

## 如果在ssh检查阶段存在尝试密码登陆的服务器，将赋值密码变量
    set +u
    if [[ -s ${SSH_TMP_TXT} && $(grep -w ${HOST} ${SSH_TMP_TXT}) ]];then
        local SSH_TMP_PASS=$(grep -w "${HOST}" ${SSH_TMP_TXT}|awk '{print $NF}')
    else
        unset SSH_TMP_PASS
    fi

## 获取数据
    DISK_DATA=$(sshpass -p "${SSH_TMP_PASS}" ssh -o StrictHostKeyChecking=no ${HOST} df -hT / /var/lib/docker /alauda-data /alauda_data /alaudadata /cpaas /data 2> /dev/null|awk -v n=${HOST} 'BEGIN {print n":"} NR>1{print $NF,$(NF-1)}'|xargs|column -t)
    echo "${DISK_DATA}" >> ${HOST_DISK_TXT}
    sshpass -p "${SSH_TMP_PASS}" ssh -o StrictHostKeyChecking=no ${HOST} "echo ${HOST}: $(date '+%Y-%m-%d %H:%M:%S')" >> ${HOST_TIME_TXT}
    sshpass -p "${SSH_TMP_PASS}" ssh -o StrictHostKeyChecking=no ${HOST} "uptime | awk '{print \$NF}'" >> ${HOST_CPU_RATE_TXT}
    sshpass -p "${SSH_TMP_PASS}" ssh -o StrictHostKeyChecking=no ${HOST} free -m|awk -F '[ :]+' 'NR==2{printf "%d%\n", ($2-$7)/$2*100}' >> ${HOST_MEM_TXT}
    set -u

}

function jq_handler::host_num() {

## 通过cluster接口的返回json计算集群各数
    HOST_COUNT=$(cat ${CLUSTER_JSON}|jq '.items[].metadata.name'|tr -d '"'|wc -l)

    printf "${HOST_COUNT}\n" > ${HOST_NUM_TXT}

}

function jq_handler::nodes_json() {

## 通过遍历集群名称获取容器平台nodes接口的返回json
## jq截取各个服务器的指标数据
    for h in $(cat ${HOST_LIST_TXT});do
        NODES_URL="${HTTP_TYPE}://${ACP_IP}/kubernetes/${h}/api/v1/nodes"
        log::info "geting ${NODES_URL} nodes interface"
        check::url_check ${NODES_URL}
        check::file_check ${DATE_DIR}/${h}_host_ip.txt
        curl -sk ${NODES_URL} -H "Authorization:Bearer ${TOKEN}" | jq . > ${DATE_DIR}/${h}.json
        CPU_NUM=$(cat ${DATE_DIR}/${h}.json | jq '.items[].status.capacity.cpu' | tr -d '"')
        IPS=$(cat ${DATE_DIR}/${h}.json | jq '.items[].status.addresses[0].address' | tr -d '"')
        printf "${CPU_NUM}\n" >> ${HOST_CPU_NUM_TXT}
        printf "${IPS}\n" >> ${DATE_DIR}/${h}_host_ip.txt && sed -i "s#^#${h} #" ${DATE_DIR}/${h}_host_ip.txt
        cat ${DATE_DIR}/${h}_host_ip.txt >> ${HOST_IP_TXT}
    done

    jq_handler::host_num

}

function jq_handler::cluster_json() {

## 获取容器平台cluser接口的返回json
## jq截取各个集群名称
    log::info "geting ${CLUSTER_URL} cluster interface"
    check::url_check ${CLUSTER_URL}
    curl -sk ${CLUSTER_URL}  -H "Authorization:Bearer ${TOKEN}"  | jq . > ${CLUSTER_JSON}
    cat ${CLUSTER_JSON}|jq '.items[].metadata.name'|tr -d '"' > ${HOST_LIST_TXT}

}

function run::ssh_host() {

## 进行ssh检查
    IPS_LIST=$(awk '{print $NF}' ${HOST_IP_TXT})

    ssh_handler::check ${IPS_LIST}

## 进行ssh到各个服务器获取指标数据
    for c in ${IPS_LIST};do
        if ! ssh_handler::exec_fetch ${c};then continue;fi
    done

## 将各个数据合并到ret.txt
    paste ${HOST_IP_TXT} ${HOST_CPU_NUM_TXT} ${HOST_CPU_RATE_TXT} ${HOST_MEM_TXT}| sed '1icluster_name address cpu_num cpu_load memory' |column -t > ${RET_TXT}

}

function run::display() {

## 展示巡检数据
    sleep 3;log::info "displaying it now"
    printf "Server Status: \n";cat ${RET_TXT}
    printf "\nDisk Useage: \n";cat ${HOST_DISK_TXT} |column -t
    printf "\nAll machines time: \n";cat ${HOST_TIME_TXT} |column -t
    printf "\nTotal Cluster number: \n";cat ${HOST_NUM_TXT}

}

function run::get_opts() {

## 脚本选项
    > /tmp/opts.txt
    ARGS=$(getopt -o h:t:f: --long host:,token:,password-file:,scan-cert-host:,kubectl,rm,help -- "$@" 2> /tmp/opts.txt)
    if [ -s /tmp/opts.txt ];then log::error "args error, use --help to see usage";exit 1;fi

    eval set -- ${ARGS}
    while :;do
        case "$1" in
            -h|--host) CLUSTER_URL=${2};shift 2;;
            -t|--token) TOKEN=${2};shift 2;;
            -f|--password-file) SSH_PASSWORD_FILE=${2};shift 2;;
            # --scan-cert-host) SCAN_CERT_HOST=${2};shift 2;;
            # --kubectl) SCAN_KUBE=true;shift;;
            --help) printf "
bash scan.sh [options].. {flags}    

    -h,--host : cluster interface of TKE or ACP platform url address
    -t,--token : platform token
    -f,--password-file : if the cluster can not log in without password, you can specify the password file to try to login
    --help : help information    

"
              exit;;
              --) shift;break;;
           esac
        done

}

function run::start() {

## 初始化脚本选项
## 初始化全局变量
    set +eu
    run::get_opts $*
    if [ -z ${CLUSTER_URL} ];then log::error "platform url address not set";exit 1;fi
    if [ -z ${TOKEN} ];then log::error "token not set";exit 1;fi
    SSH_PASSWORD_FILE=${SSH_PASSWORD_FILE:-''}
    HTTP_TYPE="${CLUSTER_URL%%:/*}"
    ACP_IP=$(printf ${CLUSTER_URL}|grep -Eo '(([0-9]{1,3}\.){3}[0-9]{1,3})')
    set -eu

## 运行前环境检查
    check::run_check

## 创建巡检目录
## 在巡检目录中初始化巡检文件数据
    DATE_DIR="/tmp/scan-$(date +'%y%m%d%H%M%S')"
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

function main() {

    set -eu

    run::start $*
    jq_handler::cluster_json
    jq_handler::nodes_json
    run::ssh_host
    run::display|more
    
}

main $*