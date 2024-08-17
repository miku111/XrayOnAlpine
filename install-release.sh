#!/bin/sh
# Xray Installer Script for Alpine Linux
# Ensure this script is run as root
if [ "$(id -u)" -ne 0 ]; then
   echo "This script must be run as root!" 
   exit 1
fi

# Step 1: Update Alpine system
apk update && apk upgrade

# Step 2: Install required dependencies
apk add curl bash unzip grep

# Step 3: Download and install Xray
XRAY_VERSION=$(curl -s https://api.github.com/repos/XTLS/Xray-core/releases/latest | grep -Po '"tag_name": "\K.*?(?=")')
curl -L -o /tmp/xray.zip https://github.com/XTLS/Xray-core/releases/download/${XRAY_VERSION}/Xray-linux-64.zip

# Create directories
mkdir -p /usr/local/bin/xray
mkdir -p /usr/local/etc/xray

# Unzip the Xray package
unzip /tmp/xray.zip -d /usr/local/bin/xray

# Make Xray binary executable
chmod +x /usr/local/bin/xray/xray

# Step 4: Create the Xray configuration file
cat <<EOF > /usr/local/etc/xray/config.json
{
  "inbounds": [{
    "port": 1080,
    "protocol": "socks",
    "settings": {
      "auth": "noauth",
      "udp": true,
      "ip": "127.0.0.1"
    }
  }],
  "outbounds": [{
    "protocol": "freedom",
    "settings": {}
  }]
}
EOF

# Step 5: Create OpenRC init script for Xray
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

# Make the init script executable
chmod +x /etc/init.d/xray

# Step 6: Enable and start the Xray service
rc-update add xray default
service xray start

# Step 7: Clean up temporary files
rm -f /tmp/xray.zip

# Step 8: Show status of Xray service
service xray status

echo "Xray installation and setup complete!"
