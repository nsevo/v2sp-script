#!/bin/bash

# Color definitions
red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
blue='\033[0;34m'
cyan='\033[0;36m'
bold='\033[1m'
dim='\033[2m'
plain='\033[0m'

# Get terminal width
get_term_width() {
    local cols
    cols=$(tput cols 2>/dev/null) || cols=80
    echo "$cols"
}

# Print a line
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
    printf "  %-*b%b\n" "$mid" "$left" "$right"
}

# UI Elements
OK="${green}[+]${plain}"
ERR="${red}[-]${plain}"
ARROW="${cyan}>${plain}"

fetch_initconfig_and_run() {
    local tmp_script
    tmp_script=$(mktemp /tmp/v2sp_init.XXXX) || {
        echo -e "${red}Failed to create temp file${plain}"
        return 1
    }
    if ! curl -fsSL https://raw.githubusercontent.com/nsevo/v2sp-script/master/initconfig.sh -o "$tmp_script"; then
        echo -e "${red}Failed to download initconfig.sh${plain}"
        rm -f "$tmp_script"
        return 1
    fi
    source "$tmp_script"
    rm -f "$tmp_script"
    if declare -f generate_config_file >/dev/null 2>&1; then
        generate_config_file
    else
        echo -e "${red}initconfig.sh missing generate_config_file${plain}"
        return 1
    fi
}

# check root
[[ $EUID -ne 0 ]] && echo -e "${red}Error: Root required${plain}\n" && exit 1

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
    echo -e "${red}Unsupported OS${plain}\n" && exit 1
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
        echo -e "${red}CentOS 7+ required${plain}\n" && exit 1
    fi
elif [[ x"${release}" == x"ubuntu" ]]; then
    if [[ ${os_version} -lt 16 ]]; then
        echo -e "${red}Ubuntu 16+ required${plain}\n" && exit 1
    fi
elif [[ x"${release}" == x"debian" ]]; then
    if [[ ${os_version} -lt 8 ]]; then
        echo -e "${red}Debian 8+ required${plain}\n" && exit 1
    fi
fi

confirm() {
    if [[ $# > 1 ]]; then
        echo && read -rp "$1 [default: $2]: " temp
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

before_show_menu() {
    echo ""
    echo -ne " ${ARROW} Press ${bold}Enter${plain} to continue..."
    read temp
    show_menu
}

# 0: running, 1: not running, 2: not installed
check_status() {
    if [[ ! -f /usr/local/v2sp/v2sp ]]; then
        return 2
    fi
    if [[ x"${release}" == x"alpine" ]]; then
        temp=$(service v2sp status 2>/dev/null | awk '{print $3}')
        if [[ x"${temp}" == x"started" ]]; then
            return 0
        else
            return 1
        fi
    else
        temp=$(systemctl status v2sp 2>/dev/null | grep Active | awk '{print $3}' | cut -d "(" -f2 | cut -d ")" -f1)
        if [[ x"${temp}" == x"running" ]]; then
            return 0
        else
            return 1
        fi
    fi
}

check_enabled() {
    if [[ x"${release}" == x"alpine" ]]; then
        temp=$(rc-update show 2>/dev/null | grep v2sp)
        if [[ x"${temp}" == x"" ]]; then
            return 1
        else
            return 0
        fi
    else
        temp=$(systemctl is-enabled v2sp 2>/dev/null)
        if [[ x"${temp}" == x"enabled" ]]; then
            return 0
        else
            return 1
        fi
    fi
}

check_uninstall() {
    check_status
    if [[ $? != 2 ]]; then
        echo ""
        echo -e "${red}v2sp already installed${plain}"
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
        echo -e "${red}v2sp not installed${plain}"
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

# Show status line
show_status() {
    local status="" auto="" uptime=""
    
    check_status
    case $? in
        0) status="${green}Running${plain}" ;;
        1) status="${yellow}Stopped${plain}" ;;
        2) status="${red}Not Installed${plain}" && echo -e "  Status: ${status}" && return ;;
    esac
    
    check_enabled
    [[ $? == 0 ]] && auto="${green}ON${plain}" || auto="${red}OFF${plain}"
    
    uptime=$(get_uptime)
    
    echo -e "  Status: ${status}  |  Auto-start: ${auto}  |  Uptime: ${uptime}"
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
        echo && echo -n -e "Enter version (default: latest): " && read version
    else
        version=$2
    fi
    bash <(curl -Ls https://raw.githubusercontent.com/nsevo/v2sp-script/master/install.sh) $version
    if [[ $? == 0 ]]; then
        echo -e "${green}Update complete, v2sp restarted${plain}"
        exit
    fi
    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

config() {
    echo "v2sp will restart after config change"
    vi /etc/v2sp/config.json
    sleep 2
    restart
    check_status
    case $? in
        0) echo -e "Status: ${green}Running${plain}" ;;
        1) echo -e "Start failed. View logs? [Y/n]"
           read -e -rp "(default: y):" yn
           [[ -z ${yn} ]] && yn="y"
           [[ ${yn} == [Yy] ]] && show_log ;;
        2) echo -e "Status: ${red}Not Installed${plain}" ;;
    esac
}

uninstall() {
    confirm "Uninstall v2sp?" "n"
    if [[ $? != 0 ]]; then
        [[ $# == 0 ]] && show_menu
        return 0
    fi
    
    echo ""
    echo -e "${bold}Uninstalling v2sp...${plain}"
    
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
    
    rm /etc/v2sp/ -rf >/dev/null 2>&1
    rm /usr/local/v2sp/ -rf >/dev/null 2>&1
    rm /usr/bin/v2sp -f >/dev/null 2>&1
    
    echo -e "${green}[OK] v2sp completely removed${plain}"
    echo ""
    exit 0
}

start() {
    check_status
    if [[ $? == 0 ]]; then
        echo -e "${yellow}v2sp is already running${plain}"
    else
        if [[ x"${release}" == x"alpine" ]]; then
            service v2sp start >/dev/null 2>&1
        else
            systemctl start v2sp >/dev/null 2>&1
        fi
        sleep 2
        check_status
        if [[ $? == 0 ]]; then
            echo -e "${green}v2sp started successfully${plain}"
        else
            echo -e "${red}v2sp failed to start, check: v2sp log${plain}"
        fi
    fi
    [[ $# == 0 ]] && before_show_menu
}

stop() {
    if [[ x"${release}" == x"alpine" ]]; then
        service v2sp stop >/dev/null 2>&1
    else
        systemctl stop v2sp >/dev/null 2>&1
    fi
    sleep 2
    check_status
    if [[ $? == 1 ]]; then
        echo -e "${green}v2sp stopped${plain}"
    else
        echo -e "${yellow}Stopping...${plain}"
    fi
    [[ $# == 0 ]] && before_show_menu
}

restart() {
    if [[ x"${release}" == x"alpine" ]]; then
        service v2sp stop >/dev/null 2>&1
        sleep 1
        service v2sp start >/dev/null 2>&1
    else
        systemctl stop v2sp >/dev/null 2>&1
        sleep 1
        systemctl start v2sp >/dev/null 2>&1
    fi
    sleep 2
    check_status
    if [[ $? == 0 ]]; then
        echo -e "${green}v2sp restarted successfully${plain}"
    else
        echo -e "${red}v2sp restart failed, check logs${plain}"
    fi
    [[ $# == 0 ]] && before_show_menu
}

status() {
    if [[ x"${release}" == x"alpine" ]]; then
        service v2sp status
    else
        systemctl status v2sp
    fi
    [[ $# == 0 ]] && before_show_menu
}

enable() {
    if [[ x"${release}" == x"alpine" ]]; then
        rc-update add v2sp >/dev/null 2>&1
    else
        systemctl enable v2sp >/dev/null 2>&1
    fi
    if [[ $? == 0 ]]; then
        echo -e "${green}Auto-start enabled${plain}"
    else
        echo -e "${red}Failed${plain}"
    fi
    [[ $# == 0 ]] && before_show_menu
}

disable() {
    if [[ x"${release}" == x"alpine" ]]; then
        rc-update del v2sp >/dev/null 2>&1
    else
        systemctl disable v2sp >/dev/null 2>&1
    fi
    if [[ $? == 0 ]]; then
        echo -e "${green}Auto-start disabled${plain}"
    else
        echo -e "${red}Failed${plain}"
    fi
    [[ $# == 0 ]] && before_show_menu
}

show_log() {
    if [[ x"${release}" == x"alpine" ]]; then
        echo -e "${red}Log viewing not supported on Alpine${plain}\n"
    else
        journalctl -u v2sp.service -e --no-pager -f
    fi
    [[ $# == 0 ]] && before_show_menu
}

install_bbr() {
    bash <(curl -L -s https://github.com/ylx2016/Linux-NetSpeed/raw/master/tcpx.sh)
}

update_shell() {
    wget -O /usr/bin/v2sp -N --no-check-certificate https://raw.githubusercontent.com/nsevo/v2sp-script/master/v2sp.sh
    if [[ $? != 0 ]]; then
        echo -e "${red}Download failed${plain}"
        before_show_menu
    else
        chmod +x /usr/bin/v2sp
        echo -e "${green}Script updated, please re-run${plain}" && exit 0
    fi
}

generate_x25519_key() {
    echo -n "Generating X25519 key: "
    /usr/local/v2sp/v2sp x25519
    echo ""
    [[ $# == 0 ]] && before_show_menu
}

show_v2sp_version() {
    echo -n "v2sp version: "
    /usr/local/v2sp/v2sp version
    echo ""
    [[ $# == 0 ]] && before_show_menu
}

generate_config_file() {
    fetch_initconfig_and_run
    [[ $# == 0 ]] && before_show_menu
}

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
    echo -e "${green}Firewall ports opened${plain}"
}

show_usage() {
    echo "v2sp management script usage:"
    echo "-----------------------------------"
    echo "v2sp              - Show menu"
    echo "v2sp start        - Start v2sp"
    echo "v2sp stop         - Stop v2sp"
    echo "v2sp restart      - Restart v2sp"
    echo "v2sp status       - View status"
    echo "v2sp enable       - Enable auto-start"
    echo "v2sp disable      - Disable auto-start"
    echo "v2sp log          - View logs"
    echo "v2sp update       - Update v2sp"
    echo "v2sp install      - Install v2sp"
    echo "v2sp uninstall    - Uninstall v2sp"
    echo "v2sp version      - Show version"
    echo "v2sp x25519       - Generate key"
    echo "v2sp generate     - Generate config"
    echo "-----------------------------------"
}

show_menu() {
    clear
    echo ""
    print_center "${bold}${cyan}v2sp${plain}"
    print_line "-"
    show_status
    print_line "="
    echo ""
    
    # Quick Actions
    echo -e "${bold}Quick Actions${plain}"
    echo -e "  ${bold}[R]${plain} Restart   ${bold}[S]${plain} Stop   ${bold}[L]${plain} Logs   ${bold}[E]${plain} Edit Config   ${bold}[H]${plain} Help"
    echo ""
    
    # Service Control
    echo -e "${bold}Service${plain}"
    print_columns "  ${green}[1]${plain} Start" "  ${green}[4]${plain} Enable auto-start"
    print_columns "  ${green}[2]${plain} Stop" "  ${green}[5]${plain} Disable auto-start"
    print_columns "  ${green}[3]${plain} Restart" "  ${green}[6]${plain} View status"
    echo ""
    
    # Configuration
    echo -e "${bold}Configuration${plain}"
    print_columns "  ${green}[7]${plain} Edit config" "  ${green}[9]${plain} Generate X25519 key"
    print_columns "  ${green}[8]${plain} Generate config" ""
    echo ""
    
    # Maintenance
    echo -e "${bold}Maintenance${plain}"
    print_columns "  ${green}[10]${plain} Update v2sp" "  ${green}[13]${plain} Uninstall v2sp"
    print_columns "  ${green}[11]${plain} Update script" "  ${green}[14]${plain} Install BBR"
    print_columns "  ${green}[12]${plain} Show version" "  ${green}[15]${plain} Open all ports"
    
    # Check if not installed, show install option
    check_status
    if [[ $? == 2 ]]; then
        echo ""
        print_columns "  ${yellow}[0]${plain} Install v2sp" ""
    fi
    
    echo ""
    print_line "="
    echo -e "  ${red}[Q]${plain} Exit"
    echo ""
    echo -ne " ${ARROW} "
    read -r num
    
    num=$(echo "$num" | tr '[:upper:]' '[:lower:]')
    
    case "${num}" in
        0) check_uninstall && install ;;
        1) check_install && start ;;
        2|s) check_install && stop ;;
        3|r) check_install && restart ;;
        4) check_install && enable ;;
        5) check_install && disable ;;
        6) check_install && status ;;
        7|e) config ;;
        8) generate_config_file ;;
        9) check_install && generate_x25519_key ;;
        10) check_install && update ;;
        11) update_shell ;;
        12) check_install && show_v2sp_version ;;
        13) check_install && uninstall ;;
        14) install_bbr ;;
        15) open_ports && before_show_menu ;;
        l) check_install && show_log ;;
        h) show_usage && before_show_menu ;;
        q) exit 0 ;;
        *) echo -e " ${ERR} Invalid" && sleep 1 ;;
    esac
    
    show_menu
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
        *) show_usage ;;
    esac
else
    show_menu
fi

