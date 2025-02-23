#!/bin/bash

# 获取用户输入
read -p "请输入访问码（多个用逗号分隔）: " FILE_SERVER_CODE

# 查询域名
export FILE_SERVER_DOMAIN="$(whoami).serv00.net"

# 查询DNS
export FILE_SERVER_IP=$(dig +short a "web$(echo $HOSTNAME | grep -oE 's[0-9]+' | grep -oE '[0-9]+').serv00.com" | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | head -n1)

# 添加端口
initial_ports=$(devil port list | awk '/^[0-9]/{print $1}' | sort); devil port add tcp random; export FILE_SERVER_PORT=$(comm -13 <(echo "$initial_ports") <(devil port list | awk '/^[0-9]/{print $1}' | sort) | head -n1)

# 配置反向代理
devil www add "$FILE_SERVER_DOMAIN" proxy localhost "$FILE_SERVER_PORT"

# 申请 SSL 证书
if ! devil ssl www add "$FILE_SERVER_IP" le le "$FILE_SERVER_DOMAIN"; then
    echo "SSL 证书申请失败，跳过 SSL 配置..."
fi

# 自动拼接文件服务器目录
FILE_SERVER_DIR="/home/$(whoami)/domains/$FILE_SERVER_DOMAIN/"

# 创建目录（如果不存在）
mkdir -p "$FILE_SERVER_DIR"

# 下载 Go 文件服务器代码
curl -sL "https://raw.githubusercontent.com/QAbot-zh/go-file-server/main/main.go" -o "$FILE_SERVER_DIR/main.go"

# 修改端口号
sed -i '' "s|:3456|:$FILE_SERVER_PORT|g" "$FILE_SERVER_DIR/main.go"

# 创建环境配置文件
cat > "$FILE_SERVER_DIR/env.conf" <<EOF
accessCodes=${FILE_SERVER_CODE}
EOF

# 创建 PM2 配置文件
cat > "$FILE_SERVER_DIR/ecosystem.config.js" <<EOF
module.exports = {
  apps: [
    {
      name: "go-file-server",
      script: "go",
      args: "run main.go",
      cwd: "$FILE_SERVER_DIR"
    }
  ]
};
EOF

# 启动服务并保存
pm2 start "$FILE_SERVER_DIR/ecosystem.config.js" && pm2 save

echo "文件服务器已成功部署在$FILE_SERVER_DOMAIN！"
