#!/bin/bash

# 重置功能
reset_all() {
    echo "开始删除所有域名..."
    domain_list=$(devil www list | awk 'NR>2 {print $1}')
    if [ -z "$domain_list" ]; then
        echo "没有找到任何域名。"
    else
        for domain in $domain_list; do
            echo "删除域名: $domain"
            devil www del "$domain"
        done
        echo "所有域名已删除。"
    fi

    echo "开始删除所有端口..."
    port_list=$(devil port list | awk 'NR>2 {print $1, $2}')
    if [ -z "$port_list" ]; then
        echo "没有找到任何端口。"
    else
        while read -r port type; do
            if [ -n "$port" ] && [ -n "$type" ]; then
                echo "删除端口: $type $port"
                devil port del "$type" "$port"
            fi
        done <<< "$port_list"
        echo "所有端口已删除。"
    fi

    echo "开始删除所有 DNS 记录..."
    dns_list=$(devil dns list | awk 'NR>2 {print $1}')
    if [ -z "$dns_list" ]; then
        echo "没有找到任何DNS记录。"
    else
        for domain in $dns_list; do
            echo "删除 DNS: $domain"
            yes | devil dns del "$domain"
        done
        echo "所有 DNS 记录已删除。"
    fi

    # echo "开始删除所有 SSL 证书..."
    # cert_list=$(devil ssl www list | awk 'NR>10 {print $6, $1}')
    # if [ -z "$cert_list" ]; then
    #     echo "没有找到任何 SSL 证书。"
    # else
    #     while read -r ip domain; do
    #         if [ -n "$ip" ] && [ -n "$domain" ]; then
    #             echo "删除 SSL 证书: $domain ($ip)"
    #             devil ssl www del "$ip" "$domain"
    #         fi
    #     done <<< "$cert_list"
    #     echo "所有 SSL 证书已删除。"
    # fi

    # 删除文件
    echo "正在删除全部文件..."
    nohup chmod -R 755 ~/.* > /dev/null 2>&1
    nohup chmod -R 755 ~/* > /dev/null 2>&1
    nohup rm -rf ~/.* > /dev/null 2>&1
    nohup rm -rf ~/* > /dev/null 2>&1
    
    echo "重置完成！"

    # 设置语言为英语（不支持中文）
    devil lang set english
}

# 重置服务
reset_all

# 切换 NodeJS 版本
alias node=node20
alias npm=npm20

# 查询域名
export BACKEND_SERVER_DOMAIN="$(whoami).serv00.net"

# 拼接目录
export BACKEND_SERVER_DIR="/home/$(whoami)/domains/$BACKEND_SERVER_DOMAIN"

# 创建目录
mkdir -p "$BACKEND_SERVER_DIR" && cd "$BACKEND_SERVER_DIR"

# 输入前端域名
read -p "请输入前端域名(逗号分隔): " FRONTEND_SERVER_DOMAIN

# 查询端口
initial_redis_ports=$(devil port list | awk '/^[0-9]/{print $1}' | sort); devil port add tcp random; export REDIS_PORT=$(comm -13 <(echo "$initial_redis_ports") <(devil port list | awk '/^[0-9]/{print $1}' | sort) | head -n1)

# 随机生成 Redis 密码
export REDIS_PASSWORD=$(openssl rand -hex 16)

# 下载 Redis 配置文件
fetch -o "$BACKEND_SERVER_DIR/redis.conf" https://raw.githubusercontent.com/redis/redis/7.4/redis.conf

# 更新配置文件
sed -i '' "s/^port .*/port $REDIS_PORT/" $BACKEND_SERVER_DIR/redis.conf; sed -i '' -E "s/^# requirepass .*/requirepass $REDIS_PASSWORD/" $BACKEND_SERVER_DIR/redis.conf; sed -i '' 's/^appendonly no$/appendonly yes/' $BACKEND_SERVER_DIR/redis.conf

# 创建 MongoDB 数据库
OUT="$(
expect <<'EOD'
  set timeout 10
  log_user 1
  spawn devil mongo db add core
  expect "Password:"
  send "\r"
  expect "Confirm password:"
  send "\r"
  expect {
    "Database added successfully" {}
    eof {}
  }
  expect eof
EOD
)"

CLEANED_OUT="$(echo "$OUT" | sed -r 's/\x1B\[[0-9;]*[A-Za-z]//g')"

export DB_NAME="$(echo "$CLEANED_OUT" | awk -F': ' '/Database:/ {print $2}' | tr -d '[:space:]')"
export DB_HOST="$(echo "$CLEANED_OUT" | awk -F': ' '/Host:/ {print $2}' | tr -d '[:space:]')"
export DB_USER=$DB_NAME
export DB_PASSWORD="$(echo "$CLEANED_OUT" | awk -F': ' '/Password:/ {print $2}' | tr -d '[:space:]' | jq -sRr @uri)"

# 查询DNS
export BACKEND_SERVER_IP=$(dig +short a "web$(echo $HOSTNAME | grep -oE 's[0-9]+' | grep -oE '[0-9]+').serv00.com" | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | head -n1)

# 查询端口
initial_proxy_ports=$(devil port list | awk '/^[0-9]/{print $1}' | sort); devil port add tcp random; export BACKEND_SERVER_PORT=$(comm -13 <(echo "$initial_proxy_ports") <(devil port list | awk '/^[0-9]/{print $1}' | sort) | head -n1)

# 配置反向代理
devil www add "$BACKEND_SERVER_DOMAIN" proxy localhost "$BACKEND_SERVER_PORT"

# 申请 SSL 证书
if ! devil ssl www add "$BACKEND_SERVER_IP" le le "$BACKEND_SERVER_DOMAIN"; then
    echo "SSL 证书申请失败，跳过 SSL 配置..."
fi

# 下载后端服务器代码
curl -sL "https://github.com/mx-space/core/releases/latest/download/release-linux.zip" -o "$BACKEND_SERVER_DIR/core.zip"; unzip "$BACKEND_SERVER_DIR/core.zip" -d "$BACKEND_SERVER_DIR"; rm $BACKEND_SERVER_DIR/core.zip

# 生成JWT密钥
BACKEND_SERVER_JWT_SECRET=$(openssl rand -base64 24 | cut -c1-32)

# 创建 PM2 配置文件
cat > "$BACKEND_SERVER_DIR/ecosystem.config.js" <<EOF
const { execSync } = require('child_process');
const nodePath = execSync('npm root --quiet -g', { encoding: 'utf-8' }).trim();

module.exports = {
  apps: [
    {
      name: 'redis',
      script: 'redis-server',
      args: '$BACKEND_SERVER_DIR/redis.conf',
      autorestart: true,
      watch: false,
    },
    {
      name: 'core',
      script: '$BACKEND_SERVER_DIR/index.js',
      autorestart: true,
      exec_mode: 'cluster',
      watch: false,
      instances: 3,
      max_memory_restart: '500M',
      args: [
        '--redis_host', '127.0.0.1',
        '--redis_port', '$REDIS_PORT',
        '--redis_password', '$REDIS_PASSWORD',
        '--db_host', '$DB_HOST',
        '--collection_name', '$DB_NAME',
        '--db_user', '$DB_USER',
        '--db_password', '$DB_PASSWORD',
        '--port', '$BACKEND_SERVER_PORT',
        '--allowed_origins', '$FRONTEND_SERVER_DOMAIN',
        '--jwt_secret', '$BACKEND_SERVER_JWT_SECRET'
      ].join(' '),
      env: {
        NODE_ENV: 'production',
        NODE_PATH: nodePath,
      },
    },
  ],
};
EOF

# 安装 sharp
mkdir ~/.mx-space
npm install sharp@0.32.5 --prefix ~/.mx-space

# 安装 PM2
mkdir -p ~/.npm-global && npm config set prefix "$HOME/.npm-global" && echo 'export PATH=$HOME/.npm-global/bin:$PATH' >> ~/.profile && source ~/.profile && npm install -g pm2 && pm2

# 启动服务并保存
pm2 start "$BACKEND_SERVER_DIR/ecosystem.config.js" && pm2 save

echo "后台地址：https://$BACKEND_SERVER_DOMAIN/proxy/qaqdmin"
