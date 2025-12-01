#!/bin/bash

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
plain='\033[0m'

cur_dir=$(pwd)

# check root
[[ $EUID -ne 0 ]] && echo -e "${red}错误：${plain} 必须使用root用户运行此脚本！\n" && exit 1

# check os
if [[ -f /etc/redhat-release ]]; then
    release="centos"
elif cat /etc/issue | grep -Eqi "alpine"; then
    release="alpine"
elif cat /etc/issue | grep -Eqi "debian"; then
    release="debian"
elif cat /etc/issue | grep -Eqi "ubuntu"; then
    release="ubuntu"
elif cat /etc/issue | grep -Eqi "centos|red hat|redhat|rocky|alma|oracle linux"; then
    release="centos"
elif cat /proc/version | grep -Eqi "debian"; then
    release="debian"
elif cat /proc/version | grep -Eqi "ubuntu"; then
    release="ubuntu"
elif cat /proc/version | grep -Eqi "centos|red hat|redhat|rocky|alma|oracle linux"; then
    release="centos"
elif cat /proc/version | grep -Eqi "arch"; then
    release="arch"
else
    echo -e "${red}未检测到系统版本，请联系脚本作者！${plain}\n" && exit 1
fi

arch=$(uname -m)

if [[ $arch == "x86_64" || $arch == "x64" || $arch == "amd64" ]]; then
    arch="64"
elif [[ $arch == "aarch64" || $arch == "arm64" ]]; then
    arch="arm64-v8a"
elif [[ $arch == "s390x" ]]; then
    arch="s390x"
else
    arch="64"
    echo -e "${red}检测架构失败，使用默认架构: ${arch}${plain}"
fi

echo "架构: ${arch}"

if [ "$(getconf WORD_BIT)" != '32' ] && [ "$(getconf LONG_BIT)" != '64' ] ; then
    echo "本软件不支持 32 位系统(x86)，请使用 64 位系统(x86_64)，如果检测有误，请联系作者"
    exit 2
fi

# os version
if [[ -f /etc/os-release ]]; then
    os_version=$(awk -F'[= ."]' '/VERSION_ID/{print $3}' /etc/os-release)
fi
if [[ -z "$os_version" && -f /etc/lsb-release ]]; then
    os_version=$(awk -F'[= ."]+' '/DISTRIB_RELEASE/{print $2}' /etc/lsb-release)
fi

if [[ x"${release}" == x"centos" ]]; then
    if [[ ${os_version} -le 6 ]]; then
        echo -e "${red}请使用 CentOS 7 或更高版本的系统！${plain}\n" && exit 1
    fi
    if [[ ${os_version} -eq 7 ]]; then
        echo -e "${red}注意： CentOS 7 无法使用hysteria1/2协议！${plain}\n"
    fi
elif [[ x"${release}" == x"ubuntu" ]]; then
    if [[ ${os_version} -lt 16 ]]; then
        echo -e "${red}请使用 Ubuntu 16 或更高版本的系统！${plain}\n" && exit 1
    fi
elif [[ x"${release}" == x"debian" ]]; then
    if [[ ${os_version} -lt 8 ]]; then
        echo -e "${red}请使用 Debian 8 或更高版本的系统！${plain}\n" && exit 1
    fi
fi

install_base() {
    if [[ x"${release}" == x"centos" ]]; then
        yum install epel-release wget curl unzip tar crontabs socat ca-certificates -y >/dev/null 2>&1
        update-ca-trust force-enable >/dev/null 2>&1
    elif [[ x"${release}" == x"alpine" ]]; then
        apk add wget curl unzip tar socat ca-certificates >/dev/null 2>&1
        update-ca-certificates >/dev/null 2>&1
    elif [[ x"${release}" == x"debian" ]]; then
        apt-get update -y >/dev/null 2>&1
        apt install wget curl unzip tar cron socat ca-certificates -y >/dev/null 2>&1
        update-ca-certificates >/dev/null 2>&1
    elif [[ x"${release}" == x"ubuntu" ]]; then
        apt-get update -y >/dev/null 2>&1
        apt install wget curl unzip tar cron socat -y >/dev/null 2>&1
        apt-get install ca-certificates wget -y >/dev/null 2>&1
        update-ca-certificates >/dev/null 2>&1
    elif [[ x"${release}" == x"arch" ]]; then
        pacman -Sy --noconfirm >/dev/null 2>&1
        pacman -S --noconfirm --needed wget curl unzip tar cron socat >/dev/null 2>&1
        pacman -S --noconfirm --needed ca-certificates wget >/dev/null 2>&1
    fi
}

# 0: running, 1: not running, 2: not installed
check_status() {
    if [[ ! -f /usr/local/v2sp/v2sp ]]; then
        return 2
    fi
    if [[ x"${release}" == x"alpine" ]]; then
        temp=$(service v2sp status | awk '{print $3}')
        if [[ x"${temp}" == x"started" ]]; then
            return 0
        else
            return 1
        fi
    else
        temp=$(systemctl status v2sp | grep Active | awk '{print $3}' | cut -d "(" -f2 | cut -d ")" -f1)
        if [[ x"${temp}" == x"running" ]]; then
            return 0
        else
            return 1
        fi
    fi
}

install_v2sp() {
    if [[ -e /usr/local/v2sp/ ]]; then
        rm -rf /usr/local/v2sp/
    fi

    mkdir /usr/local/v2sp/ -p
    cd /usr/local/v2sp/

    if  [ $# == 0 ] ;then
        last_version=$(curl -Ls "https://api.github.com/repos/nsevo/v2sp/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
        if [[ ! -n "$last_version" ]]; then
            echo -e "${red}检测 v2sp 版本失败，可能是超出 Github API 限制，请稍后再试，或手动指定 v2sp 版本安装${plain}"
            exit 1
        fi
        echo -e "检测到 v2sp 最新版本：${last_version}，开始安装"
        wget --no-check-certificate -N --progress=bar -O /usr/local/v2sp/v2sp-linux.zip https://github.com/nsevo/v2sp/releases/download/${last_version}/v2sp-linux-${arch}.zip
        if [[ $? -ne 0 ]]; then
            echo -e "${red}下载 v2sp 失败，请确保你的服务器能够下载 Github 的文件${plain}"
            exit 1
        fi
    else
        last_version=$1
        url="https://github.com/nsevo/v2sp/releases/download/${last_version}/v2sp-linux-${arch}.zip"
        echo -e "开始安装 v2sp $1"
        wget --no-check-certificate -N --progress=bar -O /usr/local/v2sp/v2sp-linux.zip ${url}
        if [[ $? -ne 0 ]]; then
            echo -e "${red}下载 v2sp $1 失败，请确保此版本存在${plain}"
            exit 1
        fi
    fi

    unzip v2sp-linux.zip
    rm v2sp-linux.zip -f
    chmod +x v2sp
    mkdir /etc/v2sp/ -p
    cp geoip.dat /etc/v2sp/
    cp geosite.dat /etc/v2sp/
    if [[ x"${release}" == x"alpine" ]]; then
        rm /etc/init.d/v2sp -f
        cat <<EOF > /etc/init.d/v2sp
#!/sbin/openrc-run

name="v2sp"
description="v2sp"

command="/usr/local/v2sp/v2sp"
command_args="server"
command_user="root"

pidfile="/run/v2sp.pid"
command_background="yes"

depend() {
        need net
}
EOF
        chmod +x /etc/init.d/v2sp
        rc-update add v2sp default
        echo -e "${green}v2sp ${last_version}${plain} 安装完成，已设置开机自启"
    else
        rm /etc/systemd/system/v2sp.service -f
        cat <<EOF > /etc/systemd/system/v2sp.service
[Unit]
Description=v2sp Service
After=network.target nss-lookup.target
Wants=network.target

[Service]
User=root
Group=root
Type=simple
LimitAS=infinity
LimitRSS=infinity
LimitCORE=infinity
LimitNOFILE=999999
WorkingDirectory=/usr/local/v2sp/
ExecStart=/usr/local/v2sp/v2sp server
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
        systemctl daemon-reload
        systemctl stop v2sp
        systemctl enable v2sp
        echo -e "${green}v2sp ${last_version}${plain} 安装完成，已设置开机自启"
    fi

    if [[ ! -f /etc/v2sp/config.json ]]; then
        cp config.json /etc/v2sp/
        echo -e ""
        echo -e "全新安装，请根据自研面板文档配置必要内容"
        first_install=true
    else
        if [[ x"${release}" == x"alpine" ]]; then
            service v2sp start
        else
            systemctl start v2sp
        fi
        sleep 2
        check_status
        echo -e ""
        if [[ $? == 0 ]]; then
            echo -e "${green}v2sp 重启成功${plain}"
        else
            echo -e "${red}v2sp 可能启动失败，请稍后使用 v2sp log 查看日志信息${plain}"
        fi
        first_install=false
    fi

    if [[ ! -f /etc/v2sp/dns.json ]]; then
        cp dns.json /etc/v2sp/
    fi
    if [[ ! -f /etc/v2sp/route.json ]]; then
        cp route.json /etc/v2sp/
    fi
    if [[ ! -f /etc/v2sp/custom_outbound.json ]]; then
        cp custom_outbound.json /etc/v2sp/
    fi
    if [[ ! -f /etc/v2sp/custom_inbound.json ]]; then
        cp custom_inbound.json /etc/v2sp/
    fi
    curl -o /usr/bin/v2sp -Ls https://raw.githubusercontent.com/nsevo/v2sp-script/master/v2sp.sh
    chmod +x /usr/bin/v2sp
    if [ ! -L /usr/bin/v2spctl ]; then
        ln -s /usr/bin/v2sp /usr/bin/v2spctl
        chmod +x /usr/bin/v2spctl
    fi
    cd $cur_dir
    rm -f install.sh
    echo -e ""
    echo "v2sp 管理脚本使用方法 (兼容使用 v2sp 执行，大小写不敏感): "
    echo "------------------------------------------"
    echo "v2sp              - 显示管理菜单 (功能更多)"
    echo "v2sp start        - 启动 v2sp"
    echo "v2sp stop         - 停止 v2sp"
    echo "v2sp restart      - 重启 v2sp"
    echo "v2sp status       - 查看 v2sp 状态"
    echo "v2sp enable       - 设置 v2sp 开机自启"
    echo "v2sp disable      - 取消 v2sp 开机自启"
    echo "v2sp log          - 查看 v2sp 日志"
    echo "v2sp x25519       - 生成 x25519 密钥"
    echo "v2sp generate     - 生成 v2sp 配置文件"
    echo "v2sp update       - 更新 v2sp"
    echo "v2sp update x.x.x - 更新 v2sp 指定版本"
    echo "v2sp install      - 安装 v2sp"
    echo "v2sp uninstall    - 卸载 v2sp"
    echo "v2sp version      - 查看 v2sp 版本"
    echo "------------------------------------------"
    # 首次安装询问是否生成配置文件
    if [[ $first_install == true ]]; then
        read -rp "检测到你为第一次安装 v2sp, 是否自动直接生成配置文件？(y/n): " if_generate
        if [[ $if_generate == [Yy] ]]; then
            curl -o ./initconfig.sh -Ls https://raw.githubusercontent.com/nsevo/v2sp-script/master/initconfig.sh
            source initconfig.sh
            rm initconfig.sh -f
            generate_config_file
        fi
    fi
}

echo -e "${green}开始安装${plain}"
install_base
install_v2sp $1
