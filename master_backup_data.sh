#!/bin/bash

LOCAL_IP=$(/usr/sbin/ifconfig eth0 | awk '/inet/ {print $2}')
BAK_DIR=/data/server/etcd/backup
BAK_DATE=$(date '+%Y%m%d%H%M%S')
BAK_FILE=etcd_backup_data_${BAK_DATE}.db

#set -eu
source /etc/profile
# 备份etcd
ETCDCTL_API=3 etcdctl --endpoints=https://${LOCAL_IP}:2379 \
--cacert=/etc/kubernetes/pki/ca/ca.crt \
--cert=/etc/kubernetes/pki/server/kubernetes.crt \
--key=/etc/kubernetes/pki/server/kubernetes.key \
snapshot save ${BAK_DIR}/${BAK_FILE}

# 备份kubernetes工作目录
cp -rf /etc/kubernetes ${BAK_DIR}/kubernetes.${BAK_DATE}

# 打包
zip ${BAK_DIR}/master_backup_data_${BAK_DATE}.zip ${BAK_DIR}/kubernetes.${BAK_DATE} ${BAK_DIR}/${BAK_FILE} && \
rm -rf ${BAK_DIR}/kubernetes.${BAK_DATE} ${BAK_DIR}/${BAK_FILE}

# 保留14天备份 
find ${BAK_DIR} -name "master_backup_data_*.zip" -type f -mtime +14 -exec rm -f {} \;