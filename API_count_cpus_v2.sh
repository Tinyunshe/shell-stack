#!/bin/bash
# 版本 Version 2.0
# 调用容器平台接口获取业务集群cpu总数

ACP_IP=""
TOKEN=""

set -eu

if [ ! -e cluster.json ];then touch cluster.json;else > cluster.json;fi
if [ ! -e cluster_name.txt ];then touch cluster_name.txt;else > cluster_name.txt;fi
if [ ! -e cpu.txt ];then touch cpu.txt;else > cpu.txt;fi

CLUSTER_URL="http://${ACP_IP}/apis/platform.tkestack.io/v1/clusters"

if ! curl -sk ${CLUSTER_URL} -H "Authorization:Bearer ${TOKEN}";then printf "cluster url error";exit 1;fi
curl -sk ${CLUSTER_URL} -H "Authorization:Bearer ${TOKEN}" | jq . > cluster.json
cat cluster.json |jq '.items[].metadata.name'|tr -d '"' > cluster_name.txt

for i in $(cat cluster_name.txt);do

    if [ ! -e ${i} ];then mkdir ${i};fi

    RESOURCE_URL="http://${ACP_IP}/kubernetes/${i}/api/v1/nodes"

    if ! curl -sk ${RESOURCE_URL} -H "Authorization:Bearer ${TOKEN}";then printf "resource url error";exit 1;fi
    curl -sk ${RESOURCE_URL} -H "Authorization:Bearer ${TOKEN}" | jq . > ${i}/${i}.json
    CPUNUM=$(cat ${i}/${i}.json | jq '.items[].status.capacity.cpu' | tr -d '"' | awk '{s+=$1} END {print s}')
    printf "${i}: ${CPUNUM} \n" >> cpu.txt

done

cat cpu.txt |column -t