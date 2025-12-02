#!/bin/bash

# Colors
red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
cyan='\033[0;36m'
bold='\033[1m'
plain='\033[0m'

print_usage() {
    echo ""
    echo -e "${bold}Input format:${plain}"
    echo -e "  ${cyan}URL KEY NODE_ID [NODE_ID ...]${plain}"
    echo ""
    echo -e "${bold}Examples:${plain}"
    echo -e "  ${green}https://example.com/v2sp_api.php mykey123 209${plain}"
    echo -e "  ${green}https://example.com/v2sp_api.php mykey123 209 210 211${plain}"
    echo ""
}

select_cert_mode() {
    echo ""
    echo -e "${bold}SSL Certificate Mode:${plain}"
    echo -e "  ${green}1${plain}) none  - No TLS (for Reality or plain)"
    echo -e "  ${green}2${plain}) file  - Use existing certificate files"
    echo -e "  ${green}3${plain}) http  - Auto-apply via HTTP (port 80 required)"
    echo -e "  ${green}4${plain}) dns   - Auto-apply via DNS (Cloudflare, etc.)"
    echo ""
    echo -ne "Select [1-4, default: 2]: "
    read -r cert_choice
    
    case "$cert_choice" in
        1) echo "none" ;;
        3) echo "http" ;;
        4) echo "dns" ;;
        *) echo "file" ;;
    esac
}

generate_node_json() {
    local url=$1
    local key=$2
    local id=$3
    local cert_mode=$4
    local cert_domain=$5
    
    # Build CertConfig based on mode
    local cert_config=""
    case "$cert_mode" in
        none)
            cert_config='"CertConfig": { "CertMode": "none" }'
            ;;
        file)
            cert_config='"CertConfig": {
                "CertMode": "file",
                "CertDomain": "'"$cert_domain"'",
                "CertFile": "/etc/v2sp/fullchain.cer",
                "KeyFile": "/etc/v2sp/cert.key"
            }'
            ;;
        http)
            cert_config='"CertConfig": {
                "CertMode": "http",
                "CertDomain": "'"$cert_domain"'"
            }'
            ;;
        dns)
            cert_config='"CertConfig": {
                "CertMode": "dns",
                "CertDomain": "'"$cert_domain"'",
                "Provider": "cloudflare",
                "DNSEnv": {
                    "CF_DNS_API_TOKEN": "YOUR_CLOUDFLARE_TOKEN"
                }
            }'
            ;;
    esac
    
    cat <<EOF
{
            "ApiHost": "$url",
            "ApiKey": "$key",
            "NodeID": $id,
            "Timeout": 30,
            "ListenIP": "0.0.0.0",
            "SendIP": "0.0.0.0",
            "DeviceOnlineMinTraffic": 200,
            "EnableProxyProtocol": false,
            "EnableUot": true,
            "EnableTFO": true,
            "DNSType": "UseIPv4",
            $cert_config
        }
EOF
}

generate_config_file() {
    echo ""
    echo -e "${bold}${cyan}v2sp Config Generator${plain}"
    echo -e "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    print_usage
    
    echo -e "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo -ne "${cyan}>${plain} "
    read -r input
    
    # Check empty input
    if [[ -z "$input" ]]; then
        echo -e "${red}No input provided${plain}"
        return 1
    fi
    
    # Parse input
    read -ra parts <<< "$input"
    
    if [[ ${#parts[@]} -lt 3 ]]; then
        echo -e "${red}Invalid input. Need at least: URL KEY NODE_ID${plain}"
        return 1
    fi
    
    local url="${parts[0]}"
    local key="${parts[1]}"
    local node_ids=("${parts[@]:2}")
    
    # Validate URL
    if [[ ! "$url" =~ ^https?:// ]]; then
        echo -e "${red}Invalid URL: $url${plain}"
        return 1
    fi
    
    # Validate node IDs
    local valid_ids=()
    for id in "${node_ids[@]}"; do
        if [[ "$id" =~ ^[0-9]+$ ]] && [[ "$id" -gt 0 ]]; then
            valid_ids+=("$id")
        else
            echo -e "${red}Invalid node ID: $id (must be positive integer)${plain}"
            return 1
        fi
    done

    if [[ ${#valid_ids[@]} -eq 0 ]]; then
        echo -e "${red}No valid node IDs${plain}"
        return 1
    fi
    
    # Select certificate mode
    local cert_mode=""
    cert_mode=$(select_cert_mode)
    
    # Get domain for TLS modes
    local cert_domain=""
    if [[ "$cert_mode" != "none" ]]; then
        echo ""
        echo -ne "Enter domain (e.g. node1.example.com): "
        read -r cert_domain
        if [[ -z "$cert_domain" ]]; then
            echo -e "${red}Domain is required for TLS${plain}"
            return 1
        fi
    fi
    
    echo ""
    echo -e "${bold}Configuration:${plain}"
    echo -e "  URL: ${green}$url${plain}"
    echo -e "  Key: ${green}$key${plain}"
    echo -e "  Nodes: ${cyan}${valid_ids[*]}${plain}"
    echo -e "  SSL Mode: ${cyan}$cert_mode${plain}"
    [[ -n "$cert_domain" ]] && echo -e "  Domain: ${cyan}$cert_domain${plain}"
    echo ""
    
    # Confirm
    echo -ne "Generate config? [Y/n]: "
    read -r confirm
    if [[ "$confirm" =~ ^[Nn] ]]; then
        echo -e "${yellow}Cancelled${plain}"
        return 0
    fi

    # Backup existing config
    if [[ -f /etc/v2sp/config.json ]]; then
        cp /etc/v2sp/config.json /etc/v2sp/config.json.bak
        echo -e "  ${green}[+]${plain} Backed up existing config"
    fi
    
    # Generate nodes JSON
    local nodes_json=""
    local first=true
    for id in "${valid_ids[@]}"; do
        if [[ "$first" == true ]]; then
            first=false
        else
            nodes_json+=","
        fi
        nodes_json+=$'\n'
        nodes_json+=$(generate_node_json "$url" "$key" "$id" "$cert_mode" "$cert_domain")
    done
    
    # Create config directory
    mkdir -p /etc/v2sp
    
    # Generate config.json
    cat > /etc/v2sp/config.json <<EOF
{
    "Log": {
        "Level": "error",
        "Output": ""
    },
    "Cores": [
        {
            "Type": "xray",
            "Log": {
                "Level": "error",
                "ErrorPath": "/etc/v2sp/error.log"
            },
            "OutboundConfigPath": "/etc/v2sp/custom_outbound.json",
            "RouteConfigPath": "/etc/v2sp/route.json"
        },
        {
            "Type": "hysteria2",
            "Log": {
                "Level": "error",
                "ErrorPath": "/etc/v2sp/hy2_error.log"
            },
            "BinaryPath": "/usr/local/bin/hysteria",
            "ConfigDir": "/etc/v2sp/hy2"
        }
    ],
    "Nodes": [${nodes_json}
    ]
}
EOF
    echo -e "  ${green}[+]${plain} Generated /etc/v2sp/config.json"
    
    # Generate custom_outbound.json
    cat > /etc/v2sp/custom_outbound.json <<'EOF'
[
    {
        "tag": "IPv4_out",
        "protocol": "freedom",
        "settings": {
            "domainStrategy": "UseIPv4v6"
        }
    },
    {
        "tag": "IPv6_out",
        "protocol": "freedom",
        "settings": {
            "domainStrategy": "UseIPv6"
        }
    },
    {
        "protocol": "blackhole",
        "tag": "block"
    }
]
EOF
    echo -e "  ${green}[+]${plain} Generated /etc/v2sp/custom_outbound.json"
    
    # Generate route.json
    cat > /etc/v2sp/route.json <<'EOF'
{
    "domainStrategy": "AsIs",
    "rules": [
        {
            "outboundTag": "block",
            "ip": [
                "geoip:private"
            ]
        },
        {
            "outboundTag": "block",
            "ip": [
                "127.0.0.1/32",
                "10.0.0.0/8",
                "fc00::/7",
                "fe80::/10",
                "172.16.0.0/12"
            ]
        },
        {
            "outboundTag": "IPv4_out",
            "network": "udp,tcp"
        }
    ]
}
EOF
    echo -e "  ${green}[+]${plain} Generated /etc/v2sp/route.json"
    
    echo ""
    echo -e "${green}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"
    echo -e "  ${bold}Config generated successfully${plain}"
    echo -e "${green}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"
    echo ""
    
    # Restart service
    if command -v v2sp &> /dev/null; then
        echo -ne "Restart v2sp now? [Y/n]: "
        read -r restart_confirm
        if [[ ! "$restart_confirm" =~ ^[Nn] ]]; then
            v2sp restart
        fi
    fi
}
