#!/bin/bash

set -eu

# env
ADDRESS=http://192.168.15.174:30199
NEXUS_USER=admin
NEXUS_PASSWORD=1qaz@WSX
NEXUS_INSTANCE_NAME=nexus-new-km6tz
TASK_NAME=database-backup
TASK_BAK_DIR=/nexus-data/backup/database-backup
LOCAL_BAK_DIR=/root/stwu/nexus-backup
DAY="7"

# env(do not modify)
LOG_FILE=${LOCAL_BAK_DIR}/backup.log
TASK_ID=$(curl -su ${NEXUS_USER}:${NEXUS_PASSWORD} ${ADDRESS}/service/rest/v1/tasks -H 'accept: application/json' |jq -r --arg n "${TASK_NAME}" '.items[] | select(.name == $n) |.id')

# base
printf "$(date) base\n" >> ${LOG_FILE}
if [ ! -e ${LOCAL_BAK_DIR} ];then printf "local bak dir ${LOCAL_BAK_DIR} not exist\n";exit 1;fi >> ${LOG_FILE}
if ! jq &> /dev/null;then printf "jq command not found\n";exit 1;fi >> ${LOG_FILE}

# 获取 Nexus pod 名称和 namespace 信息
read NEXUS_NS NEXUS_POD_NAME <<< $(kubectl get pod --all-namespaces|awk "/${NEXUS_INSTANCE_NAME}/{print\$1,\$2}")

# 执行备份元数据 task, 并归档元数据备份数据
printf "$(date) run task\n" >> ${LOG_FILE}
TASK_HTTP_CODE=$(curl -X POST -w "%{http_code}" -o /dev/null -su  ${NEXUS_USER}:${NEXUS_PASSWORD} ${ADDRESS}/service/rest/v1/tasks/${TASK_ID}/run)
if [[ ! ${TASK_HTTP_CODE} == "204" ]];then 
printf "Task: ${TASK_NAME}, run failed\nTask respone http code: ${TASK_HTTP_CODE}\n"
exit 1
fi >> ${LOG_FILE}
kubectl -n ${NEXUS_NS} exec ${NEXUS_POD_NAME} -- sh -c "cd ${TASK_BAK_DIR} && tar zcf database-backup.tar ./*"

# 拷贝元数据到本地
printf "$(date) copy orientDB data to ${LOCAL_BAK_DIR}\n" >> ${LOG_FILE}
kubectl cp ${NEXUS_NS}/${NEXUS_POD_NAME}:${TASK_BAK_DIR}/database-backup.tar ${LOCAL_BAK_DIR}/database-backup.tar
if [ ! -s ${LOCAL_BAK_DIR}/database-backup.tar ];then printf "${LOCAL_BAK_DIR}/database-backup.tar error\n";fi >> ${LOG_FILE}

# 清理容器内的元数据备份
printf "$(date) clean nexus pod orientDB data backup\n" >> ${LOG_FILE}
kubectl -n ${NEXUS_NS} exec ${NEXUS_POD_NAME} -- sh -c "rm -rf ${TASK_BAK_DIR}"

# 拷贝blobs数据到本地
printf "$(date) copy blobs to ${LOCAL_BAK_DIR}\n" >> ${LOG_FILE}
kubectl cp ${NEXUS_NS}/${NEXUS_POD_NAME}:/nexus-data/blobs ${LOCAL_BAK_DIR}/blobs
if [ ! -s ${LOCAL_BAK_DIR}/blobs ];then printf "${LOCAL_BAK_DIR}/blobs error\n";fi >> ${LOG_FILE}

# 拷贝节点ID数据到本地
printf "$(date) copy keystores to ${LOCAL_BAK_DIR}\n" >> ${LOG_FILE}
kubectl cp ${NEXUS_NS}/${NEXUS_POD_NAME}:/nexus-data/keystores ${LOCAL_BAK_DIR}/keystores
if [ ! -s ${LOCAL_BAK_DIR}/keystores ];then printf "${LOCAL_BAK_DIR}/keystores error\n";fi >> ${LOG_FILE}

# 归档备份数据以时期命名
printf "$(date) tar file\n" >> ${LOG_FILE}
tar zcf ${LOCAL_BAK_DIR}/nexus-backup-$(date +%Y-%m-%d-%H-%M-%S).tar ${LOCAL_BAK_DIR}/blobs ${LOCAL_BAK_DIR}/keystores ${LOCAL_BAK_DIR}/database-backup.tar && \
rm -rf ${LOCAL_BAK_DIR}/blobs ${LOCAL_BAK_DIR}/keystores ${LOCAL_BAK_DIR}/database-backup.tar

# 清理超出备份保留时间的备份数据
printf "$(date) clean history backup data\n" >> ${LOG_FILE}
find ${LOCAL_BAK_DIR} -name 'nexus-backup-*.tar' -type f -mtime +${DAY} -exec rm {} \;
