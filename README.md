[English](README_EN.md) | 中文

# Xray 安装脚本（适用于 Alpine Linux）

本仓库提供了一键安装和配置 Xray-core 的 shell 脚本，专为 Alpine Linux 系统设计。该脚本自动完成下载最新的 Xray 版本，设置为 OpenRC 服务，并配置一个基础的 SOCKS 代理。

## 功能
- 从官方 GitHub 仓库下载最新的 Xray 版本
- 将 Xray 二进制文件安装到 `/usr/local/bin/xray`
- 配置 Xray 以支持基本的 SOCKS 代理
- 将 Xray 设置为 OpenRC 服务
- 启用服务开机自动启动

## 系统要求
- Alpine Linux 系统
- Root 权限

## 安装方法
使用以下命令安装：

```sh
wget https://raw.githubusercontent.com/miku111/XrayOnAlpine/main/install-release.sh && bash install-release.sh
```

或者

```sh
curl -L -s https://raw.githubusercontent.com/miku111/XrayOnAlpine/main/install-release.sh | bash
```

## 管理 Xray 服务
安装完成后，可以使用 OpenRC 命令来管理 Xray 服务：

### 启动 Xray 服务：
```sh
sudo service xray start
```

### 停止 Xray 服务：
```sh
sudo service xray stop
```

### 重启 Xray 服务：
```sh
sudo service xray restart
```

### 查看 Xray 服务状态：
```sh
sudo service xray status
```
