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

# 查询域名
export PRIVATEBIN_DOMAIN="$(whoami).serv00.net"

# 拼接目录
export PRIVATEBIN_DIR="/home/$(whoami)/domains/$PRIVATEBIN_DOMAIN"

# 创建目录
mkdir -p "$PRIVATEBIN_DIR"

# 查询DNS
export PRIVATEBIN_IP=$(dig +short a "web$(echo $HOSTNAME | grep -oE 's[0-9]+' | grep -oE '[0-9]+').serv00.com" | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | head -n1)

# 查询端口
initial_proxy_ports=$(devil port list | awk '/^[0-9]/{print $1}' | sort); devil port add tcp random; export PRIVATEBIN_PORT=$(comm -13 <(echo "$initial_proxy_ports") <(devil port list | awk '/^[0-9]/{print $1}' | sort) | head -n1)

# 配置反向代理
devil www add "$PRIVATEBIN_DOMAIN" proxy localhost "$PRIVATEBIN_PORT"

# 申请 SSL 证书
if ! devil ssl www add "$PRIVATEBIN_IP" le le "$PRIVATEBIN_DOMAIN"; then
    echo "SSL 证书申请失败，跳过 SSL 配置..."
fi

# 创建 PostgreSQL 数据库
OUT="$(
expect <<'EOD'
  set timeout 10
  log_user 1
  spawn devil pgsql db add bin
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

# 克隆仓库
rm -rf "$PRIVATEBIN_DIR/public_html" && git clone https://github.com/PrivateBin/PrivateBin "$PRIVATEBIN_DIR/public_html"

# 修改配置
cp "$PRIVATEBIN_DIR/public_html/cfg/conf.sample.php" "$PRIVATEBIN_DIR/public_html/cfg/conf.php"

sed -i '' -e 's/opendiscussion = false/opendiscussion = true/' \
           -e 's/; discussiondatedisplay = false/discussiondatedisplay = true/' \
           -e 's/fileupload = false/fileupload = true/' \
           -e 's/burnafterreadingselected = false/burnafterreadingselected = true/' \
           -e 's/\[model\]/;[model]/' \
           -e 's/^;*\[model\]/;[model]/' \
           -e 's/class = Filesystem/;class = Filesystem/' \
           -e 's/\[model_options\]/;[model_options]/' \
           -e 's/^;*\[model_options\]/;[model_options]/' \
           -e 's/dir = PATH "data"/;dir = PATH "data"/' \
           -e '$ a\
[model]\
class = Database\
[model_options]\
dsn = "pgsql:host=\$DB_HOST;dbname=\$DB_NAME"\
tbl = "privatebin_"     ; table prefix\
usr = "\$DB_USER"\
pwd = "\$DB_PASSWORD"\
opt[12] = true    ; PDO::ATTR_PERSISTENT' "$PRIVATEBIN_DIR/public_html/cfg/conf.php"

echo "PrivateBin服务已部署在：https://$PRIVATEBIN_DOMAIN"
