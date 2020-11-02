#!/bin/bash
# 调用容器平台接口获取业务集群cpu总数
# 优化范围：后期会直接使用jq匹配

ACP_IP=""
TOKEN=""

set -eu

curl -sk http://${ACP_IP}/apis/platform.tkestack.io/v1/clusters -H "Authorization:Bearer ${TOKEN}" \ 
| jq . > cluster.json

grep -E '\"name\":' cluster.json | awk -F '\"' '{print $4}' | grep -wv token > cluster_name.txt

if [ ! -e cpu.txt ];then touch cpu.txt;else > cpu.txt;fi

for i in $(cat cluster_name.txt);do

  if [ ! -e ${i} ];then mkdir ${i};fi
  curl -sk http://${ACP_IP}/kubernetes/${i}/api/v1/nodes -H "Authorization:Bearer ${TOKEN}" \ 
  | jq . > ${i}/${i}.json
  CPUNUM=$(grep -A 1 capacity ${i}/${i}.json |grep cpu |awk -F '\"' '{s+=$4} END {print s}')
  printf "${i}: ${CPUNUM} \n">> cpu.txt

done

cat cpu.txt 