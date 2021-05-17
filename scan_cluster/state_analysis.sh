#!/bin/bash

function cert_scan() {

    local NS_LIST=$*

    for item in $(find /etc/kubernetes/pki -maxdepth 2 -name "*.crt");do openssl x509 -in $item -text -noout| grep Not;echo ====================$item=================;done

}

function ns_count_pod() {

    local NS=$*

    for n in ${NS};do
        if kubectl get ns ${n} &> /dev/null;then 
            printf "${n}:\n"
            printf "\tAll pods: $(kubectl -n ${n} get po|grep -cvE '^NAME')\n"
            printf "\tNormal pods: $(kubectl -n ${n} get po|grep -c 'Running')\n"
            printf "\tError pods: $(kubectl -n ${n} get po|grep -cvE '^NAME|Running')\n"
            printf "\tNot match replicas pods:\n$(kubectl -n ${n} get po -owide|awk -F '[/ ]+' 'NR>1{if($2<$3)print $0}')\n"
        else
            printf "ERROR ${n} not found\n"
            continue
        fi
    done

}
    
function check_kubectl() {

    printf "kubectl checking...\n"
    if ! command -v kubectl &> /dev/null;then
        printf "kubectl not found\n";exit 1
    fi

}

function workflow() {

    NS_LIST=(cpaas-system alauda-system cert-manager kube-system)

    ns_count_pod ${NS_LIST[@]}
    cert_scan

}

function opts() {
    local opts
}

function main() {

    set -eu

    check_kubectl
    workflow

}
function tmp() {
    
    kubectl describe no | awk -F '[ m]+' '/cpu[[:space:]]+[0-9]+m/ {s+=$3}END{print "total cpu request: ",s/1000}'
    kubectl describe no | awk -F '[ m]+' '/cpu[[:space:]]+[0-9]+m/ {s+=$5}END{print "total cpu limits: ",s/1000}'
    for i in $(find /etc/kubernetes -maxdepth 1 ! -name "kubelet.conf" -name "*.conf";find /etc/kubernetes/pki/ -maxdepth 2 -name "*.crt");do if [[ ${i##*.} = "conf" ]];then echo $i;openssl x509 -in <(awk '/client-certificate-data:/{print $2}' $i|base64 -d) -noout -dates;echo "---";else echo $i;openssl x509 -in <(cat $i) -noout -dates;echo "---";fi;done  | more

}

main