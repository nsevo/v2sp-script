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
    echo -e "${bold}Usage:${plain}"
    echo -e "  Enter: ${cyan}URL KEY NODE_ID [NODE_ID ...]${plain}"
    echo ""
    echo -e "${bold}Examples:${plain}"
    echo -e "  ${green}https://example.com/v2sp_api.php mykey123 209${plain}"
    echo -e "  ${green}https://example.com/v2sp_api.php mykey123 209 210 211${plain}"
    echo ""
    echo -e "${bold}Note:${plain} Protocol type is auto-detected from panel database"
    echo ""
}

generate_node_json() {
    local url=$1
    local key=$2
    local id=$3
    
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
            "CertConfig": {
                "CertMode": "file",
                "CertFile": "/etc/v2sp/fullchain.cer",
                "KeyFile": "/etc/v2sp/cert.key"
            }
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
    
    echo ""
    echo -e "${bold}Configuration:${plain}"
    echo -e "  URL: ${green}$url${plain}"
    echo -e "  Key: ${green}$key${plain}"
    echo -e "  Nodes: ${cyan}${valid_ids[*]}${plain}"
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
        nodes_json+=$(generate_node_json "$url" "$key" "$id")
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
