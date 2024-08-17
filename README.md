# XrayOnAlpine
onekey script to install xray on alpine system
# Xray Installer for Alpine Linux

This repository contains a one-click shell script to install and configure [Xray-core](https://github.com/XTLS/Xray-core) on Alpine Linux. The script automates the process of downloading the latest Xray release, setting it up as a service using OpenRC, and configuring a basic SOCKS proxy.

## Features

- Downloads the latest Xray release from the official GitHub repository
- Installs Xray binaries into `/usr/local/bin/xray`
- Configures Xray with a basic SOCKS proxy setup
- Sets up Xray as an OpenRC service
- Enables the service to start automatically on boot

## Requirements

- Alpine Linux system
- Root access

## Installation

`wget https://raw.githubusercontent.com/miku111/XrayOnAlpine/main/install-release.sh && bash install-release.sh`
or `bash <(curl -L -s [https://raw.githubusercontent.com/miku111/XrayOnAlpine/main/install-release.sh])>`

##Managing the Xray Service
Once installed, you can manage the Xray service using OpenRC commands:

Start the Xray Service:
sudo service xray start

Stop the Xray Service:
sudo service xray stop

Restart the Xray Service:
sudo service xray restart

Check the Status of Xray:
sudo service xray status

##ImportNote

this script just INSTALL Xray on your system, you need CONFIG it manually.the default config file is /usr/local/etc/xray/config.conf.
