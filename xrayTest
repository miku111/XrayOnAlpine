#!/bin/bash

# ==========================================
# Alpine Linux Xray/Hysteria 2 Auto Install
# Fixed & Optimized
# ==========================================

# Auto-install bash if missing (Essential for Alpine)
if [ ! -x "/bin/bash" ]; then
    echo "Bash not found. Installing Bash for Alpine..."
    if command -v apk >/dev/null; then
        apk update && apk add bash
        exec /bin/bash "$0" "$@"
    else
        echo "Error: This script requires apk package manager (Alpine Linux)."
        exit 1
    fi
fi

# Global Variables
CONF_TYPE=""
PORT=""
UUID=""
PUB_KEY=""
SNI=""
SHORT_ID=""

getIP(){
    local serverIP=
    serverIP=$(curl -s -4 http://www.cloudflare.com/cdn-cgi/trace | grep "ip" | awk -F "[=]" '{print $2}')
    if [[ -z "${serverIP}" ]]; then
        serverIP=$(curl -s -6 http://www.cloudflare.com/cdn-cgi/trace | grep "ip" | awk -F "[=]" '{print $2}')
    fi
    echo "${serverIP}"
}

getShortId(){
    hexchars="0123456789abcdef"
    str=""
    for _ in $(seq 1 16); do
        str="$str${hexchars:RANDOM%16:1}"
    done
    echo "$str"
}

# --------------------------
# Xray Configuration Section
# --------------------------

configReality(){
    # Default SNI settings for Auto Mode
    local serverName="www.amazon.com"
    local sniList='["uedata.amazon.com", "corporate.amazon.com", "mp3recs.amazon.com"]'
    SNI="uedata.amazon.com" # Default display SNI

    install_xray_core
    configure_xray_json "$serverName" "$sniList"
}

configRealityRegion(){
    # Region Selection Arrays
    destNames=("www.t-mobile.com" "www.arm.com" "www.tsukuba.ac.jp" "www.hongkongdisneyland.com" "www.china-airlines.com" "sigtelinc.com" "www.bouyguestelecom.fr" "www.mercedes-benz.de" "www.incredibleindia.gov.in" "www.amazon.com")
    sniNames=("business.t-mobile.com" "learn.arm.com" "www.tsukuba.ac.jp" "entitlement.hongkongdisneyland.com" "book.china-airlines.com" "www.sigtelinc.com" "www.bouygtel.fr" "pro.mercedes-benz.com" "www.incredibleindia.org" "corporate.amazon.com")
    
    echo "Please select a region:"
    echo "1. US (T-Mobile)"
    echo "2. UK (ARM)"
    echo "3. JP (Tsukuba)"
    echo "4. HK (Disney)"
    echo "5. TW (China Airlines)"
    echo "6. SG (Singtel)"
    echo "7. FR (Bouygues)"
    echo "8. DE (Benz)"
    echo "9. IN (India)"
    echo "10. Others (Amazon)"

    read -r userInput
    
    # Input validation
    if [[ "$userInput" =~ ^[0-9]+$ ]] && [ "$userInput" -ge 1 ] && [ "$userInput" -le 10 ]; then
        index=$((userInput - 1))
        local serverName=${destNames[$index]}
        local chosenSni=${sniNames[$index]}
        local sniList="[\"$chosenSni\"]"
        SNI="$chosenSni"
    else
        echo "Invalid selection. Defaulting to Amazon (US)."
        local serverName="www.amazon.com"
        local sniList="[\"corporate.amazon.com\"]"
        SNI="corporate.amazon.com"
    fi

    install_xray_core
    configure_xray_json "$serverName" "$sniList"
}

install_xray_core(){
    echo ">>> Preparing Xray Installation..."
    apk update && apk add curl unzip grep

    # Download Xray
    XRAY_VERSION=$(curl -s https://api.github.com/repos/XTLS/Xray-core/releases/latest | grep -Po '"tag_name": "\K.*?(?=")')
    echo ">>> Downloading Xray ${XRAY_VERSION}..."
    curl -L -o /tmp/xray.zip "https://github.com/XTLS/Xray-core/releases/download/${XRAY_VERSION}/Xray-linux-64.zip"

    mkdir -p /usr/local/bin/xray
    mkdir -p /usr/local/etc/xray
    unzip -o /tmp/xray.zip -d /usr/local/bin/xray
    chmod +x /usr/local/bin/xray/xray
    rm -f /tmp/xray.zip

    # OpenRC Script
    cat <<EOF > /etc/init.d/xray
#!/sbin/openrc-run

name="Xray"
description="Xray Proxy Service"

command="/usr/local/bin/xray/xray"
command_args="-config /usr/local/etc/xray/config.json"
pidfile="/var/run/xray.pid"
command_background="yes"

depend() {
    need net
}

start_pre() {
    checkpath --file --mode 0644 --owner root:root /var/run/xray.pid
}
EOF
    chmod +x /etc/init.d/xray
    rc-update add xray default
}

configure_xray_json(){
    local destServer="$1"
    local sniJson="$2"

    # Generate Keys
    UUID=$(/usr/local/bin/xray/xray uuid)
    local reX25519Key=$(/usr/local/bin/xray/xray x25519)
    local rePrivateKey=$(echo "${reX25519Key}" | awk '/PrivateKey:/ {print $2}')
    PUB_KEY=$(echo "${reX25519Key}" | awk '/PublicKey:/ {print $2}') # Fixed grep pattern

    read -t 30 -p "Please input port (default 443): " inputPort
    PORT=${inputPort:-443}

    SHORT_ID=$(getShortId)
    local shortId2=$(getShortId)

    # Config JSON
    cat >/usr/local/etc/xray/config.json<<EOF
{
    "inbounds": [
        {
            "port": $PORT,
            "protocol": "vless",
            "settings": {
                "clients": [
                    {
                        "id": "$UUID",
                        "flow": "xtls-rprx-vision"
                    }
                ],
                "decryption": "none"
            },
            "streamSettings": {
                "network": "tcp",
                "security": "reality",
                "realitySettings": {
                    "show": false,
                    "dest": "${destServer}:443",
                    "xver": 0,
                    "serverNames": $sniJson,
                    "privateKey": "$rePrivateKey",
                    "shortIds": [
                        "$SHORT_ID",
                        "$shortId2"
                    ]
                }
            }
        }
    ],
    "outbounds": [
        {
            "protocol": "freedom",
            "tag": "direct"
        },
        {
            "protocol": "blackhole",
            "tag": "blocked"
        }
    ]    
}
EOF
    
    echo ">>> Restarting Xray..."
    rc-service xray restart
    sleep 1
    
    # Print Result
    client_re
}

client_re(){
    local ip=$(getIP)
    echo
    echo "=========== Reality Config ============"
    echo "Address     : ${ip}"
    echo "Port        : ${PORT}"
    echo "UUID        : ${UUID}"
    echo "Flow        : xtls-rprx-vision"
    echo "Network     : tcp"
    echo "Public Key  : ${PUB_KEY}"
    echo "SNI         : ${SNI}"
    echo "ShortID     : ${SHORT_ID}"
    echo "======================================="
    echo "Link (Copy to Client):"
    echo "vless://${UUID}@${ip}:${PORT}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${SNI}&fp=chrome&pbk=${PUB_KEY}&sid=${SHORT_ID}&type=tcp&headerType=none#Xray_Reality_${ip}"
    echo
}

# --------------------------
# Hysteria 2 Configuration
# --------------------------

installHy2(){
    echo ">>> Installing Hysteria 2..."
    apk add --no-cache bash curl wget openssl coreutils grep

    local hyPasswd=$(openssl rand -base64 24)
    local getPort=$(shuf -i 10000-65000 -n 1)
    local serverIP=$(getIP)

    # Version Detect
    HY2_VERSION=$(curl -s https://api.github.com/repos/apernet/hysteria/releases/latest | grep -oP '"tag_name": "\K(.*?)(?=")')
    if [[ -z "$HY2_VERSION" ]]; then
        echo "Error: Could not detect Hysteria version."
        exit 1
    fi
    HY2_VERSION_ESCAPED=$(echo "$HY2_VERSION" | sed 's/\//%2F/g')

    # Arch Detect
    ARCH=$(uname -m)
    case $ARCH in
        x86_64)  HY2_ARCH="amd64" ;;
        aarch64) HY2_ARCH="arm64" ;;
        armv7l)  HY2_ARCH="armv7" ;;
        *) echo "Unsupported Arch: $ARCH"; exit 1 ;;
    esac

    # Download
    wget -qO /usr/local/bin/hysteria "https://github.com/apernet/hysteria/releases/download/$HY2_VERSION_ESCAPED/hysteria-linux-$HY2_ARCH"
    chmod +x /usr/local/bin/hysteria

    mkdir -p /etc/hysteria/
    
    # Self-signed Cert
    openssl req -x509 -nodes -newkey ec:<(openssl ecparam -name prime256v1) \
        -keyout /etc/hysteria/server.key -out /etc/hysteria/server.crt \
        -subj "/CN=bing.com" -days 3650

    chmod 644 /etc/hysteria/server.key /etc/hysteria/server.crt

    # Config YAML
    cat >/etc/hysteria/config.yaml <<EOF
listen: :$getPort
tls:
  cert: /etc/hysteria/server.crt
  key: /etc/hysteria/server.key
auth:
  type: password
  password: $hyPasswd
masquerade:
  type: proxy
  proxy:
    url: https://bing.com
    rewriteHost: true
quic:
  initStreamReceiveWindow: 26843545 
  maxStreamReceiveWindow: 26843545 
  initConnReceiveWindow: 67108864 
  maxConnReceiveWindow: 67108864 
bandwidth:
  up: 1 gbps
  down: 1 gbps
EOF

    # OpenRC Service
    cat <<EOF > /etc/init.d/hysteria
#!/sbin/openrc-run

name="hysteria"
description="Hysteria 2 Proxy Service"
command="/usr/local/bin/hysteria"
command_args="server -c /etc/hysteria/config.yaml"
command_background="yes"
pidfile="/run/\${RC_SVCNAME}.pid"
output_log="/var/log/hysteria.log"
error_log="/var/log/hysteria.err"

depend() {
    need net
    after firewall
}
EOF
    chmod +x /etc/init.d/hysteria
    rc-update add hysteria default
    
    # UFW Check
    if command -v ufw >/dev/null 2>&1; then
        ufw allow "$getPort"/udp
    fi

    rc-service hysteria restart

    echo "==============================================="
    echo "Hysteria 2 Installed!"
    echo "IP: ${serverIP}"
    echo "Port: ${getPort}"
    echo "Password: ${hyPasswd}"
    echo "==============================================="
    echo "Connection String:"
    echo "hysteria2://${hyPasswd}@${serverIP}:${getPort}/?insecure=1&sni=bing.com#Hysteria2_${serverIP}"
    echo "==============================================="
}

# --------------------------
# Main Menu
# --------------------------

menu(){
    clear
    echo "################################################"
    echo "#       Alpine Linux Xray/Hy2 Installer        #"
    echo "################################################"
    echo "1. Install Xray (VLESS-Reality) [Auto Config]"
    echo "2. Install Xray (VLESS-Reality) [Select Region]"
    echo "3. Install Hysteria 2"
    echo "0. Exit"
    echo "################################################"
    
    read -r -p "Enter choice [1-3]: " option
    
    case "$option" in
        1) configReality ;;
        2) configRealityRegion ;;
        3) installHy2 ;;
        0) exit 0 ;;
        *) echo "Invalid option, please try again." ; sleep 2 ; menu ;;
    esac
}

# Root Check
if [ "$(id -u)" -ne 0 ]; then
   echo "Error: This script must be run as root!" 
   exit 1
fi

menu
