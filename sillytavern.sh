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

# 切换nodejs版本
alias node=node20
alias npm=npm20

# 查询域名
export Silly_Tavern_DOMAIN="$(whoami).serv00.net"

# 查询DNS
export Silly_Tavern_IP=$(dig +short a "web$(echo $HOSTNAME | grep -oE 's[0-9]+' | grep -oE '[0-9]+').serv00.com" | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | head -n1)

# 添加端口
initial_ports=$(devil port list | awk '/^[0-9]/{print $1}' | sort); devil port add tcp random; export Silly_Tavern_PORT=$(comm -13 <(echo "$initial_ports") <(devil port list | awk '/^[0-9]/{print $1}' | sort) | head -n1)

# 配置反向代理
devil www add "$Silly_Tavern_DOMAIN" proxy localhost "$Silly_Tavern_PORT"

# 申请 SSL 证书
if ! devil ssl www add "$Silly_Tavern_IP" le le "$Silly_Tavern_DOMAIN"; then
    echo "SSL 证书申请失败，跳过 SSL 配置..."
fi

# 自动拼接文件服务器目录
Silly_Tavern_DIR="/home/$(whoami)/domains/$Silly_Tavern_DOMAIN/"

# 创建目录（如果不存在）
mkdir -p "$Silly_Tavern_DIR" && cd "$Silly_Tavern_DIR"

# 克隆仓库
git clone https://github.com/SillyTavern/SillyTavern -b release && cd $_

# 赋权
chmod +x start.sh

# 输入用户名
read -p "请输入用户名: " Silly_Tavern_USERNAME

# 输入密码
read -p "请输入密码: " Silly_Tavern_PASSWORD

# 修改配置文件
sed -i '' 's/listen: false/listen: true/; s/port: .*/port: '"$Silly_Tavern_PORT"'/; s/whitelistMode: true/whitelistMode: false/; s/basicAuthMode: false/basicAuthMode: true/; s/username: .*/username: '"$Silly_Tavern_USERNAME"'/; s/password: .*/password: '"$Silly_Tavern_PASSWORD"'/' config.yaml

# 创建 PM2 配置文件
cat > "$Silly_Tavern_DIR/ecosystem.config.js" <<EOF
module.exports = {
  apps: [
    {
      name: 'sillytavern',
      script: './start.sh',
      cwd: '$Silly_Tavern_DIR/SillyTavern',
      interpreter: 'bash'
    }
  ]
};
EOF

# 安装 PM2
mkdir -p ~/.npm-global && npm config set prefix "$HOME/.npm-global" && echo 'export PATH=$HOME/.npm-global/bin:$PATH' >> ~/.profile && source ~/.profile && npm install -g pm2 && pm2

# 启动服务并保存
pm2 start "$Silly_Tavern_DIR/ecosystem.config.js" && pm2 save

echo "Silly Tavern已成功部署在 https://$Silly_Tavern_DOMAIN"
