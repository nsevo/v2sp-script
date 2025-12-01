#!/bin/bash
# 一键配置

# 协议映射（仅支持 Xray）
declare -A NODE_TYPE_LABELS=(
    ["shadowsocks"]="Shadowsocks"
    ["vless"]="VLESS"
    ["vmess"]="VMess"
    ["trojan"]="Trojan"
    ["hysteria"]="Hysteria"
)

declare -A CORE_PROTOCOL_MATRIX=(
    ["xray"]="shadowsocks vless vmess trojan hysteria"
)

select_node_type() {
    local core=$1
    local options_string="${CORE_PROTOCOL_MATRIX[$core]}"
    read -r -a options <<< "$options_string"

    if [[ ${#options[@]} -eq 1 ]]; then
        echo "${options[0]}"
        return
    fi

    while true; do
        echo -e "${yellow}请选择节点传输协议：${plain}" >&2
        for idx in "${!options[@]}"; do
            local key=${options[$idx]}
            local label=${NODE_TYPE_LABELS[$key]}
            printf "  %d. %s\n" $((idx + 1)) "$label" >&2
        done
        read -rp "请输入：" choice
        if [[ $choice =~ ^[1-9][0-9]*$ ]] && (( choice >= 1 && choice <= ${#options[@]} )); then
            echo "${options[$((choice - 1))]}"
            return
        fi
        echo -e "${red}无效选择，请重新输入。${plain}" >&2
    done
}

# 检查系统是否有 IPv6 地址
check_ipv6_support() {
    if ip -6 addr | grep -q "inet6"; then
        echo "1"  # 支持 IPv6
    else
        echo "0"  # 不支持 IPv6
    fi
}

add_node_config() {
    # 固定使用 xray 内核
        core="xray"
        core_xray=true
    echo -e "${green}使用 Xray 内核${plain}"
    while true; do
        read -rp "请输入节点Node ID：" NodeID
        # 判断NodeID是否为正整数
        if [[ "$NodeID" =~ ^[0-9]+$ ]]; then
            break  # 输入正确，退出循环
        else
            echo "错误：请输入正确的数字作为Node ID。"
        fi
    done

    NodeType=$(select_node_type "$core")
    fastopen=true
    isreality="n"
    istls="n"
    if [ "$NodeType" == "vless" ]; then
        read -rp "请选择是否为reality节点？(y/n)" isreality
    elif [ "$NodeType" == "hysteria" ]; then
        fastopen=false
        istls="y"
    fi

    if [[ "$isreality" != "y" && "$isreality" != "Y" &&  "$istls" != "y" ]]; then
        read -rp "请选择是否进行TLS配置？(y/n)" istls
    fi

    certmode="none"
    certdomain="example.com"
    if [[ "$isreality" != "y" && "$isreality" != "Y" && ( "$istls" == "y" || "$istls" == "Y" ) ]]; then
        echo -e "${yellow}请选择证书申请模式：${plain}"
        echo -e "${green}1. http模式自动申请，节点域名已正确解析${plain}"
        echo -e "${green}2. dns模式自动申请，需填入正确域名服务商API参数${plain}"
        echo -e "${green}3. self模式，自签证书或提供已有证书文件${plain}"
        read -rp "请输入：" certmode
        case "$certmode" in
            1 ) certmode="http" ;;
            2 ) certmode="dns" ;;
            3 ) certmode="self" ;;
        esac
        read -rp "请输入节点证书域名(example.com)：" certdomain
        if [ "$certmode" != "http" ]; then
            echo -e "${red}请手动修改配置文件后重启 v2sp！${plain}"
        fi
    fi
    # 生成 Xray 节点配置（Core 字段可省略，自动默认为 xray）
    node_config=$(cat <<EOF
{
            "ApiHost": "$ApiHost",
            "ApiKey": "$ApiKey",
            "NodeID": $NodeID,
            "NodeType": "$NodeType",
            "Timeout": 30,
            "ListenIP": "0.0.0.0",
            "SendIP": "0.0.0.0",
            "DeviceOnlineMinTraffic": 200,
            "MinReportTraffic": 0,
            "EnableProxyProtocol": false,
            "EnableUot": true,
            "EnableTFO": true,
            "DNSType": "UseIPv4",
            "CertConfig": {
                "CertMode": "$certmode",
                "RejectUnknownSni": false,
                "CertDomain": "$certdomain",
                "CertFile": "/etc/v2sp/fullchain.cer",
                "KeyFile": "/etc/v2sp/cert.key",
                "Email": "noreply@v2sp.com",
                "Provider": "cloudflare",
                "DNSEnv": {
                    "EnvName": "env1"
                }
            }
        },
EOF
)
    nodes_config+=("$node_config")
}

generate_config_file() {
    echo -e "${yellow}v2sp 配置文件生成向导${plain}"
    echo -e "${red}请阅读以下注意事项：${plain}"
    echo -e "${red}1. 目前该功能正处测试阶段${plain}"
    echo -e "${red}2. 生成的配置文件会保存到 /etc/v2sp/config.json${plain}"
    echo -e "${red}3. 原来的配置文件会保存到 /etc/v2sp/config.json.bak${plain}"
    echo -e "${red}4. 目前仅部分支持TLS${plain}"
    echo -e "${red}5. 使用此功能生成的配置文件会自带审计，确定继续？(y/n)${plain}"
    read -rp "请输入：" continue_prompt
    if [[ "$continue_prompt" =~ ^[Nn][Oo]? ]]; then
        exit 0
    fi
    
    nodes_config=()
    first_node=true
    core_xray=true
    fixed_api_info=false
    check_api=false
    
    while true; do
        if [ "$first_node" = true ]; then
            read -rp "请输入面板 API 地址(https://example.com)：" ApiHost
            read -rp "请输入节点接入密钥(API Key)：" ApiKey
            read -rp "是否固定以上面板信息用于后续节点？(y/n)" fixed_api
            if [ "$fixed_api" = "y" ] || [ "$fixed_api" = "Y" ]; then
                fixed_api_info=true
                echo -e "${red}成功固定地址${plain}"
            fi
            first_node=false
            add_node_config
        else
            read -rp "是否继续添加节点配置？(输入y继续，直接回车退出) [y/N] " continue_adding_node
            if [[ ! "$continue_adding_node" =~ ^[Yy]$ ]]; then
                break
            elif [ "$fixed_api_info" = false ]; then
                read -rp "请输入面板 API 地址(https://example.com)：" ApiHost
                read -rp "请输入节点接入密钥(API Key)：" ApiKey
            fi
            add_node_config
        fi
    done

    # 初始化核心配置数组
    cores_config="["

    # 检查并添加xray核心配置
    if [ "$core_xray" = true ]; then
        cores_config+="
    {
        \"Type\": \"xray\",
        \"Log\": {
            \"Level\": \"error\",
            \"ErrorPath\": \"/etc/v2sp/error.log\"
        },
        \"OutboundConfigPath\": \"/etc/v2sp/custom_outbound.json\",
        \"RouteConfigPath\": \"/etc/v2sp/route.json\"
    },"
    fi


    # 移除最后一个逗号并关闭数组
    cores_config+="]"
    cores_config=$(echo "$cores_config" | sed 's/},]$/}]/')

    # 切换到配置文件目录
    cd /etc/v2sp
    
    # 备份旧的配置文件
    mv config.json config.json.bak
    nodes_config_str="${nodes_config[*]}"
    formatted_nodes_config="${nodes_config_str%,}"

    # 创建 config.json 文件
    cat <<EOF > /etc/v2sp/config.json
{
    "Log": {
        "Level": "error",
        "Output": ""
    },
    "Cores": $cores_config,
    "Nodes": [$formatted_nodes_config]
}
EOF
    
    # 创建 custom_outbound.json 文件
    cat <<EOF > /etc/v2sp/custom_outbound.json
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
    
    # 创建 route.json 文件
    cat <<EOF > /etc/v2sp/route.json
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
    echo -e "${green}v2sp 配置文件生成完成,正在重新启动服务${plain}"
    v2sp restart
}
