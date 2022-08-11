#!/bin/bash

set -e

# CR name
CR_NAME="sh.helm.release.v1.alauda-base sh.helm.release.v1.chart-base-operator" 

# clean last etcd backup data
if [ -e etcd-clean-data.db ];then rm -f etcd-clean-data.db;fi 

# backup etcd data
ETCDCTL_API=3 etcdctl --endpoints=https://127.0.0.1:2379 --cacert=/etc/kubernetes/pki/etcd/ca.crt --cert=/etc/kubernetes/pki/etcd/server.crt --key=/etc/kubernetes/pki/etcd/server.key \
snapshot save etcd-clean-data.db 

for i in ${CR_NAME[@]};do
    # CR count
    WCL=$(kubectl get rels -A|grep ${i}|wc -l) 

    # delete rels action
    kubectl get rels -A|grep ${i}|sort -k3 -t "v" -n|awk -v num=${WCL} '{if(NR>=1&&NR<=num-5)print "kubectl delete rels -n",$1,$2}'|bash 

done

# delete pipeline action
for ns in $(kubectl get ns -oname |awk -F '/' '{print$2}');do 
    kubectl delete pipeline -n $ns $(kubectl get pipeline -n $ns | awk 'match($4,/([1-9][0-9][0-9]d)|([2-9][0-9]d)|(1[5-9]d)/) {print $1}')
done

# compact
REV=$(ETCDCTL_API=3 etcdctl --endpoints=$(kubectl get no -owide|awk '$3 == "master"{print$1}'|xargs -I {} printf "https://{}:2379,"|sed 's/,$//') --cacert=/etc/kubernetes/pki/etcd/ca.crt --cert=/etc/kubernetes/pki/etcd/server.crt --key=/etc/kubernetes/pki/etcd/server.key endpoint status -w json|grep -Eo '"revision":[0-9]+'|cut -d':' -f2|uniq)
ETCDCTL_API=3 etcdctl --endpoints=$(kubectl get no -owide|awk '$3 == "master"{print$1}'|xargs -I {} printf "https://{}:2379,"|sed 's/,$//') --cacert=/etc/kubernetes/pki/etcd/ca.crt --cert=/etc/kubernetes/pki/etcd/server.crt --key=/etc/kubernetes/pki/etcd/server.key \
compact ${REV} 

# defrag
ETCDCTL_API=3 etcdctl --endpoints=$(kubectl get no -owide|awk '$3 == "master"{print$1}'|xargs -I {} printf "https://{}:2379,"|sed 's/,$//') --cacert=/etc/kubernetes/pki/etcd/ca.crt --cert=/etc/kubernetes/pki/etcd/server.crt --key=/etc/kubernetes/pki/etcd/server.key \
defrag --command-timeout=60s 