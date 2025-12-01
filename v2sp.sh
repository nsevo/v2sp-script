#!/bin/bash

# Color definitions
red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
blue='\033[0;34m'
cyan='\033[0;36m'
white='\033[0;37m'
bold='\033[1m'
dim='\033[2m'
plain='\033[0m'

# Get terminal width
get_term_width() {
    local cols
    cols=$(tput cols 2>/dev/null) || cols=80
    echo "$cols"
}

# Print a line with padding
print_line() {
    local char="${1:-=}"
    local width=$(get_term_width)
    printf "%${width}s\n" | tr ' ' "$char"
}

# Print centered text
print_center() {
    local text="$1"
    local width=$(get_term_width)
    local padding=$(( (width - ${#text}) / 2 ))
    printf "%${padding}s%s\n" "" "$text"
}

# Print two columns
print_columns() {
    local left="$1"
    local right="$2"
    local width
    width=$(get_term_width)
    local mid=$(( width / 2 ))
    # %-*b ensures left column width with ANSI support; %b for right to keep colors
    printf "  %-*b%b\n" "$mid" "$left" "$right"
}

# UI Elements  
CHECKMARK="${green}[+]${plain}"
CROSS="${red}[-]${plain}"
ARROW="${cyan}>${plain}"
BULLET="${green}*${plain}"
INFO="${blue}[i]${plain}"
WARN="${yellow}[!]${plain}"

# Metrics cache
NET_LAST_RX=0
NET_LAST_TX=0
NET_LAST_TS=0
CPU_LAST_TOTAL=0
CPU_LAST_IDLE=0

fetch_initconfig_and_run() {
    local tmp_script
    tmp_script=$(mktemp /tmp/v2sp_init.XXXX) || {
        echo -e "${red}无法创建临时文件${plain}"
        return 1
    }
    if ! curl -fsSL https://raw.githubusercontent.com/nsevo/v2sp-script/master/initconfig.sh -o "$tmp_script"; then
        echo -e "${red}下载 initconfig.sh 失败，请检查网络连接${plain}"
        rm -f "$tmp_script"
        return 1
    fi
    # shellcheck disable=SC1090
    source "$tmp_script"
    rm -f "$tmp_script"
    if declare -f generate_config_file >/dev/null 2>&1; then
        generate_config_file
    else
        echo -e "${red}initconfig.sh 未提供 generate_config_file 函数${plain}"
        return 1
    fi
}

# check root
[[ $EUID -ne 0 ]] && echo -e "${red}错误: ${plain} 必须使用root用户运行此脚本！\n" && exit 1

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

# 检查系统是否有 IPv6 地址
check_ipv6_support() {
    if ip -6 addr | grep -q "inet6"; then
        echo "1"  # 支持 IPv6
    else
        echo "0"  # 不支持 IPv6
    fi
}

confirm() {
    if [[ $# > 1 ]]; then
        echo && read -rp "$1 [默认$2]: " temp
        if [[ x"${temp}" == x"" ]]; then
            temp=$2
        fi
    else
        read -rp "$1 [y/n]: " temp
    fi
    if [[ x"${temp}" == x"y" || x"${temp}" == x"Y" ]]; then
        return 0
    else
        return 1
    fi
}

confirm_restart() {
    confirm "是否重启v2sp" "y"
    if [[ $? == 0 ]]; then
        restart
    else
        before_show_menu
    fi
}

before_show_menu() {
    echo ""
    echo -ne " ${ARROW} Press ${bold}Enter${plain} to return to main menu..."
    read temp
}

install() {
    bash <(curl -Ls https://raw.githubusercontent.com/nsevo/v2sp-script/master/install.sh)
    if [[ $? == 0 ]]; then
        if [[ $# == 0 ]]; then
            start
        else
            start 0
        fi
    fi
}

update() {
    if [[ $# == 0 ]]; then
        echo && echo -n -e "输入指定版本(默认最新版): " && read version
    else
        version=$2
    fi
    bash <(curl -Ls https://raw.githubusercontent.com/nsevo/v2sp-script/master/install.sh) $version
    if [[ $? == 0 ]]; then
        echo -e "${green}更新完成，已自动重启 v2sp，请使用 v2sp log 查看运行日志${plain}"
        exit
    fi

    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

config() {
    echo "v2sp在修改配置后会自动尝试重启"
    vi /etc/v2sp/config.json
    sleep 2
    restart
    check_status
    case $? in
        0)
            echo -e "v2sp状态: ${green}已运行${plain}"
            ;;
        1)
            echo -e "检测到您未启动v2sp或v2sp自动重启失败，是否查看日志？[Y/n]" && echo
            read -e -rp "(默认: y):" yn
            [[ -z ${yn} ]] && yn="y"
            if [[ ${yn} == [Yy] ]]; then
               show_log
            fi
            ;;
        2)
            echo -e "v2sp状态: ${red}未安装${plain}"
    esac
}

uninstall() {
    confirm "确定要卸载 v2sp 吗?" "n"
    if [[ $? != 0 ]]; then
        return 0
    fi
    
    echo ""
    echo -e "${bold}Uninstalling v2sp...${plain}"
    print_line "-"
    
    # Stop and disable service
    echo -ne "  ${ARROW} Stopping service..."
    if [[ x"${release}" == x"alpine" ]]; then
        service v2sp stop >/dev/null 2>&1
        rc-update del v2sp >/dev/null 2>&1
        rm /etc/init.d/v2sp -f >/dev/null 2>&1
    else
        systemctl stop v2sp >/dev/null 2>&1
        systemctl disable v2sp >/dev/null 2>&1
        rm /etc/systemd/system/v2sp.service -f >/dev/null 2>&1
        systemctl daemon-reload >/dev/null 2>&1
        systemctl reset-failed >/dev/null 2>&1
    fi
    echo -e "\r  ${CHECKMARK} Service stopped      "
    
    # Remove files
    echo -ne "  ${ARROW} Removing files..."
    rm /etc/v2sp/ -rf >/dev/null 2>&1
    rm /usr/local/v2sp/ -rf >/dev/null 2>&1
    echo -e "\r  ${CHECKMARK} Files removed        "
    
    # Remove management script
    echo -ne "  ${ARROW} Removing script..."
    rm /usr/bin/v2sp -f >/dev/null 2>&1
    echo -e "\r  ${CHECKMARK} Script removed       "
    
    print_line "-"
    echo -e "  ${green}[OK] v2sp 已完全移除${plain}"
    echo ""

    if [[ $# == 0 ]]; then
        echo -e "  ${dim}Press Enter to exit...${plain}"
        read temp
        exit 0
    fi
}

start() {
    check_status
    if [[ $? == 0 ]]; then
        echo ""
        echo -e "  ${INFO} Service is already ${green}running${plain}"
        echo -e "  ${WARN} Use option ${bold}[8]${plain} or ${bold}[R]${plain} to restart"
    else
        echo ""
        echo -e "${bold}Starting v2sp...${plain}"
        print_line "-"
        
        echo -ne "  ${ARROW} Initializing service..."
        if [[ x"${release}" == x"alpine" ]]; then
            service v2sp start >/dev/null 2>&1
        else
            systemctl start v2sp >/dev/null 2>&1
        fi
        sleep 2
        
        check_status
        if [[ $? == 0 ]]; then
            echo -e "\r  ${CHECKMARK} Service initialized  "
            print_line "-"
            echo -e "  ${green}[OK] v2sp started successfully${plain}"
            echo -e "  ${dim}Use 'v2sp log' to view logs${plain}"
        else
            echo -e "\r  ${CROSS} Service failed       "
            print_line "-"
            echo -e "  ${red}[FAIL] Failed to start v2sp${plain}"
            echo -e "  ${INFO} Check logs: ${bold}v2sp log${plain}"
        fi
    fi

    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

stop() {
    echo ""
    echo -e "${bold}Stopping v2sp...${plain}"
    print_line "-"
    
    echo -ne "  ${ARROW} Sending stop signal..."
    if [[ x"${release}" == x"alpine" ]]; then
        service v2sp stop >/dev/null 2>&1
    else
        systemctl stop v2sp >/dev/null 2>&1
    fi
    sleep 2
    
    check_status
    if [[ $? == 1 ]]; then
        echo -e "\r  ${CHECKMARK} Service stopped      "
        print_line "-"
        echo -e "  ${green}[OK] v2sp stopped successfully${plain}"
    else
        echo -e "\r  ${WARN} Service stopping...   "
        print_line "-"
        echo -e "  ${yellow}[WARN] Stop operation may take longer${plain}"
        echo -e "  ${INFO} Check status: ${bold}v2sp status${plain}"
    fi

    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

restart() {
    echo ""
    echo -e "${bold}Restarting v2sp...${plain}"
    print_line "-"
    
    echo -ne "  ${ARROW} Stopping service..."
    if [[ x"${release}" == x"alpine" ]]; then
        service v2sp stop >/dev/null 2>&1
    else
        systemctl stop v2sp >/dev/null 2>&1
    fi
    sleep 1
    echo -e "\r  ${CHECKMARK} Service stopped      "
    
    echo -ne "  ${ARROW} Starting service..."
    if [[ x"${release}" == x"alpine" ]]; then
        service v2sp start >/dev/null 2>&1
    else
        systemctl start v2sp >/dev/null 2>&1
    fi
    sleep 2
    
    check_status
    if [[ $? == 0 ]]; then
        echo -e "\r  ${CHECKMARK} Service started      "
        print_line "-"
        echo -e "  ${green}[OK] v2sp restarted successfully${plain}"
    else
        echo -e "\r  ${CROSS} Service failed       "
        print_line "-"
        echo -e "  ${red}[FAIL] Failed to restart v2sp${plain}"
        echo -e "  ${INFO} Check logs: ${bold}v2sp log${plain}"
    fi
    
    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

status() {
    if [[ x"${release}" == x"alpine" ]]; then
        service v2sp status
    else
        systemctl status v2sp --no-pager -l
    fi
    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

enable() {
    echo ""
    echo -e "${bold}Enabling auto-start...${plain}"
    print_line "-"
    
    if [[ x"${release}" == x"alpine" ]]; then
        rc-update add v2sp >/dev/null 2>&1
    else
        systemctl enable v2sp >/dev/null 2>&1
    fi
    
    if [[ $? == 0 ]]; then
        echo -e "  ${CHECKMARK} Auto-start enabled"
        print_line "-"
        echo -e "  ${green}[OK] v2sp will start on system boot${plain}"
    else
        echo -e "  ${CROSS} Failed to enable"
        print_line "-"
        echo -e "  ${red}[FAIL] Operation failed${plain}"
        echo -e "  ${INFO} Check system permissions"
    fi

    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

disable() {
    echo ""
    echo -e "${bold}Disabling auto-start...${plain}"
    print_line "-"
    
    if [[ x"${release}" == x"alpine" ]]; then
        rc-update del v2sp >/dev/null 2>&1
    else
        systemctl disable v2sp >/dev/null 2>&1
    fi
    
    if [[ $? == 0 ]]; then
        echo -e "  ${CHECKMARK} Auto-start disabled"
        print_line "-"
        echo -e "  ${green}[OK] v2sp will not start on boot${plain}"
    else
        echo -e "  ${CROSS} Failed to disable"
        print_line "-"
        echo -e "  ${red}[FAIL] Operation failed${plain}"
        echo -e "  ${INFO} Check system permissions"
    fi

    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

show_log() {
    if [[ x"${release}" == x"alpine" ]]; then
        echo -e "${red}alpine系统暂不支持日志查看${plain}\n" && exit 1
    else
        journalctl -u v2sp.service -e --no-pager -f
    fi
    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

install_bbr() {
    bash <(curl -L -s https://github.com/ylx2016/Linux-NetSpeed/raw/master/tcpx.sh)
}

update_shell() {
    wget -O /usr/bin/v2sp -N --no-check-certificate https://raw.githubusercontent.com/nsevo/v2sp-script/master/v2sp.sh
    if [[ $? != 0 ]]; then
        echo ""
        echo -e "${red}下载脚本失败，请检查本机能否连接 Github${plain}"
        before_show_menu
    else
        chmod +x /usr/bin/v2sp
        echo -e "${green}升级脚本成功，请重新运行脚本${plain}" && exit 0
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

check_enabled() {
    if [[ x"${release}" == x"alpine" ]]; then
        temp=$(rc-update show | grep v2sp)
        if [[ x"${temp}" == x"" ]]; then
            return 1
        else
            return 0
        fi
    else
        temp=$(systemctl is-enabled v2sp)
        if [[ x"${temp}" == x"enabled" ]]; then
            return 0
        else
            return 1;
        fi
    fi
}

check_uninstall() {
    check_status
    if [[ $? != 2 ]]; then
        echo ""
        echo -e "${red}v2sp已安装，请不要重复安装${plain}"
        if [[ $# == 0 ]]; then
            before_show_menu
        fi
        return 1
    else
        return 0
    fi
}

check_install() {
    check_status
    if [[ $? == 2 ]]; then
        echo ""
        echo -e "${red}请先安装v2sp${plain}"
        if [[ $# == 0 ]]; then
            before_show_menu
        fi
        return 1
    else
        return 0
    fi
}

# Get service uptime
get_uptime() {
    if [[ -f /usr/local/v2sp/v2sp ]]; then
        if [[ x"${release}" == x"alpine" ]]; then
            echo "N/A"
        else
            local pid=$(pgrep -f "/usr/local/v2sp/v2sp" 2>/dev/null)
            if [[ -n "$pid" ]]; then
                ps -p $pid -o etime= 2>/dev/null | tr -d ' ' || echo "N/A"
            else
                echo "N/A"
            fi
        fi
    else
        echo "N/A"
    fi
}

# Get system resource usage
get_resource_usage() {
    if command -v free &> /dev/null; then
        local mem_used=$(free -m 2>/dev/null | awk 'NR==2{printf "%.0f", $3}')
        local mem_total=$(free -m 2>/dev/null | awk 'NR==2{printf "%.0f", $2}')
        echo "${mem_used}/${mem_total}MB"
    else
        echo "N/A"
    fi
}

# Get CPU usage snapshot
get_cpu_usage() {
    if [[ ! -f /proc/stat ]]; then
        echo "N/A"
        return
    fi

    local cpu user nice system idle iowait irq softirq steal guest guest_nice
    read -r cpu user nice system idle iowait irq softirq steal guest guest_nice < /proc/stat
    local idle_total=$((idle + iowait))
    local non_idle=$((user + nice + system + irq + softirq + steal))
    local total=$((idle_total + non_idle))

    if [[ $CPU_LAST_TOTAL -eq 0 ]]; then
        CPU_LAST_TOTAL=$total
        CPU_LAST_IDLE=$idle_total
        echo "--%"
        return
    fi

    local totald=$((total - CPU_LAST_TOTAL))
    local idled=$((idle_total - CPU_LAST_IDLE))
    local usage=0
    if [[ $totald -gt 0 ]]; then
        usage=$(( (100 * (totald - idled)) / totald ))
    fi

    CPU_LAST_TOTAL=$total
    CPU_LAST_IDLE=$idle_total
    printf "%02d%%" "$usage"
}

# Get main network interface
get_main_interface() {
    # Try to find the main interface with default route
    local iface=$(ip route 2>/dev/null | grep '^default' | awk '{print $5}' | head -1)
    if [[ -z "$iface" ]]; then
        # Fallback: find first non-loopback interface with traffic
        iface=$(ip -o link show 2>/dev/null | awk -F': ' '{print $2}' | grep -v '^lo$' | head -1)
    fi
    echo "$iface"
}

# Get network speed using cached samples
get_network_speed() {
    local iface=$(get_main_interface)
    if [[ -z "$iface" ]] || [[ ! -f /proc/net/dev ]]; then
        echo "Down 0bps / Up 0bps"
        return
    fi
    
    local stats=$(grep "$iface" /proc/net/dev 2>/dev/null)
    local rx=$(echo "$stats" | awk '{print $2}')
    local tx=$(echo "$stats" | awk '{print $10}')
    if [[ -z "$rx" ]] || [[ -z "$tx" ]]; then
        echo "Down 0bps / Up 0bps"
        return
    fi

    local now=$(date +%s)
    if [[ $NET_LAST_TS -eq 0 ]]; then
        NET_LAST_TS=$now
        NET_LAST_RX=$rx
        NET_LAST_TX=$tx
        echo "Down 0bps / Up 0bps"
        return
    fi

    local delta_t=$((now - NET_LAST_TS))
    [[ $delta_t -le 0 ]] && delta_t=1
    local rx_delta=$((rx - NET_LAST_RX))
    local tx_delta=$((tx - NET_LAST_TX))
    (( rx_delta < 0 )) && rx_delta=0
    (( tx_delta < 0 )) && tx_delta=0
    local rx_bits=$(( rx_delta * 8 / delta_t ))
    local tx_bits=$(( tx_delta * 8 / delta_t ))

    NET_LAST_TS=$now
    NET_LAST_RX=$rx
    NET_LAST_TX=$tx

    local rx_display=$(format_bits $rx_bits)
    local tx_display=$(format_bits $tx_bits)
    
    echo "Down ${rx_display} / Up ${tx_display}"
}

# Format bits to human readable (bps/Kbps/Mbps)
format_bits() {
    local bits=$1
    if [[ $bits -lt 1000 ]]; then
        echo "${bits}bps"
    elif [[ $bits -lt 1000000 ]]; then
        printf "%.1fKbps" "$(echo "scale=1; $bits / 1000" | bc 2>/dev/null || echo "$((bits / 1000))")"
    else
        printf "%.2fMbps" "$(echo "scale=2; $bits / 1000000" | bc 2>/dev/null || echo "$((bits / 1000000))")"
    fi
}

# Show detailed status (single line, minimal)
show_status() {
    local status="" auto="" uptime="" memory="" network="" cpu=""
    
    check_status
    case $? in
        0) status="${green}RUN${plain}" ;;
        1) status="${yellow}STOP${plain}" ;;
        2) status="${red}N/A${plain}" && echo -e "  Status: ${status}" && echo "" && return ;;
    esac
    
    check_enabled
    [[ $? == 0 ]] && auto="${green}ON${plain}" || auto="${red}OFF${plain}"
    
    uptime=$(get_uptime)
    memory=$(get_resource_usage)
    cpu=$(get_cpu_usage)
    
    # Single line status
    echo -e "  Status: ${status}  |  Auto: ${auto}  |  Up: ${uptime}  |  CPU: ${cpu}  |  Mem: ${memory}"
    
    # Network snapshot
    network=$(get_network_speed)
    echo -e "  ${cyan}${network}${plain}"
    echo ""
}

show_tools_menu() {
    while true; do
        clear
        echo ""
        print_line "="
        print_center "${bold}${cyan}v2sp System Tools${plain}"
        print_line "="
        echo ""
        print_columns "  ${green}[15]${plain} Install BBR" "  ${green}[18]${plain} Open all ports"
        echo ""
        print_line "-"
        echo -e "  ${red}[Q]${plain} Back"
        print_line "="
        echo ""
        echo -ne " ${ARROW} "
        read -r tool_choice
        tool_choice=$(echo "$tool_choice" | tr '[:upper:]' '[:lower:]')
        case "${tool_choice}" in
            15)
                install_bbr
                before_show_menu
                return
                ;;
            18)
                open_ports
                before_show_menu
                return
                ;;
            q)
                return
                ;;
            *)
                echo -e " ${CROSS} Invalid selection"
                sleep 1
                ;;
        esac
    done
}

# Real-time monitor (Press M)
monitor_live() {
    trap 'return' INT  # Catch Ctrl+C to return to menu
    
    while true; do
        tput clear
        tput cup 0 0
        
        echo -e "${bold}${cyan}v2sp Monitor${plain} ${dim}| Press Ctrl+C to exit${plain}"
        print_line "="
        
        # Service status
        check_status
        case $? in
            0) echo -e "Service:    ${green}● RUNNING${plain}" ;;
            1) echo -e "Service:    ${yellow}○ STOPPED${plain}" && break ;;
            2) echo -e "Service:    ${red}✕ NOT INSTALLED${plain}" && break ;;
        esac
        
        check_enabled
        [[ $? == 0 ]] && echo -e "Auto-start: ${green}ENABLED${plain}" || echo -e "Auto-start: ${red}DISABLED${plain}"
        
        # Resources
        echo ""
        echo -e "${bold}Resources${plain}"
        echo -e "Uptime:  $(get_uptime)"
        echo -e "Memory:  $(get_resource_usage)"
        
        # Real-time network
        echo ""
        echo -e "${bold}Network ($(get_main_interface))${plain}"
        
        local rx1=$(cat /proc/net/dev 2>/dev/null | grep "$(get_main_interface)" | awk '{print $2}')
        local tx1=$(cat /proc/net/dev 2>/dev/null | grep "$(get_main_interface)" | awk '{print $10}')
        sleep 1
        local rx2=$(cat /proc/net/dev 2>/dev/null | grep "$(get_main_interface)" | awk '{print $2}')
        local tx2=$(cat /proc/net/dev 2>/dev/null | grep "$(get_main_interface)" | awk '{print $10}')
        
        if [[ -n "$rx1" ]] && [[ -n "$tx1" ]]; then
            local rx_speed=$(format_bits $((($rx2 - $rx1) * 8)))
            local tx_speed=$(format_bits $((($tx2 - $tx1) * 8)))
            echo -e "Down:    ${cyan}${rx_speed}/s${plain}"
            echo -e "Up:      ${cyan}${tx_speed}/s${plain}"
        fi
        
        echo ""
        print_line "="
        echo -e "${dim}Refreshing every 2s...${plain}"
        
        sleep 1
    done
}

show_enable_status() {
    check_enabled
    if [[ $? == 0 ]]; then
        echo -e "  ${CHECKMARK} Auto-start: ${green}Enabled${plain}"
    else
        echo -e "  ${CROSS} Auto-start: ${red}Disabled${plain}"
    fi
}

generate_x25519_key() {
    echo -n "正在生成 x25519 密钥："
    /usr/local/v2sp/v2sp x25519
    echo ""
    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

show_v2sp_version() {
    echo -n "v2sp 版本："
    /usr/local/v2sp/v2sp version
    echo ""
    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

generate_config_file() {
    fetch_initconfig_and_run
    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

# 放开防火墙端口
open_ports() {
    systemctl stop firewalld.service 2>/dev/null
    systemctl disable firewalld.service 2>/dev/null
    setenforce 0 2>/dev/null
    ufw disable 2>/dev/null
    iptables -P INPUT ACCEPT 2>/dev/null
    iptables -P FORWARD ACCEPT 2>/dev/null
    iptables -P OUTPUT ACCEPT 2>/dev/null
    iptables -t nat -F 2>/dev/null
    iptables -t mangle -F 2>/dev/null
    iptables -F 2>/dev/null
    iptables -X 2>/dev/null
    netfilter-persistent save 2>/dev/null
    echo -e "${green}放开防火墙端口成功！${plain}"
}

show_usage() {
    echo "v2sp 管理脚本使用方法: "
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
    echo "v2sp update x.x.x - 安装 v2sp 指定版本"
    echo "v2sp install      - 安装 v2sp"
    echo "v2sp uninstall    - 卸载 v2sp"
    echo "v2sp version      - 查看 v2sp 版本"
    echo "------------------------------------------"
}

render_main_menu() {
    clear
    echo ""
    print_center "${bold}${cyan}v2sp${plain}"
    echo ""
    show_status
    echo -e "${bold}Quick Actions${plain}"
    print_line "-"
    print_columns "  ${bold}[R]${plain} Restart    ${bold}[S]${plain} Stop    ${bold}[L]${plain} Logs" "  ${bold}[M]${plain} Monitor    ${bold}[U]${plain} Update    ${bold}[E]${plain} Config"
    print_columns "  ${bold}[T]${plain} Tools" "  ${bold}[H]${plain} Help"
    echo ""
    echo -e "${bold}Service Control${plain}"
    print_line "-"
    print_columns "  ${green}[6]${plain} Start service" "  ${green}[7]${plain} Stop service"
    print_columns "  ${green}[8]${plain} Restart service" "  ${green}[9]${plain} Show status"
    print_columns "  ${green}[10]${plain} View logs" "  ${green}[11]${plain} Enable auto-start"
    print_columns "  ${green}[12]${plain} Disable auto-start" ""
    echo ""
    echo -e "${bold}Configuration${plain}"
    print_line "-"
    print_columns "  ${green}[0]${plain} Edit config" "  ${green}[17]${plain} Generate config"
    print_columns "  ${green}[16]${plain} Generate X25519 key" ""
    echo ""
    echo -e "${bold}Maintenance${plain}"
    print_line "-"
    check_status
    local install_state=$?
    if [[ ${install_state} -eq 2 ]]; then
        print_columns "  ${green}[1]${plain} Install v2sp" ""
    fi
    print_columns "  ${green}[2]${plain} Update v2sp" "  ${green}[4]${plain} Show version"
    print_columns "  ${green}[5]${plain} Update script" "  ${green}[3]${plain} Uninstall v2sp"
    echo ""
    print_line "-"
    echo -e "  ${bold}[T]${plain} System tools       ${red}[Q]${plain} Exit"
    print_line "="
    echo -ne " ${ARROW} "
}

handle_menu_choice() {
    local num="$1"
    case "${num}" in
        "" ) return 0 ;;
        0|e) config ;;
        1) check_uninstall && install ;;
        2|u) check_install && update ;;
        3) check_install && uninstall ;;
        4) check_install && show_v2sp_version ;;
        5) update_shell ;;
        6) check_install && start ;;
        7|s) check_install && stop ;;
        8|r) check_install && restart ;;
        9) check_install && status ;;
        10|l) check_install && show_log ;;
        11) check_install && enable ;;
        12) check_install && disable ;;
        15) install_bbr ;;
        16) check_install && generate_x25519_key ;;
        17) generate_config_file ;;
        18) open_ports ;;
        m) check_install && monitor_live ;;
        t) show_tools_menu ;;
        h) show_usage && before_show_menu ;;
        q) exit 0 ;;
        *) echo -e " ${CROSS} Invalid" && sleep 1 ;;
    esac
    return 0
}

show_menu() {
    local num=""
    while true; do
        render_main_menu
        if read -t 1 -r num; then
            num=$(echo "$num" | tr '[:upper:]' '[:lower:]')
            handle_menu_choice "$num"
        fi
    done
}


if [[ $# > 0 ]]; then
    case $1 in
        "start") check_install 0 && start 0 ;;
        "stop") check_install 0 && stop 0 ;;
        "restart") check_install 0 && restart 0 ;;
        "status") check_install 0 && status 0 ;;
        "enable") check_install 0 && enable 0 ;;
        "disable") check_install 0 && disable 0 ;;
        "log") check_install 0 && show_log 0 ;;
        "update") check_install 0 && update 0 $2 ;;
        "config") config $* ;;
        "generate") generate_config_file ;;
        "install") check_uninstall 0 && install 0 ;;
        "uninstall") check_install 0 && uninstall 0 ;;
        "x25519") check_install 0 && generate_x25519_key 0 ;;
        "version") check_install 0 && show_v2sp_version 0 ;;
        "update_shell") update_shell ;;
        *) show_usage
    esac
else
    show_menu
fi
