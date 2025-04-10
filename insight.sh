#!/bin/bash

# 重置所有功能
reset_all() {
    # 删除所有域名
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

    # 删除所有端口
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

    # 删除所有 DNS 记录
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

    # 删除所有 SSL 证书（注释部分保留）
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
    
    # 删除数据库
    delete_databases() {
        local db_type="$1"  # 数据库类型，如 pgsql, mongo, mysql
        echo "开始删除所有 $db_type 数据库..."
        local db_list=$(devil "$db_type" list | awk 'NR>3 {print $1}')
        if [ -z "$db_list" ]; then
            echo "没有找到任何 $db_type 数据库。"
        else
            while read -r db_name; do
                if [ -n "$db_name" ]; then
                    echo "删除 $db_type 数据库: $db_name"
                    devil "$db_type" db del "$db_name"
                fi
            done <<< "$db_list"
            echo "所有 $db_type 数据库已删除。"
        fi
    }

    delete_databases "pgsql"
    delete_databases "mongo"
    delete_databases "mysql"

    echo "重置完成！"

    # 设置语言为英语（不支持中文）
    devil lang set english
}

# 调用重置功能
reset_all

# 输入配置信息
read -p "请输入Telegram机器人Token: " TELEGRAM_BOT_TOKEN
read -p "请输入OpenAI配置信息，格式：https://api.openai.com,sk-123,gpt-4o-mini: " OPENAI_INFO

# 赋值给变量
IFS=',' read -r OPENAI_API_BASE_URL OPENAI_API_KEY OPENAI_API_MODEL <<< "$OPENAI_INFO"
OPENAI_API_BASE_URL=$OPENAI_API_BASE_URL
OPENAI_API_KEY=$OPENAI_API_KEY
OPENAI_API_MODEL=$OPENAI_API_MODEL

# 拼接目录
export INSIGHTS_BOT_DIR="/home/$(whoami)/domains/insights-bot"

# 创建PostgreSQL数据库
OUT="$(
expect <<'EOD'
  set timeout 10
  log_user 1
  spawn devil pgsql db add insbot
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

DB_NAME="$(echo "$CLEANED_OUT" | awk -F': ' '/Database:/ {print $2}' | tr -d '[:space:]')"
DB_HOST="$(echo "$CLEANED_OUT" | awk -F': ' '/Host:/ {print $2}' | tr -d '[:space:]')"
DB_PASSWORD="$(echo "$CLEANED_OUT" | awk -F': ' '/Password:/ {print $2}' | tr -d '[:space:]' | jq -sRr @uri)"
export DB_CONNECTION_STR="postgresql://$DB_NAME:$DB_PASSWORD@$DB_HOST:5432/$DB_NAME?search_path=public&sslmode=disable"

# 查询端口
initial_ports=$(devil port list | awk '/^[0-9]/{print $1}' | sort); devil port add tcp random; export REDIS_PORT=$(comm -13 <(echo "$initial_ports") <(devil port list | awk '/^[0-9]/{print $1}' | sort) | head -n1)
initial_ports=$(devil port list | awk '/^[0-9]/{print $1}' | sort); devil port add tcp random; export HEALTH_PORT=$(comm -13 <(echo "$initial_ports") <(devil port list | awk '/^[0-9]/{print $1}' | sort) | head -n1)

# 克隆仓库代码
git clone https://github.com/nekomeowww/insights-bot.git $INSIGHTS_BOT_DIR && cd $_

# 更新health文件
sed -i '' "s/Addr:              \":7069\"/Addr:              \":$HEALTH_PORT\"/g" $INSIGHTS_BOT_DIR/internal/services/health/health.go

# 打包文件
go build -a -o "insights-bot" "github.com/nekomeowww/insights-bot/cmd/insights-bot"

# 下载 Redis 配置文件
fetch -o "$INSIGHTS_BOT_DIR/redis.conf" https://raw.githubusercontent.com/redis/redis/7.4/redis.conf

# 随机生成 Redis 密码
export REDIS_PASSWORD=$(openssl rand -hex 16)

# 更新Redis配置文件
sed -i '' "s/^port .*/port $REDIS_PORT/" $INSIGHTS_BOT_DIR/redis.conf; sed -i '' -E "s/^# requirepass .*/requirepass $REDIS_PASSWORD/" $INSIGHTS_BOT_DIR/redis.conf; sed -i '' 's/^appendonly no$/appendonly yes/' $INSIGHTS_BOT_DIR/redis.conf

# 赋权
chmod +x  $INSIGHTS_BOT_DIR/insights-bot

# 配置环境变量
cat > "$INSIGHTS_BOT_DIR/.env" <<EOF
DB_CONNECTION_STR="$DB_CONNECTION_STR"
TELEGRAM_BOT_TOKEN=$TELEGRAM_BOT_TOKEN
OPENAI_API_HOST=$OPENAI_API_BASE_URL
OPENAI_API_SECRET=$OPENAI_API_KEY
OPENAI_API_MODEL_NAME=$OPENAI_API_MODEL
REDIS_HOST=localhost
REDIS_PORT=$REDIS_PORT
REDIS_PASSWORD=$REDIS_PASSWORD
LOCALES_DIR=$INSIGHTS_BOT_DIR/locales
EOF

# 创建 PM2 配置文件
cat > "$INSIGHTS_BOT_DIR/ecosystem.config.js" <<EOF
module.exports = {
  apps: [
    {
      name: 'redis',
      script: 'redis-server',
      args: '$INSIGHTS_BOT_DIR/redis.conf',
      autorestart: true,
      watch: false,
    },
    {
      name: 'insights-bot',
      script: '$INSIGHTS_BOT_DIR/insights-bot',
      autorestart: true,
      watch: false,
      cwd: '$INSIGHTS_BOT_DIR'
    }
  ],
};
EOF

# 安装 PM2
mkdir -p ~/.npm-global && npm config set prefix "$HOME/.npm-global" && echo 'export PATH=$HOME/.npm-global/bin:$PATH' >> ~/.profile && source ~/.profile && npm install -g pm2 && pm2

# 启动服务并保存
pm2 start "$INSIGHTS_BOT_DIR/ecosystem.config.js" && pm2 save

echo "insight-bot 已启动，请前往 Telegram 使用"
