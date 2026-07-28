#!/usr/bin/env bash

# Alpine Linux Xray/REALITY installer.
# Automatic configuration uses Amazon as the REALITY target.
# The regional/manual branch and Hysteria 2 branch are retained.

XRAY_HOME="/usr/local/bin/xray"
XRAY_BIN="${XRAY_HOME}/xray"
XRAY_CLI_LINK="/usr/local/sbin/xray"
XRAY_CONFIG_DIR="/usr/local/etc/xray"
XRAY_CONFIG="${XRAY_CONFIG_DIR}/config.json"
XRAY_ASSET_DIR="/usr/local/share/xray"
XRAY_LOG_DIR="/var/log/xray"
REALITY_TARGET="www.amazon.com:443"
REALITY_SNI="www.amazon.com"

log(){
    printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"
}

warn(){
    printf '[%s] WARNING: %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >&2
}

die(){
    printf '[%s] ERROR: %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >&2
    exit 1
}

getIP(){
    local serverIP=""

    serverIP=$(curl -4 -fsS --connect-timeout 5 --max-time 10 \
        https://www.cloudflare.com/cdn-cgi/trace 2>/dev/null |
        awk -F= '$1 == "ip" {print $2; exit}' || true)

    if [[ -z "${serverIP}" ]]; then
        serverIP=$(curl -6 -fsS --connect-timeout 5 --max-time 10 \
            https://www.cloudflare.com/cdn-cgi/trace 2>/dev/null |
            awk -F= '$1 == "ip" {print $2; exit}' || true)
    fi

    printf '%s\n' "${serverIP:-SERVER_IP}"
}

formatUriHost(){
    local host=$1
    if [[ "${host}" == *:* && "${host}" != \[*\] ]]; then
        printf '[%s]' "${host}"
    else
        printf '%s' "${host}"
    fi
}

getShortId(){
    od -An -N8 -tx1 /dev/urandom | tr -d ' \n'
}

selectRealityPort(){
    local input=""

    if [[ -n "${XRAY_PORT:-}" ]]; then
        getPort=${XRAY_PORT}
    else
        read -r -t 15 -p "REALITY listen port [443]: " input || true
        getPort=${input:-443}
    fi

    [[ "${getPort}" =~ ^[0-9]+$ ]] || die "Invalid port: ${getPort}"
    (( getPort >= 1 && getPort <= 65535 )) || die "Port must be between 1 and 65535."

    if (( getPort != 443 )); then
        warn "Current Xray releases warn when REALITY listens on a non-443 port."
    fi
}

generateRealityCredentials(){
    local keyOutput

    v2uuid=$(${XRAY_BIN} uuid | tr -d '\r\n')
    keyOutput=$(${XRAY_BIN} x25519)

    rePrivateKey=$(printf '%s\n' "${keyOutput}" |
        awk -F':[[:space:]]*' '$1 == "PrivateKey" {print $2; exit}' |
        tr -d '\r')

    # Compatible with:
    #   Password: <public key>
    #   Password (PublicKey): <public key>
    # Hash32 is intentionally not used as the client public key.
    rePublicKey=$(printf '%s\n' "${keyOutput}" |
        awk -F':[[:space:]]*' '$1 ~ /^Password( \(PublicKey\))?$/ {print $2; exit}' |
        tr -d '\r')

    shortId1=$(getShortId)
    shortId2=$(getShortId)

    [[ -n "${v2uuid}" ]] || die "xray uuid returned an empty value."
    [[ -n "${rePrivateKey}" ]] || die "Could not parse PrivateKey from xray x25519."
    [[ -n "${rePublicKey}" ]] || die "Could not parse Password (PublicKey) from xray x25519."
    [[ "${shortId1}" =~ ^[0-9a-f]{16}$ ]] || die "Failed to generate shortId."
}

installRealityConfig(){
    local tempConfig backupConfig=""
    tempConfig=$(mktemp)

    cat >"${tempConfig}" <<EOF
{
  "log": {
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "tag": "vless-reality-in",
      "port": ${getPort},
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "${v2uuid}",
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
          "target": "${REALITY_TARGET}",
          "xver": 0,
          "serverNames": [
            "${REALITY_SNI}"
          ],
          "privateKey": "${rePrivateKey}",
          "maxTimeDiff": 0,
          "shortIds": [
            "${shortId1}",
            "${shortId2}"
          ],
          "limitFallbackUpload": {
            "afterBytes": 0,
            "bytesPerSec": 262144,
            "burstBytesPerSec": 1048576
          },
          "limitFallbackDownload": {
            "afterBytes": 0,
            "bytesPerSec": 1048576,
            "burstBytesPerSec": 4194304
          }
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

    XRAY_LOCATION_ASSET="${XRAY_ASSET_DIR}" \
        "${XRAY_BIN}" run -test -c "${tempConfig}" >/dev/null || {
            rm -f "${tempConfig}"
            die "Generated Xray configuration did not pass validation."
        }

    mkdir -p "${XRAY_CONFIG_DIR}"
    if [[ -f "${XRAY_CONFIG}" ]]; then
        backupConfig="${XRAY_CONFIG}.bak.$(date '+%Y%m%d%H%M%S')"
        cp -p "${XRAY_CONFIG}" "${backupConfig}"
        log "Previous configuration backed up to ${backupConfig}."
    fi

    install -m 0600 "${tempConfig}" "${XRAY_CONFIG}"
    rm -f "${tempConfig}"

    rc-service xray restart || die "Xray failed to restart."
    sleep 1
    rc-service xray status >/dev/null 2>&1 || die "Xray is not running; check ${XRAY_LOG_DIR}/openrc.err."
}

configReality(){
    generateRealityCredentials
    selectRealityPort

    sniName=${REALITY_SNI}
    serverName=${REALITY_TARGET%:*}
    export sniName serverName

    installRealityConfig
}

# Regional/manual selection is retained. Only key parsing and current target
# field compatibility are updated; the target list itself is unchanged.
configRealityRegion(){
    local userInput index tempConfig
    destNames=("www.t-mobile.com" "www.arm.com" "www.tsukuba.ac.jp" "www.hongkongdisneyland.com" "www.china-airlines.com" "sigtelinc.com" "www.bouyguestelecom.fr" "www.mercedes-benz.de" "www.incredibleindia.gov.in" "www.amazon.com")
    sniNames=("business.t-mobile.com" "learn.arm.com" "www.tsukuba.ac.jp" "entitlement.hongkongdisneyland.com" "book.china-airlines.com" "www.sigtelinc.com" "www.bouygtel.fr" "pro.mercedes-benz.com" "www.incredibleindia.org" "corporate.amazon.com")

    echo "Please select a region:"
    echo "1. US"
    echo "2. UK"
    echo "3. JP"
    echo "4. HK"
    echo "5. TW"
    echo "6. SG"
    echo "7. FR"
    echo "8. DE"
    echo "9. IN"
    echo "10. Others"
    read -r userInput

    if [[ "${userInput}" =~ ^([1-9]|10)$ ]]; then
        index=$((userInput - 1))
        serverName=${destNames[$index]}
        sniName=${sniNames[$index]}
    else
        echo "Invalid selection. Please enter a number between 1 and 10."
        return 1
    fi

    generateRealityCredentials
    selectRealityPort
    tempConfig=$(mktemp)

    cat >"${tempConfig}" <<EOF
{
  "inbounds": [
    {
      "port": ${getPort},
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "${v2uuid}",
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
          "target": "${serverName}:443",
          "xver": 0,
          "serverNames": ["${sniName}"],
          "privateKey": "${rePrivateKey}",
          "maxTimeDiff": 0,
          "shortIds": ["${shortId1}", "${shortId2}"]
        }
      }
    }
  ],
  "outbounds": [
    {"protocol": "freedom", "tag": "direct"},
    {"protocol": "blackhole", "tag": "blocked"}
  ]
}
EOF

    XRAY_LOCATION_ASSET="${XRAY_ASSET_DIR}" \
        "${XRAY_BIN}" run -test -c "${tempConfig}" >/dev/null || {
            rm -f "${tempConfig}"
            die "Generated manual configuration did not pass validation."
        }

    [[ -f "${XRAY_CONFIG}" ]] && cp -p "${XRAY_CONFIG}" "${XRAY_CONFIG}.bak.$(date '+%Y%m%d%H%M%S')"
    install -m 0600 "${tempConfig}" "${XRAY_CONFIG}"
    rm -f "${tempConfig}"
    rc-service xray restart
}

detectXrayAsset(){
    case "$(uname -m)" in
        x86_64|amd64) echo "64" ;;
        aarch64|arm64) echo "arm64-v8a" ;;
        armv7l|armv7) echo "arm32-v7a" ;;
        armv6l|armv6) echo "arm32-v6" ;;
        i386|i486|i586|i686) echo "32" ;;
        riscv64) echo "riscv64" ;;
        *) die "Unsupported architecture: $(uname -m)" ;;
    esac
}

getLatestXrayVersion(){
    local releaseJson effectiveUrl version

    if [[ -n "${XRAY_VERSION:-}" ]]; then
        echo "v${XRAY_VERSION#v}"
        return
    fi

    releaseJson=$(curl -fsSL --connect-timeout 10 --max-time 30 \
        --retry 3 --retry-delay 2 \
        -H 'Accept: application/vnd.github+json' \
        -H 'X-GitHub-Api-Version: 2022-11-28' \
        https://api.github.com/repos/XTLS/Xray-core/releases/latest 2>/dev/null || true)

    version=$(printf '%s\n' "${releaseJson}" |
        sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' |
        head -n 1)

    if [[ -z "${version}" ]]; then
        effectiveUrl=$(curl -fsSL -o /dev/null -w '%{url_effective}' \
            --connect-timeout 10 --max-time 30 \
            https://github.com/XTLS/Xray-core/releases/latest 2>/dev/null || true)
        version=${effectiveUrl##*/}
    fi

    [[ "${version}" == v* ]] || die "Unable to determine the latest Xray release."
    echo "${version}"
}

installXray(){
    local xrayVersion xrayAsset tempDir zipFile digestFile downloadUrl
    local expectedSha actualSha choice

    log "Installing dependencies..."
    apk update
    apk add --no-cache bash ca-certificates curl grep openssl unzip
    update-ca-certificates >/dev/null 2>&1 || true

    xrayVersion=$(getLatestXrayVersion)
    xrayAsset=$(detectXrayAsset)
    tempDir=$(mktemp -d)
    zipFile="${tempDir}/xray.zip"
    digestFile="${tempDir}/xray.zip.dgst"
    downloadUrl="https://github.com/XTLS/Xray-core/releases/download/${xrayVersion}/Xray-linux-${xrayAsset}.zip"

    log "Downloading Xray ${xrayVersion} for $(uname -m)..."
    curl -fL --connect-timeout 10 --max-time 180 \
        --retry 3 --retry-delay 2 \
        -o "${zipFile}" "${downloadUrl}" || {
            rm -rf "${tempDir}"
            die "Failed to download Xray."
        }

    if curl -fL --connect-timeout 10 --max-time 30 \
        --retry 2 --retry-delay 1 \
        -o "${digestFile}" "${downloadUrl}.dgst" 2>/dev/null; then
        expectedSha=$(grep -Ei 'SHA(2-)?-?256' "${digestFile}" |
            awk '{print $NF}' |
            tr -cd '0-9a-fA-F' |
            head -c 64 || true)
        if [[ "${#expectedSha}" -eq 64 ]]; then
            actualSha=$(sha256sum "${zipFile}" | awk '{print $1}')
            [[ "${actualSha,,}" == "${expectedSha,,}" ]] || {
                rm -rf "${tempDir}"
                die "Xray archive SHA-256 verification failed."
            }
            log "Xray archive SHA-256 verified."
        else
            warn "Could not parse SHA-256 from the digest file."
        fi
    else
        warn "Digest file download failed; continuing without checksum verification."
    fi

    mkdir -p "${tempDir}/unpack"
    unzip -q -o "${zipFile}" -d "${tempDir}/unpack" || {
        rm -rf "${tempDir}"
        die "Failed to extract Xray."
    }

    [[ -f "${tempDir}/unpack/xray" ]] || {
        rm -rf "${tempDir}"
        die "Xray binary was not found in the archive."
    }
    chmod 0755 "${tempDir}/unpack/xray"
    "${tempDir}/unpack/xray" version >/dev/null || {
        rm -rf "${tempDir}"
        die "Downloaded Xray binary cannot run on this system."
    }

    rc-service xray stop >/dev/null 2>&1 || true
    mkdir -p "${XRAY_HOME}" "${XRAY_CONFIG_DIR}" "${XRAY_ASSET_DIR}" "${XRAY_LOG_DIR}"
    install -m 0755 "${tempDir}/unpack/xray" "${XRAY_BIN}"
    ln -sfn "${XRAY_BIN}" "${XRAY_CLI_LINK}"
    [[ -f "${tempDir}/unpack/geoip.dat" ]] && install -m 0644 "${tempDir}/unpack/geoip.dat" "${XRAY_ASSET_DIR}/geoip.dat"
    [[ -f "${tempDir}/unpack/geosite.dat" ]] && install -m 0644 "${tempDir}/unpack/geosite.dat" "${XRAY_ASSET_DIR}/geosite.dat"
    rm -rf "${tempDir}"

    cat > /etc/init.d/xray <<'EOF'
#!/sbin/openrc-run

name="Xray"
description="Xray Proxy Service"
supervisor=supervise-daemon
respawn_delay=5
respawn_max=3
respawn_period=60

command="/usr/local/bin/xray/xray"
command_args="run -c /usr/local/etc/xray/config.json"
pidfile="/run/${RC_SVCNAME}.pid"
output_log="/var/log/xray/openrc.log"
error_log="/var/log/xray/openrc.err"
env=${env:-"XRAY_LOCATION_ASSET=/usr/local/share/xray"}
extra_commands="checkconfig"

depend() {
    need net
    after firewall
}

checkconfig() {
    "$command" run -test -c /usr/local/etc/xray/config.json
}

start_pre() {
    checkpath -d -m 0755 -o root:root /var/log/xray
    checkpath -f -m 0644 -o root:root "$output_log" "$error_log"
    checkconfig
}
EOF

    chmod 0755 /etc/init.d/xray
    rc-update add xray default >/dev/null 2>&1 || true

    log "Installed: $(${XRAY_BIN} version | head -n 1)"
    echo "Please select a configuration method:"
    echo "1) Auto Config (Amazon target)"
    echo "2) Manual/Regional Config"
    echo "3) Exit"

    while true; do
        read -r -p "Enter your choice (1-3): " choice
        case "${choice}" in
            1) configReality; break ;;
            2) configRealityRegion; break ;;
            3) echo "Exiting..."; exit 0 ;;
            *) echo "Invalid input. Please enter 1, 2, or 3." ;;
        esac
    done

    clear
    client_re
}

client_re(){
    local serverIP uriHost uri resultFile
    serverIP=$(getIP)
    uriHost=$(formatUriHost "${serverIP}")
    uri="vless://${v2uuid}@${uriHost}:${getPort}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${sniName}&fp=chrome&pbk=${rePublicKey}&sid=${shortId1}&type=tcp#xrayReality"
    resultFile="/root/xray-reality.txt"

    cat >"${resultFile}" <<EOF
Address: ${serverIP}
Port: ${getPort}
UUID: ${v2uuid}
Flow: xtls-rprx-vision
Transport: tcp
Security: reality
Target: ${serverName}:443
SNI: ${sniName}
Public key: ${rePublicKey}
Short ID: ${shortId1}

${uri}
EOF
    chmod 0600 "${resultFile}"

    echo
    echo "安装已经完成"
    echo
    echo "===========reality配置参数============"
    echo "代理模式：vless"
    echo "地址：${serverIP}"
    echo "端口：${getPort}"
    echo "UUID：${v2uuid}"
    echo "流控：xtls-rprx-vision"
    echo "传输协议：tcp"
    echo "Public key：${rePublicKey}"
    echo "底层传输：reality"
    echo "Target: ${serverName}:443"
    echo "SNI: ${sniName}"
    echo "shortIds: ${shortId1}"
    echo "===================================="
    echo "${uri}"
    echo
    echo "配置已保存到 ${resultFile}"
}

installHy2(){
  #!/bin/bash

# Exit on any error
set -e

# Function to log messages
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

# Ensure script runs as root
if [[ $EUID -ne 0 ]]; then
    log "Error: This script must be run as root!"
    exit 1
fi


# Install required packages
log "Installing required packages..."
apk add --no-cache bash curl wget openssl coreutils grep

# Generate a strong random password (32 characters)
hyPasswd=$(openssl rand -base64 24)

# Select a random port (avoid common ports)
getPort=$(shuf -i 10000-65000 -n 1)

# Get the latest Hysteria 2 version
log "Detecting latest Hysteria 2 version..."
HY2_VERSION=$(curl -s https://api.github.com/repos/apernet/hysteria/releases/latest | grep -oP '"tag_name": "\K(.*?)(?=")')
if [[ -z "$HY2_VERSION" ]]; then
    log "Error: Could not detect latest version"
    exit 1
fi

HY2_VERSION_ESCAPED=$(echo "$HY2_VERSION" | sed 's/\//%2F/g')

# Determine system architecture
ARCH=$(uname -m)
case $ARCH in
    x86_64)  HY2_ARCH="amd64" ;;
    aarch64) HY2_ARCH="arm64" ;;
    armv7l)  HY2_ARCH="armv7" ;;
    *)
        log "Error: Unsupported architecture: $ARCH"
        exit 1
        ;;
esac

# Download and install Hysteria 2
log "Downloading Hysteria 2 version $HY2_VERSION..."
DOWNLOAD_URL="https://github.com/apernet/hysteria/releases/download/$HY2_VERSION_ESCAPED/hysteria-linux-$HY2_ARCH"
if ! wget -qO /usr/local/bin/hysteria "$DOWNLOAD_URL"; then
    log "Error: Failed to download Hysteria 2"
    exit 1
fi
chmod +x /usr/local/bin/hysteria

# Create configuration directory
mkdir -p /etc/hysteria/

# Generate self-signed TLS certificate
log "Generating TLS certificate..."
openssl req -x509 -nodes -newkey ec:<(openssl ecparam -name prime256v1) \
    -keyout /etc/hysteria/server.key -out /etc/hysteria/server.crt \
    -subj "/CN=bing.com" -days 36500

# Secure certificate files
chown root:root /etc/hysteria/server.key /etc/hysteria/server.crt
chmod 600 /etc/hysteria/server.key /etc/hysteria/server.crt

# Create server configuration
log "Creating server configuration..."
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

# Create OpenRC service
log "Creating OpenRC service..."
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

start_pre() {
    if [ ! -f /etc/hysteria/config.yaml ]; then
        eerror "Configuration file not found: /etc/hysteria/config.yaml"
        return 1
    fi
    checkpath -f -m 0644 -o root:root "\$output_log" "\$error_log"
}
EOF

chmod +x /etc/init.d/hysteria
rc-update add hysteria default

# Get server IP
serverIP=$(getIP)

# Configure firewall (if installed)
if command -v ufw >/dev/null 2>&1; then
    log "Configuring UFW firewall..."
    ufw allow "$getPort"/udp
fi

# Start the service
log "Starting Hysteria service..."
rc-service hysteria restart

# Display connection information
echo "==============================================="
echo "Hysteria 2 Installation Complete!"
echo "Connection String:"
echo "hysteria2://${hyPasswd}@${serverIP}:${getPort}/?insecure=1&sni=bing.com#Hysteria2-$(date +%Y%m%d)"
echo "==============================================="
echo "Config file location: /etc/hysteria/config.yaml"
echo "Log files: /var/log/hysteria.log and /var/log/hysteria.err"

}

menu(){
    echo "0. Exit"
    echo "1. install Xray and Config Reality"
    echo "2. install hystria2"
    read option
    if [[ "$option" -eq 0 ]]; then
        exit 0
    elif [[ "$option" -eq 1 ]]; then
        installXray
    elif [[ "$option" -eq 2 ]]; then
        installHy2
    else
        echo "invid option"
        menu
    fi
}
# Ensure this script is run as root
if [ "$(id -u)" -ne 0 ]; then
   echo "This script must be run as root!" 
   exit 1
fi
menu #special thanks to administrator of 1024.day
