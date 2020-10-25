#!/bin/bash
# 调用容器平台接口获取业务集群cpu总数
# 优化范围：后期会直接使用jq匹配

set -eu

curl -k http://192.168.1.10/apis/platform.tkestack.io/v1/clusters -H "Authorization:Bearer eyJhbGciOiJSUzI1NiIsImtpZCI6IjMyZWQ5NmZiM2U0YzkyYmExNDM4ZDQxOTcxMTA2YTdjZTlmNjE0NjIifQ.eyJpc3MiOiJodHRwczovLzE5Mi4xNjguMS4xMC9kZXgiLCJzdWIiOiJDaVF3T0dFNE5qZzBZaTFrWWpnNExUUmlOek10T1RCaE9TMHpZMlF4TmpZeFpqVTBOallTQld4dlkyRnMiLCJhdWQiOiJhbGF1ZGEtYXV0aCIsImV4cCI6MTc2MDc3MzMwNiwiaWF0IjoxNjAzMDg5NzA2LCJub25jZSI6ImFsYXVkYS1jb25zb2xlIiwiYXRfaGFzaCI6Im1ib2Vmc3VHd29HbzhuNEN1QUdXUEEiLCJlbWFpbCI6ImFkbWluQGNwYWFzLmlvIiwiZW1haWxfdmVyaWZpZWQiOnRydWUsIm5hbWUiOiLnrqHnkIblkZgiLCJleHQiOnsiaXNfYWRtaW4iOnRydWUsImNvbm5faWQiOiJsb2NhbCJ9fQ.iRFJw8JTu9eAw_QrzIh9ayh1J1WLY0Z1M4OYLKpOmqXl9oS6XN-YrhNnw3YTSq770OsZWcM85uAqdi4LTGZQ_DsmanQs3_6ZDZ4Ano6zv5VEISRPAVbg82JV6JVJ__Ee68Kg-CQnRCY5HeE6D3vO0WL5t9pofhGWp2q-zq6CFGL_CPMMQW0bKnRPQxk7f-Dl7a-roGKDfoyQJH4Lpx-SrYOunqNWM6z9mpTILYWwf8VYSkEwKGLHFo0zOWFAl9UUJe_jqavCaIwJqLA-B_IzJNnPFkqRUyR5Z1VVIwam8xxRFmLVhdy_NX4eJilnLO_y7WRlgdLJqdwfM79-C8de3g" \ 
| jq . > cluster.json

grep -E '\"name\":' cluster.json | awk -F '\"' '{print $4}' | grep -wv token > cluster_name.txt

if [ ! -e cpu.txt ];then touch cpu.txt;else > cpu.txt;fi

for i in $(cat cluster_name.txt);do

  if [ ! -e ${i} ];then mkdir ${i};fi
  curl -k http://192.168.1.10/kubernetes/${i}/api/v1/nodes -H "Authorization:Bearer eyJhbGciOiJSUzI1NiIsImtpZCI6IjMyZWQ5NmZiM2U0YzkyYmExNDM4ZDQxOTcxMTA2YTdjZTlmNjE0NjIifQ.eyJpc3MiOiJodHRwczovLzE5Mi4xNjguMS4xMC9kZXgiLCJzdWIiOiJDaVF3T0dFNE5qZzBZaTFrWWpnNExUUmlOek10T1RCaE9TMHpZMlF4TmpZeFpqVTBOallTQld4dlkyRnMiLCJhdWQiOiJhbGF1ZGEtYXV0aCIsImV4cCI6MTc2MDc3MzMwNiwiaWF0IjoxNjAzMDg5NzA2LCJub25jZSI6ImFsYXVkYS1jb25zb2xlIiwiYXRfaGFzaCI6Im1ib2Vmc3VHd29HbzhuNEN1QUdXUEEiLCJlbWFpbCI6ImFkbWluQGNwYWFzLmlvIiwiZW1haWxfdmVyaWZpZWQiOnRydWUsIm5hbWUiOiLnrqHnkIblkZgiLCJleHQiOnsiaXNfYWRtaW4iOnRydWUsImNvbm5faWQiOiJsb2NhbCJ9fQ.iRFJw8JTu9eAw_QrzIh9ayh1J1WLY0Z1M4OYLKpOmqXl9oS6XN-YrhNnw3YTSq770OsZWcM85uAqdi4LTGZQ_DsmanQs3_6ZDZ4Ano6zv5VEISRPAVbg82JV6JVJ__Ee68Kg-CQnRCY5HeE6D3vO0WL5t9pofhGWp2q-zq6CFGL_CPMMQW0bKnRPQxk7f-Dl7a-roGKDfoyQJH4Lpx-SrYOunqNWM6z9mpTILYWwf8VYSkEwKGLHFo0zOWFAl9UUJe_jqavCaIwJqLA-B_IzJNnPFkqRUyR5Z1VVIwam8xxRFmLVhdy_NX4eJilnLO_y7WRlgdLJqdwfM79-C8de3g" \ 
  | jq . > ${i}/${i}.json
  CPUNUM=$(grep -A 1 capacity ${i}/${i}.json |grep cpu |awk -F '\"' '{s+=$4} END {print s}')
  printf "${i}: ${CPUNUM} \n">> cpu.txt

done

cat cpu.txt 