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

# Check if protocol requires TLS certificate
# Returns: "required" | "optional" | "none" | "reality"
check_tls_requirement() {
    local node_type=$1
    local tls_value=$2
    
    case "$node_type" in
        # These protocols ALWAYS require TLS
        trojan|hysteria|hysteria2)
            echo "required"
            ;;
        # These protocols NEVER need TLS
        shadowsocks)
            echo "none"
            ;;
        # VMess/VLess depends on tls field
        vmess|vless)
            case "$tls_value" in
                1) echo "required" ;;    # Normal TLS
                2) echo "reality" ;;     # Reality (no cert needed)
                *) echo "none" ;;        # No TLS
            esac
            ;;
        *)
            echo "none"
            ;;
    esac
}

# Fetch node config from API and extract info
fetch_node_info() {
    local url=$1
    local key=$2
    local node_id=$3
    
    # Build API URL
    local api_url="${url}?action=config&node_id=${node_id}&token=${key}"
    
    # Fetch config
    local response
    response=$(curl -s --connect-timeout 10 "$api_url" 2>/dev/null)
    
    if [[ -z "$response" ]]; then
        echo ""
        return 1
    fi
    
    # Extract fields using grep/sed (lightweight JSON parsing)
    local node_type server_name tls
    node_type=$(echo "$response" | grep -o '"node_type"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*: *"\([^"]*\)".*/\1/')
    server_name=$(echo "$response" | grep -o '"server_name"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*: *"\([^"]*\)".*/\1/')
    tls=$(echo "$response" | grep -o '"tls"[[:space:]]*:[[:space:]]*[0-9]*' | sed 's/.*: *//')
    
    # Default tls to 0 if not found
    [[ -z "$tls" ]] && tls="0"
    
    # Return: node_type|server_name|tls
    echo "${node_type}|${server_name}|${tls}"
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
        http)
            cert_config='"CertConfig": {
                "CertMode": "http",
                "CertDomain": "'"$cert_domain"'"
            }'
            ;;
        none|reality)
            cert_config='"CertConfig": {
                "CertMode": "none"
            }'
            ;;
        *)
            cert_config='"CertConfig": {
                "CertMode": "file",
                "CertDomain": "'"${cert_domain:-your-domain.com}"'",
                "CertFile": "/etc/v2sp/fullchain.cer",
                "KeyFile": "/etc/v2sp/cert.key"
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
    
    echo ""
    echo -e "${bold}Fetching node configurations...${plain}"
    
    # Fetch info for each node
    declare -A node_type_map
    declare -A node_domain_map
    declare -A node_tls_map
    declare -A node_cert_req_map
    
    for id in "${valid_ids[@]}"; do
        echo -ne "  Node $id: "
        local info
        info=$(fetch_node_info "$url" "$key" "$id")
        
        if [[ -n "$info" ]]; then
            IFS='|' read -r node_type server_name tls <<< "$info"
            node_type_map[$id]="$node_type"
            node_domain_map[$id]="$server_name"
            node_tls_map[$id]="$tls"
            
            # Check TLS requirement
            local cert_req
            cert_req=$(check_tls_requirement "$node_type" "$tls")
            node_cert_req_map[$id]="$cert_req"
            
            # Display status
            case "$cert_req" in
                required)
                    if [[ -n "$server_name" ]]; then
                        echo -e "${green}$node_type${plain} -> ${cyan}$server_name${plain} (TLS required)"
                    else
                        echo -e "${green}$node_type${plain} (TLS required, ${yellow}no domain found${plain})"
                    fi
                    ;;
                reality)
                    echo -e "${green}$node_type${plain} (Reality, no cert needed)"
                    ;;
                none)
                    echo -e "${green}$node_type${plain} (no TLS)"
                    ;;
                *)
                    echo -e "${green}$node_type${plain}"
                    ;;
            esac
        else
            echo -e "${yellow}Failed to fetch (will use defaults)${plain}"
            node_type_map[$id]=""
            node_domain_map[$id]=""
            node_tls_map[$id]="0"
            node_cert_req_map[$id]="none"
        fi
    done
    
    echo ""
    echo -e "${bold}Configuration:${plain}"
    echo -e "  URL: ${green}$url${plain}"
    echo -e "  Key: ${green}$key${plain}"
    echo -e "  Nodes: ${cyan}${valid_ids[*]}${plain}"
    echo ""
    
    # Check if any node requires TLS
    local has_tls_nodes=false
    for id in "${valid_ids[@]}"; do
        if [[ "${node_cert_req_map[$id]}" == "required" && -n "${node_domain_map[$id]}" ]]; then
            has_tls_nodes=true
            break
        fi
    done
    
    # Ask about certificate mode
    local auto_cert="n"
    if [[ "$has_tls_nodes" == true ]]; then
        echo -e "${bold}TLS certificates required for some nodes.${plain}"
        echo -e "  ${cyan}Auto-apply via HTTP? (requires port 80)${plain}"
        echo -ne "Enable auto-certificate? [Y/n]: "
        read -r auto_cert
        if [[ ! "$auto_cert" =~ ^[Nn] ]]; then
            auto_cert="y"
        fi
        echo ""
    fi
    
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
        
        local cert_mode="file"
        local cert_domain="${node_domain_map[$id]}"
        local cert_req="${node_cert_req_map[$id]}"
        
        # Determine cert mode based on requirement
        case "$cert_req" in
            required)
                if [[ "$auto_cert" == "y" && -n "$cert_domain" ]]; then
                    cert_mode="http"
                else
                    cert_mode="file"
                fi
                ;;
            reality|none)
                cert_mode="none"
                ;;
        esac
        
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
    
    echo ""
    echo -e "${green}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"
    echo -e "  ${bold}Config generated successfully${plain}"
    echo ""
    
    # Show summary
    for id in "${valid_ids[@]}"; do
        local domain="${node_domain_map[$id]}"
        local node_type="${node_type_map[$id]:-unknown}"
        local cert_req="${node_cert_req_map[$id]}"
        
        case "$cert_req" in
            required)
                if [[ "$auto_cert" == "y" && -n "$domain" ]]; then
                    echo -e "  Node $id: ${green}$node_type${plain} -> ${cyan}$domain${plain} (auto-cert)"
                elif [[ -n "$domain" ]]; then
                    echo -e "  Node $id: ${green}$node_type${plain} -> ${cyan}$domain${plain} (manual cert)"
                else
                    echo -e "  Node $id: ${green}$node_type${plain} (${yellow}needs cert config${plain})"
                fi
                ;;
            reality)
                echo -e "  Node $id: ${green}$node_type${plain} (Reality)"
                ;;
            none)
                echo -e "  Node $id: ${green}$node_type${plain}"
                ;;
        esac
    done
    
    echo ""
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

# Main
generate_config_file
