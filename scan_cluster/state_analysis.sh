#!/bin/bash

function cert_scan() {

    local NS_LIST=$*

}

function count_pod() {

    local NS=$*

    for n in ${NS};do
        if kubectl get ns ${n} &> /dev/null;then 
            printf "${n}:\n"
            printf "\tAll pods: $(kubectl -n ${n} get po|grep -cvE '^NAME')\n"
            printf "\tNormall pods: $(kubectl -n ${n} get po|grep -c 'Running')\n"
            printf "\tError pods: $(kubectl -n ${n} get po|grep -cvE '^NAME|Running')\n"
            printf "\tNot match replicas pods:\n$(kubectl -n ${n} get po -owide|awk -F '[/ ]+' 'NR>1{if($2<$3)print $0}')\n"
        else
            printf "ERROR ${n} not found\n"
            continue
        fi
    done

}
    
function f_check() {

    printf "kubectl checking...\n"
    if ! command -v kubectl &> /dev/null;then
        printf "kubectl not found\n";exit 1
    fi

}

function workflow() {

    NS_LIST=(cpaas-system alauda-system cert-manager kube-system)

    count_pod ${NS_LIST[@]}
    cert_scan

}

function main() {

    set -eu

    f_check
    workflow

}

main