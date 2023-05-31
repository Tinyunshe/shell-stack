#!/bin/bash

set -eu
# 过滤所有api的数量并且输出api group
# awk -F/ '{if($3 ~ /\./) print $4"\t"$3; else print $3}' $ETCD_FILE|sort -n | uniq -c |column -t
# 过滤所有api
# awk -F/ '{if($3 ~ /\./) print $4; else print $3}' $ETCD_FILE|sort|uniq

WORKDIR=/root/stwu/etcd-data-region
ETCD_FILE=$WORKDIR/tmpkey.txt
BLACK_CR_FILE=$WORKDIR/blackcr.txt
GITOPS_DIR=$WORKDIR/gitops/environment-manifests/edge-manifests/production/cluster-global
GITOPS_NS_CR_FILE=$WORKDIR/nsgitopscr.txt
GITOPS_CLUSTER_CR_FILE=$WORKDIR/clustergitopscr.txt
HANDLE_BLACK_ETCD_FILE=$WORKDIR/handleblacketcd.txt
CLUSTER_CR_FILE=$WORKDIR/clustercr.txt
NS_CR_FILE=$WORKDIR/nscr.txt
UNKNOW_RES_FILE=$WORKDIR/unknowres.txt
RESULT_FILE=$WORKDIR/result.txt

function clean() {
    # 清理临时文件
    echo "==> clean $GITOPS_NS_CR_FILE $GITOPS_CLUSTER_CR_FILE $CLUSTER_CR_FILE $NS_CR_FILE"
    rm -f $GITOPS_NS_CR_FILE $GITOPS_CLUSTER_CR_FILE $CLUSTER_CR_FILE $NS_CR_FILE
}

function prepare() {
    # 检查环境阶段
    echo "==> prepare"
    # awk 'NF' > $ETCDFILE
}

function get_cluster_namespaces_cr() {

    # 区分cluster与namespace资源并分别保存
    # awk -F/ '{if($3 ~ /\./) print $4; else print $3}' $ETCD_FILE|sort|uniq|grep -v "$(cat $BLACK_CR_FILE)" > $ETCD_CR_FILE
    echo "==> get_cluster_namespaces_cr"
    kubectl api-resources --namespaced=true | sed -n '1!p' | cut -d' ' -f1 >$NS_CR_FILE
    kubectl api-resources --namespaced=false | sed -n '1!p' | cut -d' ' -f1 >$CLUSTER_CR_FILE

}

function handle_black_cr() {

    # 先判断是否是ns CR，如果是再判断是否在黑名单中
    # 如果不是
    echo "==> handle_black_cr"

    local need_delete_line_file=$WORKDIR/ndl.txt

    while read -r line; do
        IFS='/' read -ra fields <<<"$line"
        field3=${fields[-3]} # kind
        field2=${fields[-2]} # ns
        if grep -qw $field3 $NS_CR_FILE; then
            # namespace CR
            if grep -qw $field3 $BLACK_CR_FILE; then
                echo $line >>$need_delete_line_file
            fi
            continue
        elif grep -qw $field2 $CLUSTER_CR_FILE; then
            # cluster CR
            if grep -qw $field2 $BLACK_CR_FILE; then
                echo $line >>$need_delete_line_file
            fi
            continue
        else
            # unknow res
            # /registry/devops.alauda.io/devops.alauda.io/codereposervices/gitlab
            # /registry/ingress/cpaas-system/apollo
            if grep -qw $field2 $BLACK_CR_FILE || grep -qw $field3 $BLACK_CR_FILE; then
                echo $line >>$need_delete_line_file
                continue
            fi
            echo $line >>$UNKNOW_RES_FILE
        fi

    done <<<"$(cat $ETCD_FILE)"

    # 将黑名单数据从全量数据中删除并另存到HANDLE_BLACK_ETCD_FILE
    comm -23 <(cat $ETCD_FILE | sort) <(cat $need_delete_line_file | sort) >$HANDLE_BLACK_ETCD_FILE

    # 清理临时黑名单数据
    rm -f $need_delete_line_file

}

function get_gitops_cr() {

    # 获取gitops所有yaml的kind字段值，并处理kind:List，如果是List则遍历获取其中的kind字段值
    echo "==> get_gitops_cr"

    for yamlfile in $(find $GITOPS_DIR -name "*.yaml" -type f); do
        for i in $(seq 0 $(yq -N '.|document_index' $yamlfile | wc -l)); do
            kind=$(yq "select(document_index == $i)" $yamlfile | yq '.kind')
            namespace=$(yq "select(document_index == $i)" $yamlfile | yq '.metadata.namespace')
            name=$(yq "select(document_index == $i)" $yamlfile | yq '.metadata.name')
            if [[ $namespace != "null" ]]; then
                # ns资源
                echo "$kind $namespace $name" >>$GITOPS_NS_CR_FILE
            elif [[ $kind == "List" ]]; then
                # List资源
                list_kind=$(yq '.items[].kind' $yamlfile)
                list_namespace=$(yq '.items[].metadata.namespace' $yamlfile)
                list_name=$(yq '.items[].metadata.name' $yamlfile)
                if [[ $list_namespace != "null" ]]; then
                    # List中是ns资源
                    echo "$list_kind $list_namespace $list_name" >>$GITOPS_NS_CR_FILE
                else
                    # List中是cluster资源
                    echo "$list_kind $list_name" >>$GITOPS_CLUSTER_CR_FILE
                fi
            else
                # cluster集群资源或者是list资源
                echo "$kind $name" >>$GITOPS_CLUSTER_CR_FILE
            fi
        done
    done
    # 将null去掉
    sed -i '/^null/d' $GITOPS_NS_CR_FILE && sed -i '/^null/d' $GITOPS_CLUSTER_CR_FILE

    # 使用kubectl api-resources命令，将yaml中的kind识别为etcd所识别的小写cr，合并到GITOPS_CR_FILE
    for kind in $(cat $GITOPS_NS_CR_FILE | cut -d' ' -f1 | sort | uniq); do
        kindlower=$(kubectl api-resources | grep -w $kind | cut -d' ' -f1 | uniq)
        sed -i "s#\<$kind\>#$kindlower#g" $GITOPS_NS_CR_FILE
    done

    for kind in $(cat $GITOPS_CLUSTER_CR_FILE | cut -d' ' -f1 | sort | uniq); do
        kindlower=$(kubectl api-resources | grep -w $kind | cut -d' ' -f1 | uniq)
        sed -i "s#\<$kind\>#$kindlower#g" $GITOPS_CLUSTER_CR_FILE
    done

}

function contrast_etcd_gitops_cr_name() {

    # 比较etcd和gitops的cr数据差异
    # 读取数据a和数据b的内容
    echo "==> contrast_etcd_gitops_cr_name"

    MISS_NS_CR=()
    MISS_CLUSTER_CR=()
    MISS_NS_RES=()
    MISS_CLUSTER_RES=()

    local etcd_data=$(cat $HANDLE_BLACK_ETCD_FILE)
    local gitops_ns_data=$(cat $GITOPS_NS_CR_FILE)
    local gitops_cluster_data=$(cat $GITOPS_CLUSTER_CR_FILE)

    # 按行处理etcd数据，逐行匹配gitops数据
    while read -r line; do
        # 使用"/"作为分隔符，将行分割成数组
        IFS='/' read -ra fields <<<"$line"
        # 获取倒数第三列、倒数第二列和倒数第一列
        field3=${fields[-3]} # kind
        field2=${fields[-2]} # ns
        field1=${fields[-1]} # name

        # 区分ns资源与cluster资源，分别处理
        if grep -qw $field3 $NS_CR_FILE; then

            # 如果是namespace CR
            # 如果etcd数据当前行的倒数第三列CR名字列不在gitops所有ns cr中的话，认为gitops不存在该CR，记录后，进入etcd下一条数据
            if ! grep -qoE "\<$field3\>" $GITOPS_NS_CR_FILE; then
                MISS_NS_CR+=("$field3")
                continue
            fi

            # 倒数第三列CR名字存在的话，逐行匹配gitops ns cr数据
            # 逐行处理数据a，查找匹配项
            matched=0
            while read -r n_line; do
                # 使用空格作为分隔符，将行分割成数组
                IFS=' ' read -ra n_fields <<<"$n_line"
                # 判断是否匹配
                # n_fields[0] kind
                # n_fields[1] ns
                # n_fields[2] name
                # echo ${n_fields[0]} --- ${n_fields[1]} --- ${n_fields[2]}
                if [[ "${n_fields[0]}" == "$field3" && "${n_fields[1]}" == "$field2" && "${n_fields[2]}" == "$field1" ]]; then
                    matched=1
                    break
                fi
            done <<<"$gitops_ns_data"

            # 如果未找到匹配项，则输出当前行内容
            if [[ "$matched" -eq 0 ]]; then
                MISS_NS_RES+=("$line")
                # echo "$line"
            fi
            # continue

        else
            # cluster CR
            if ! grep -qoE "\<$field2\>" $GITOPS_CLUSTER_CR_FILE; then
                MISS_CLUSTER_CR+=("$field2")
                continue
            fi

            matched=0
            while read -r c_line; do
                IFS=' ' read -ra c_fields <<<"$c_line"
                # c_fields[0] kind
                # c_fields[1] name
                if [[ "${c_fields[0]}" == "$field2" && "${c_fields[1]}" == "$field1" ]]; then
                    matched=1
                    break
                fi
            done <<<"$gitops_cluster_data"

            if [[ "$matched" -eq 0 ]]; then
                MISS_CLUSTER_RES+=("$line")
                # echo "$line"
            fi

        fi
    done <<<"$etcd_data"

    handle_print_result >$RESULT_FILE

}

function handle_print_result() {

    echo "==> handle_print_result"

    echo -e "gitops 不存在的 namespace级别 CR:\n\n$(echo ${MISS_NS_CR[@]} | tr ' ' '\n' | sort -u)\n\n---\n\n"
    echo -e "gitops 不存在的 集群级别 CR:\n\n$(echo ${MISS_CLUSTER_CR[@]} | tr ' ' '\n' | sort -u)\n\n---\n\n"
    echo -e "gitops 没有同步的 namespace级别 resource:\n\n$(echo ${MISS_NS_RES[@]} | tr ' ' '\n')\n\n---\n\n"
    echo -e "gitops 没有同步的 集群级别 resource:\n\n$(echo ${MISS_CLUSTER_RES[@]} | tr ' ' '\n')\n\n---\n\n"
    echo -e "未识别到的CR:\n\n$(cat $UNKNOW_RES_FILE)\n\n---\n\n"

}

function opts() {
    # 默认选项的初始值
    skip_handle_black_cr=false

    # 解析命令行选项和参数
    while [[ $# -gt 0 ]]; do
        case "$1" in
        --skip-handle_black_cr)
            skip_handle_black_cr=true
            shift
            ;;
        *)
            echo "Invalid option: $1"
            exit 1
            ;;
        esac
    done

    # 根据选项执行相应的函数
    if [ "$skip_handle_black_cr" = true ]; then
        if [ ! -e "$HANDLE_BLACK_ETCD_FILE" ]||[ ! -e "$UNKNOW_RES_FILE" ]; then
            echo "$HANDLE_BLACK_ETCD_FILE or $UNKNOW_RES_FILE not exist, can not skip handle_black_cr"
            exit 1
        fi
        clean
        get_cluster_namespaces_cr
        get_gitops_cr
        contrast_etcd_gitops_cr_name
        cat $RESULT_FILE
        clean
        exit 0
    fi
}

function main() {
    opts "$@"
    clean
    get_cluster_namespaces_cr
    handle_black_cr
    get_gitops_cr
    contrast_etcd_gitops_cr_name
    cat $RESULT_FILE
    clean
}

main "$@"
