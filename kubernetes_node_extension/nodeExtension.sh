base_set () {
    local setHostname=${1:?"\$1需要设置hostname"}
    hostnamectl set-hostname ${setHostname}
}

kernel_update () {
    rpm --import https://www.elrepo.org/RPM-GPG-KEY-elrepo.org
    rpm -Uvh http://www.elrepo.org/elrepo-release-7.0-3.el7.elrepo.noarch.rpm
    yum --disablerepo=\* --enablerepo=elrepo-kernel repolist
    yum --disablerepo=\* --enablerepo=elrepo-kernel install -y kernel-ml.x86_64
    grub2-set-default 0
}

yum_install_pkg () {
    yum -y install lrzsz zip unzip vim net-tools curl bridge-utils jq\
    conntrack ipvsadm ipset sysstat libseccomp \
    salt-minion
}

ip_vs_add () {
    ipvs_modules="ip_vs ip_vs_lc ip_vs_wlc ip_vs_rr ip_vs_wrr ip_vs_lblc ip_vs_lblcr ip_vs_dh ip_vs_sh ip_vs_fo ip_vs_nq ip_vs_sed ip_vs_ftp"
    for kernel_module in ${ipvs_modules}; do
        /sbin/modinfo -F filename ${kernel_module} > /dev/null 2>&1
    if (($? == 0)); then
        /sbin/modprobe ${kernel_module}
    fi
    done
    chmod 755 /etc/sysconfig/modules/ipvs.modules && bash /etc/sysconfig/modules/ipvs.modules
    lsmod | grep ip_vs
}

docker_ce_install () {
    yum install -y yum-utils device-mapper-persistent-data lvm2
    yum-config-manager --add-repo https://mirrors.aliyun.com/docker-ce/linux/centos/docker-ce.repo
    yum clean all
    yum makecache fast
    yum install -y docker-ce

    mkdir -p /etc/docker && mkdir -p /data/server/docker/data

# << 双号输入重定向结尾字符不能有空格
cat > /etc/docker/daemon.json << EOF
{
"registry-mirrors":["https://registry.docker-cn.com",
                    "https://mbvs4o4m.mirror.aliyuncs.com"],
"insecure-registries": ["harbor.dfsjfm.com"],
"data-root":"/data/server/docker/data",
"exec-opts":["native.cgroupdriver=systemd"],
"log-driver":"json-file",
"log-opts":{ "max-size" :"300m","max-file":"1"}
}
EOF
    systemctl enable --now docker
    sleep 10 ; echo "waiting dockerd.."
}

data_copy_src_docker () {
    docker pull $setDataDockerImage
    docker run -d --name tmpc $setDataDockerImage

    docker cp tmpc:/data/node /etc/kubernetes
    docker cp tmpc:/data/kubelet /usr/local/sbin/kubelet
    docker cp tmpc:/data/kubelet.service /usr/lib/systemd/system/kubelet.service
    docker cp tmpc:/data/kubernetes.conf /etc/sysctl.d/kubernetes.conf

    docker rm -f tmpc
    docker image rm $setDataDockerImage
}

handle_process () {
    sysctl --system
    systemctl enable --now kubelet
    if (($? == 0));then
        rm -f /etc/kubernetes/pki/kubeconfig/bootstrap.conf
    else
        return 1
    fi
}

main () {

# 1.base_set：基础系统设置
# 2.kernel_update：升级内核
# 3.yum_install_pkg：安装rpm依赖
# 4.ip_vs_add：加载ip_vs模块
# 5.docker_ce_install：安装docker-ce，并且启动dockerd
# 6.data_copy_src_docker：拉取包含关键数据的文件镜像并拷贝镜像中的数据文件到节点
# 7.handle_process：加载内核参数，启动kubelet，删除bootstrap.conf文件

    execFuncs=(base_set kernel_update yum_install_pkg ip_vs_add docker_ce_install data_copy_src_docker handle_process)
    for func in ${execFuncs[@]};do
        funcName=$func
        echo -e "\033[31m---------- $funcName ----------\033[0m"
        $func
        if (($? != 0));then echo "$func exec faild" && exit 1 ;fi
    done
    echo -e "\033[31m---------- Complete ----------\033[0m"
}

set -eu

setDataDockerImage=${2:-"tinyunshe/extension_data:1.18.2"}

main