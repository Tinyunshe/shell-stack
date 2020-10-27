#!/bin/bash
# etcd维护脚本，包含常用命令，证书查询，查看是否有备份计划任务

function check_cert_file() {
    cert_file=(
        /etc/kubernetes/pki/etcd/ca.crt
        /etc/kubernetes/pki/etcd/peer.crt
        /etc/kubernetes/pki/etcd/peer.key
    )

    tag=0
    for f in ${cert_file[@]};do
        if [ ! -e $f ];then
            printf "$f is not exist\n"
            let 'tag++'
            continue
        fi
    done
    if (($tag > 0));then return false;fi

    # pass
}

function check_crontab() {
    # pass
}

function status() {
    set +x
    etcdctl \
    --endpoints=$ENDPOINT \
    --cacert /etc/kubernetes/pki/etcd/ca.crt \
    --cert /etc/kubernetes/pki/etcd/peer.crt \
    --key /etc/kubernetes/pki/etcd/peer.key \
    -w table \
    endpoint status
    set -x
}

function health() {
    set +x
    etcdctl \
    --endpoints=$ENDPOINT \
    --cacert /etc/kubernetes/pki/etcd/ca.crt \
    --cert /etc/kubernetes/pki/etcd/peer.crt \
    --key /etc/kubernetes/pki/etcd/peer.key \
    -w table \
    endpoint health
    set -x
}

function useage() {
    printf " \
    参数1: 集群endpoints\n \
    参数2: etcd维护指令\n \
    \t- status: 集群状态，包括etcd数据量\n \
    \t- health: 集群健康检查\n \
    \t- del_nfm: 删除etcd数据中notification告警信息\n \
    "
}

function main() {

    ENDPOINT=${1:-http://127.0.0.1:2379}
    CMD=$2
    export ETCDCTL_API=3
    
    if [[ $ENDPOINT != '^http' ]];then useage;exit 1;fi

    if ! check_cert_file;then printf "etcd证书位置不存在\n";exit 1;fi

    case $CMD in 
    status)
    status
    ;;
    health)
    health
    ;;
    *)
    useage
    ;;
    esac
}

main $*