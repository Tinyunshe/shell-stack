#!/bin/bash
ACP_VERSION=(2.9 3.0 3.4)
ACTIONS=(start stop show)

check(){
case $1 in action) LIST=${ACTIONS[@]};; version) LIST=${ACP_VERSION[@]};;esac
for opt in ${LIST};do
  if [[ "${opt}a" != "${2}a" ]];then
    continue
  else
    return 0
  fi
done
return 1
}

start(){
for i in $(cat /root/vhost/acp${1}/${1}.txt);do
virsh start $i && sleep 2
done
}

stop(){
for x in $(seq 1 3);do
for i in $(cat /root/vhost/acp${1}/${1}.txt);do
virsh shutdown $i && sleep 3 && virsh destroy $i
done
done
}

show(){
for version in ${ACP_VERSION[@]};do
echo "acp${version}:"
awk 'NR==FNR{a[$1]=$1}NR>FNR{if($2 in a)print $2,$3}' /root/vhost/acp${version}/${version}.txt <(virsh list --all)
echo "---";echo
done
}

if ! check action $1;then echo "ERROR: No exisit action";exit 1;fi
case $1 in
start)
if ! check version $2;then echo "ERROR: No exisit acp version";exit 1;fi
start $2;;
stop)
if ! check version $2;then echo "ERROR: No exisit acp version";exit 1;fi
stop $2;;
show)  show;;
esac