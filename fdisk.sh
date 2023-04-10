#!/bin/bash

# $1是磁盘名
# $2是挂载路径
# $3是分区名
# 自动fdisk分区，创建文件系统，挂载路径，配置fstab

DEV=$1
DIR=$2
PAT=${1}1

fdisk $DEV << EOF
n
p
1


w
EOF

mkfs.xfs $PAT

if [ ! -e $DIR ];then mkdir $DIR ;fi

mount $PAT $DIR

echo "$(blkid $PAT -o export|grep -w UUID) $DIR xfs defaults,noatime 0 0" >> /etc/fstab

df -hT $DIR
tail -1 /etc/fstab
