#!/bin/bash

# Colors
red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
cyan='\033[0;36m'
dim='\033[2m'
bold='\033[1m'
plain='\033[0m'

# Progress bar with blocks
TOTAL_STEPS=6
CURRENT_STEP=0

progress_bar() {
    local current=$1
    local total=$2
    local width=30
    local percentage=$((current * 100 / total))
    local filled=$((width * current / total))
    local empty=$((width - filled))
    
    echo -ne "\r  ["
    printf "%${filled}s" | tr ' ' '█'
    printf "%${empty}s" | tr ' ' '░'
    echo -ne "] ${percentage}% (${current}/${total})"
}

step_start() {
    CURRENT_STEP=$((CURRENT_STEP + 1))
    echo -ne "\r  [${cyan}${CURRENT_STEP}/${TOTAL_STEPS}${plain}] $1..."
}

step_ok() {
    echo -e "\r  ${green}[+]${plain} $1                              "
}

step_fail() {
    echo -e "\r  ${red}[-]${plain} $1"
    [[ -n "$2" ]] && echo -e "      ${dim}$2${plain}"
}

step_warn() {
    echo -e "  ${yellow}[!]${plain} $1"
}

cur_dir=$(pwd)

# Check root
[[ $EUID -ne 0 ]] && echo -e "${red}Error: Root required${plain}" && exit 1

# Detect OS
if [[ -f /etc/redhat-release ]]; then
    release="centos"
elif cat /etc/issue | grep -Eqi "alpine"; then
    release="alpine"
elif cat /etc/issue | grep -Eqi "debian"; then
    release="debian"
elif cat /etc/issue | grep -Eqi "ubuntu"; then
    release="ubuntu"
elif cat /proc/version | grep -Eqi "debian"; then
    release="debian"
elif cat /proc/version | grep -Eqi "ubuntu"; then
    release="ubuntu"
elif cat /proc/version | grep -Eqi "centos|red hat|redhat|rocky|alma|oracle linux"; then
    release="centos"
elif cat /proc/version | grep -Eqi "arch"; then
    release="arch"
else
    echo -e "${red}Unsupported OS${plain}" && exit 1
fi

# Detect arch
arch=$(uname -m)
if [[ $arch == "x86_64" || $arch == "x64" || $arch == "amd64" ]]; then
    arch="64"
elif [[ $arch == "aarch64" || $arch == "arm64" ]]; then
    arch="arm64-v8a"
elif [[ $arch == "s390x" ]]; then
    arch="s390x"
else
    arch="64"
fi

# Check 64bit
[ "$(getconf WORD_BIT)" != '32' ] && [ "$(getconf LONG_BIT)" != '64' ] && \
    echo -e "${red}32-bit not supported${plain}" && exit 2

# OS version check
if [[ -f /etc/os-release ]]; then
    os_version=$(awk -F'[= ."]' '/VERSION_ID/{print $3}' /etc/os-release)
fi
[[ -z "$os_version" && -f /etc/lsb-release ]] && \
    os_version=$(awk -F'[= ."]+' '/DISTRIB_RELEASE/{print $2}' /etc/lsb-release)

if [[ x"${release}" == x"centos" && ${os_version} -le 6 ]]; then
    echo -e "${red}CentOS 7+ required${plain}" && exit 1
elif [[ x"${release}" == x"ubuntu" && ${os_version} -lt 16 ]]; then
    echo -e "${red}Ubuntu 16+ required${plain}" && exit 1
elif [[ x"${release}" == x"debian" && ${os_version} -lt 8 ]]; then
    echo -e "${red}Debian 8+ required${plain}" && exit 1
    fi

install_hysteria2() {
    # Check if already installed
    if [[ -f /usr/local/bin/hysteria ]]; then
        return 0
    fi
    
    # Detect arch for Hysteria2
    local hy2_arch=""
    case "$(uname -m)" in
        x86_64|amd64)
            hy2_arch="amd64"
            ;;
        aarch64|arm64)
            hy2_arch="arm64"
            ;;
        *)
            # Unsupported arch, skip
            return 0
            ;;
    esac
    
    # Get latest version
    local hy2_version=""
    hy2_version=$(curl -Ls "https://api.github.com/repos/apernet/hysteria/releases/latest" 2>/dev/null | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
    if [[ -z "$hy2_version" ]]; then
        # Silent fail, not critical
        return 0
    fi
    
    # Download Hysteria2
    local hy2_url="https://github.com/apernet/hysteria/releases/download/${hy2_version}/hysteria-linux-${hy2_arch}"
    wget --no-check-certificate -q -O /usr/local/bin/hysteria "$hy2_url" 2>/dev/null
    if [[ $? -eq 0 ]]; then
        chmod +x /usr/local/bin/hysteria
        mkdir -p /etc/v2sp/hy2
    fi
}

install_base() {
    case "${release}" in
        centos)
            yum install -y -q epel-release wget curl unzip tar socat ca-certificates >/dev/null 2>&1
            update-ca-trust force-enable >/dev/null 2>&1
            ;;
        alpine)
            apk add --quiet wget curl unzip tar socat ca-certificates >/dev/null 2>&1
            update-ca-certificates >/dev/null 2>&1
            ;;
        debian|ubuntu)
            apt-get update -qq >/dev/null 2>&1
            apt-get install -qq -y wget curl unzip tar cron socat ca-certificates >/dev/null 2>&1
            update-ca-certificates >/dev/null 2>&1
            ;;
        arch)
            pacman -Sy --noconfirm --quiet >/dev/null 2>&1
            pacman -S --noconfirm --needed --quiet wget curl unzip tar cron socat ca-certificates >/dev/null 2>&1
            ;;
    esac
}

check_status() {
    [[ ! -f /usr/local/v2sp/v2sp ]] && return 2
    
    if [[ x"${release}" == x"alpine" ]]; then
        temp=$(service v2sp status 2>/dev/null | awk '{print $3}')
        [[ x"${temp}" == x"started" ]] && return 0 || return 1
    else
        temp=$(systemctl status v2sp 2>/dev/null | grep Active | awk '{print $3}' | cut -d "(" -f2 | cut -d ")" -f1)
        [[ x"${temp}" == x"running" ]] && return 0 || return 1
    fi
}

install_v2sp() {
    local last_version=""
    local archive="/usr/local/v2sp/v2sp-linux.zip"

    # Clean old installation
    [[ -e /usr/local/v2sp/ ]] && rm -rf /usr/local/v2sp/
    mkdir -p /usr/local/v2sp/
    cd /usr/local/v2sp/

    # Step 1: Download
    step_start "Fetching v2sp"
    if [ $# == 0 ]; then
        last_version=$(curl -Ls "https://api.github.com/repos/nsevo/v2sp/releases/latest" 2>/dev/null | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
        if [[ ! -n "$last_version" ]]; then
            step_fail "Fetching v2sp" "GitHub API limit or network issue"
            exit 1
        fi
    else
        last_version=$1
    fi
    
    wget --no-check-certificate -q -O "${archive}" \
        "https://github.com/nsevo/v2sp/releases/download/${last_version}/v2sp-linux-${arch}.zip" 2>&1 | \
        grep -o "[0-9]\+%" | while read percent; do
            progress_bar ${percent%\%} 100
        done
    
        if [[ $? -ne 0 ]]; then
        step_fail "Download v2sp ${last_version}" "Network error or invalid version"
            exit 1
        fi
    step_ok "Downloaded v2sp ${last_version}"
    
    # Step 2: Extract and install
    step_start "Installing core"
    unzip -qq v2sp-linux.zip 2>/dev/null
    rm -f v2sp-linux.zip
    chmod +x v2sp
    mkdir -p /etc/v2sp/
    cp geoip.dat /etc/v2sp/ 2>/dev/null
    cp geosite.dat /etc/v2sp/ 2>/dev/null
    
    # Setup service
    if [[ x"${release}" == x"alpine" ]]; then
        cat > /etc/init.d/v2sp <<'EOF'
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
        rc-update add v2sp default >/dev/null 2>&1
    else
        cat > /etc/systemd/system/v2sp.service <<'EOF'
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
        systemctl daemon-reload >/dev/null 2>&1
        systemctl stop v2sp >/dev/null 2>&1
        systemctl enable v2sp >/dev/null 2>&1
    fi
    step_ok "Core installed ${last_version}"
    
    # Step 3: Configuration
    step_start "Configuring files"
    local first_install=false
    if [[ ! -f /etc/v2sp/config.json ]]; then
        cp config.json /etc/v2sp/ 2>/dev/null
        first_install=true
    else
        # Restart existing installation
        if [[ x"${release}" == x"alpine" ]]; then
            service v2sp start >/dev/null 2>&1
        else
            systemctl start v2sp >/dev/null 2>&1
        fi
        sleep 1
        check_status
        if [[ $? != 0 ]]; then
            step_warn "Service may have failed, check: v2sp log"
        fi
    fi
    
    # Copy default configs
    [[ ! -f /etc/v2sp/dns.json ]] && cp dns.json /etc/v2sp/ 2>/dev/null
    [[ ! -f /etc/v2sp/route.json ]] && cp route.json /etc/v2sp/ 2>/dev/null
    [[ ! -f /etc/v2sp/custom_outbound.json ]] && cp custom_outbound.json /etc/v2sp/ 2>/dev/null
    [[ ! -f /etc/v2sp/custom_inbound.json ]] && cp custom_inbound.json /etc/v2sp/ 2>/dev/null
    step_ok "Config files ready"
    
    # Step 4: Management script
    step_start "Installing management script"
    curl -sLo /usr/bin/v2sp https://raw.githubusercontent.com/nsevo/v2sp-script/master/v2sp.sh 2>/dev/null
    if [[ $? -ne 0 ]]; then
        step_fail "Script download failed"
    else
        chmod +x /usr/bin/v2sp
        [[ ! -L /usr/bin/v2spctl ]] && ln -s /usr/bin/v2sp /usr/bin/v2spctl && chmod +x /usr/bin/v2spctl
        step_ok "Management script installed"
    fi
    
    # Step 5: Install Hysteria2 (optional, for hysteria2 nodes)
    step_start "Installing Hysteria2"
    install_hysteria2
    step_ok "Hysteria2 ready"
    
    # Step 6: Verify installation
    step_start "Verifying installation"
    local missing=0
    local files=(
        "/etc/v2sp/config.json"
        "/etc/v2sp/dns.json"
        "/etc/v2sp/route.json"
        "/etc/v2sp/geoip.dat"
        "/etc/v2sp/geosite.dat"
    )
    for f in "${files[@]}"; do
        if [[ ! -f "$f" ]]; then
            missing=$((missing + 1))
            # Auto-fix if possible
            case "$f" in
                */geoip.dat) cp /usr/local/v2sp/geoip.dat "$f" 2>/dev/null ;;
                */geosite.dat) cp /usr/local/v2sp/geosite.dat "$f" 2>/dev/null ;;
            esac
        fi
    done
    [[ $missing -gt 0 ]] && step_warn "${missing} file(s) missing, may need manual setup"
    step_ok "Installation verified"
    
    # Cleanup
    cd $cur_dir
    rm -f install.sh
    
    # Summary
    echo ""
    echo -e "${green}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"
    echo -e "  ${bold}v2sp ${last_version} installed${plain}"
    echo -e "${green}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"
    echo ""
    echo -e "  ${cyan}Usage:${plain}"
    echo -e "    v2sp              ${dim}Interactive menu${plain}"
    echo -e "    v2sp start        ${dim}Start service${plain}"
    echo -e "    v2sp stop         ${dim}Stop service${plain}"
    echo -e "    v2sp restart      ${dim}Restart service${plain}"
    echo -e "    v2sp status       ${dim}Check status${plain}"
    echo -e "    v2sp log          ${dim}View logs${plain}"
    echo -e "    v2sp generate     ${dim}Generate config${plain}"
    echo ""
    
    # First install prompt
    if [[ $first_install == true ]]; then
        echo -e "  ${yellow}[!]${plain} First install detected"
        read -rp "  Generate config now? (y/n): " if_generate
        if [[ $if_generate == [Yy] ]]; then
            if [[ -x /usr/local/v2sp/v2sp ]]; then
                /usr/local/v2sp/v2sp config init
            else
                echo -e "  ${red}v2sp binary not found, please reinstall${plain}"
            fi
        fi
    fi
}

# Main
clear
echo ""
echo -e "${bold}${cyan}v2sp Installer${plain}"
echo -e "${dim}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"
echo -e "  OS: ${release} | Arch: ${arch}"
echo -e "${dim}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"
echo ""

step_start "Preparing environment"
install_base
step_ok "Environment ready"

install_v2sp $1
