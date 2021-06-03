#!/bin/bash
# 执行参数，让执行脚本时，带的参数生效
run_function=''
for i in $@
do
    eval $i
done

rm -rf /tmp/tmp

# 备份到/cpaas/backup
back_k8s_file()
{
    ETCD_CONTAINER_NAME=$(docker ps | grep etcd | grep -v POD | awk '{print $1}')
    ETCD_CLIENT_URL=$(docker inspect ${ETCD_CONTAINER_NAME}  -f '{{.Args}}' | sed 's/ /\n /g' | awk '/--advertise-client-urls=/{print}' | sed 's/.*=//')
    docker inspect ${ETCD_CONTAINER_NAME}  -f '{{.Config.Entrypoint}}' | sed 's/ /\n /g' >/tmp/tmp
    CERT_KEY=$(cat /tmp/tmp | awk '/--cert-file=/{print}' | sed 's/.*=//')
    CACERT_KEY=$(cat /tmp/tmp | awk '/--peer-trusted-ca-file=/{print}' | sed 's/.*=//')
    KEY_KEY=$(cat /tmp/tmp | awk '/--key-file=/{print}' | sed 's/.*=//')
    export ETCDCTL_API=3
    BACKUP_LIST_BIN=($(command -v kubeadm) $(command -v kubectl) $(command -v kubelet))
    BACKUP_LIST_DIR=(/root/.helm /root/.kube /opt/cni/bin /etc/kubeadm /etc/kubernetes /etc/cni /var/lib/kubelet/pki)
    BACKUP_LIST_FILE=(/etc/systemd/system/kubelet.service /var/lib/kubelet/config.yaml /var/lib/kubelet/kubeadm-flags.env)
    rm -rf /cpaas/backup
    mkdir -p /cpaas/backup

    for i in ${BACKUP_LIST_BIN[@]} ${BACKUP_LIST_DIR[@]} ${BACKUP_LIST_FILE[@]}
    do
        mkdir -p $(echo /cpaas/backup$i | sed 's#/[a-zA-Z.]*$##')
        cp -Ra $i $(echo /cpaas/backup$i | sed 's#/[a-zA-Z.]*$##')
    done
    docker cp ${ETCD_CONTAINER_NAME}:/usr/local/bin/etcdctl /usr/bin
    back_file_name=$(date +%Y%m%d-%T)-snapshot.db
    /usr/bin/etcdctl --cert=${CERT_KEY} --cacert=${CACERT_KEY} --key=${KEY_KEY} --endpoints ${ETCD_CLIENT_URL} snapshot save /cpaas/backup/${back_file_name}
    tar zcf /cpaas/bak/backup-[$(hostname)]-[$(date +%Y-%m-%d)].tar.gz /cpaas/backup
    
}

# 恢复
recovery_k8s()
{
    for i in /cpaas/backup/*
    do
        for j in ${i}/*
        do
            /usr/bin/cp -Raf ${j} /${i##*/}
        done
    done
    $(whereis -b cp | awk '{print $NF}') -Raf /cpaas/backup/root/.helm /root
    $(whereis -b cp | awk '{print $NF}') -Raf /cpaas/backup/root/.kube /root
}

$run_function