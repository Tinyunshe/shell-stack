#!/bin/bash

handler(){
  NAME=("3.4" "3.0" "2.9" "2.6")
  for v in ${NAME[*]};do
    if [[ $1 == $v ]];then
      return
    fi
  done
  printf "unknow name\n";exit 1
}

case $1 in
"start")
handler $2
for i in {01..03};do ssh demo-phy$i "for m in \$(virsh list --all|awk '/rotc${2/./-}/{print \$2}');do virsh start \$m;done";done ;;
"stop")
handler $2
for i in {01..03};do ssh demo-phy$i "for m in \$(virsh list|awk '/rotc${2/./-}/{print \$2}');do virsh shutdown \$m;done";done ;;
"show")
handler $2
for i in {01..03};do ssh demo-phy$i "virsh list --all|awk '/rotc${2/./-}/{print\$2,\$3}'";done|column -t ;;
*)
printf "unknow action\n" ;;
esac