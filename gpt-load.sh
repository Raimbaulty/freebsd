#!/bin/bash

REPO="tbphp/gpt-load"
OUTFILE="gpt-load"

# 彩色输出函数
green()  { echo -e "\033[32m$1\033[0m"; }
yellow() { echo -e "\033[33m$1\033[0m"; }
red()    { echo -e "\033[31m$1\033[0m"; }
blue()   { echo -e "\033[36m$1\033[0m"; }

# 检测系统和架构
OS=$(uname | tr '[:upper:]' '[:lower:]')
ARCH=$(uname -m)

case "$ARCH" in
    x86_64|amd64) ARCH="amd64" ;;
    aarch64|arm64) ARCH="arm64" ;;
    *) red "✗ 不支持的架构: $ARCH"; exit 1 ;;
esac

case "$OS" in
    linux)   PATTERN="gpt-load-linux-$ARCH" ;;
    darwin)  PATTERN="gpt-load-macos-$ARCH" ;;
    msys*|mingw*|cygwin*|windowsnt) PATTERN="gpt-load-windows-$ARCH.exe"; OUTFILE="gpt-load.exe" ;;
    *) red "✗ 不支持的系统: $OS"; exit 1 ;;
esac

blue "➤ 系统: $OS"
blue "➤ 架构: $ARCH"
blue "➤ 目标文件: $OUTFILE"

# 检查并删除同名文件
if [ -f "$OUTFILE" ]; then
    yellow "⚠️  已检测到旧文件，正在删除: $OUTFILE"
    rm -f "$OUTFILE"
fi

# 获取下载链接
RELEASE_JSON=$(curl -s "https://api.github.com/repos/$REPO/releases/latest")
DOWNLOAD_URL=$(echo "$RELEASE_JSON" | jq -r --arg pattern "$PATTERN" '.assets[] | select(.name==$pattern) | .browser_download_url')

if [[ -z "$DOWNLOAD_URL" ]]; then
    red "✗ 未找到匹配的文件！"
    exit 2
fi

green "↓ 开始静默下载..."

wget -q "$DOWNLOAD_URL" -O "$OUTFILE"
if [[ $? -ne 0 ]]; then
    red "✗ 下载失败！"
    exit 3
fi

if [[ "$OUTFILE" != *.exe ]]; then
    chmod +x "$OUTFILE"
    green "✔ 已赋予执行权限: $OUTFILE"
fi

green "✔ 下载完成: $OUTFILE"
