#!/bin/bash

# Colors
red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
cyan='\033[0;36m'
bold='\033[1m'
plain='\033[0m'

# Supported protocols
PROTOCOLS="vless vmess trojan shadowsocks hysteria"

print_usage() {
    echo ""
    echo -e "${bold}Usage:${plain}"
    echo -e "  Enter: ${cyan}URL KEY PROTOCOL:ID [PROTOCOL:ID ...]${plain}"
    echo ""
    echo -e "${bold}Examples:${plain}"
    echo -e "  ${green}https://api.example.com/v2sp_api.php mykey123 vless:209${plain}"
    echo -e "  ${green}https://api.example.com/v2sp_api.php mykey123 vless:209 vmess:210${plain}"
    echo -e "  ${green}https://api.example.com/v2sp_api.php mykey123 vless:209 trojan:211 shadowsocks:212${plain}"
    echo ""
    echo -e "${bold}Supported protocols:${plain} ${PROTOCOLS}"
    echo ""
}

validate_protocol() {
    local proto=$1
    for p in $PROTOCOLS; do
        [[ "$proto" == "$p" ]] && return 0
    done
    return 1
}

parse_node() {
    local node=$1
    local proto="${node%%:*}"
    local id="${node##*:}"
    
    # Validate format
    if [[ ! "$node" =~ ^[a-z]+:[0-9]+$ ]]; then
        echo -e "${red}Invalid format: $node (expected PROTOCOL:ID)${plain}" >&2
        return 1
    fi
    
    # Validate protocol
    if ! validate_protocol "$proto"; then
        echo -e "${red}Unknown protocol: $proto${plain}" >&2
        echo -e "Supported: ${PROTOCOLS}" >&2
        return 1
    fi
    
    # Validate ID
    if [[ ! "$id" =~ ^[0-9]+$ ]] || [[ "$id" -eq 0 ]]; then
        echo -e "${red}Invalid node ID: $id${plain}" >&2
        return 1
    fi
    
    echo "$proto:$id"
    return 0
}

generate_node_json() {
    local url=$1
    local key=$2
    local proto=$3
    local id=$4
    
    cat <<EOF
        {
            "ApiHost": "$url",
            "ApiKey": "$key",
            "NodeID": $id,
            "NodeType": "$proto",
            "Timeout": 30,
            "ListenIP": "0.0.0.0",
            "SendIP": "0.0.0.0",
            "DeviceOnlineMinTraffic": 200,
            "EnableProxyProtocol": false,
            "EnableUot": true,
            "EnableTFO": true,
            "DNSType": "UseIPv4"
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
        echo -e "${red}Invalid input. Need at least: URL KEY PROTOCOL:ID${plain}"
        return 1
    fi
    
    local url="${parts[0]}"
    local key="${parts[1]}"
    local nodes=("${parts[@]:2}")
    
    # Validate URL
    if [[ ! "$url" =~ ^https?:// ]]; then
        echo -e "${red}Invalid URL: $url${plain}"
        return 1
    fi
    
    # Validate and parse nodes
    local valid_nodes=()
    for node in "${nodes[@]}"; do
        local parsed
        parsed=$(parse_node "$node")
        if [[ $? -eq 0 ]]; then
            valid_nodes+=("$parsed")
        else
            return 1
        fi
    done
    
    if [[ ${#valid_nodes[@]} -eq 0 ]]; then
        echo -e "${red}No valid nodes${plain}"
        return 1
    fi
    
    echo ""
    echo -e "${bold}Configuration:${plain}"
    echo -e "  URL: ${green}$url${plain}"
    echo -e "  Key: ${green}$key${plain}"
    echo -e "  Nodes:"
    for node in "${valid_nodes[@]}"; do
        local proto="${node%%:*}"
        local id="${node##*:}"
        echo -e "    - ${cyan}$proto${plain} (ID: ${green}$id${plain})"
    done
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
    for node in "${valid_nodes[@]}"; do
        local proto="${node%%:*}"
        local id="${node##*:}"
        
        if [[ "$first" == true ]]; then
            first=false
        else
            nodes_json+=","
        fi
        nodes_json+=$'\n'
        nodes_json+=$(generate_node_json "$url" "$key" "$proto" "$id")
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
