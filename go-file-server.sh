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

# 开启服务
devil binexec on && source ~/.profile

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

# 安装 PM2
mkdir -p ~/.npm-global && npm config set prefix "$HOME/.npm-global" && echo 'export PATH=$HOME/.npm-global/bin:$PATH' >> ~/.profile && source ~/.profile && npm install -g pm2 && pm2

# 启动服务并保存
pm2 start "$FILE_SERVER_DIR/ecosystem.config.js" && pm2 save

echo "文件服务器已成功部署在 https://$FILE_SERVER_DOMAIN"
