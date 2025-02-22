#!/bin/bash
set -e

# 版本信息
VERSION="1.0.0"
GITHUB_REPO="https://raw.githubusercontent.com/QAbot-zh/go-file-server/main"

# 打印欢迎信息
echo "文件服务部署脚本 v$VERSION"
echo "----------------------------------------"

# 用户输入文件服务器域名
read -p "请输入文件服务域名（示例：file.domain.com）: " FILE_SERVER_DOMAIN
export FILE_SERVER_DOMAIN

# 验证输入非空
if [ -z "$FILE_SERVER_DOMAIN" ]; then
  echo "错误：域名不能为空！"
  exit 1
fi

# 收集accessCodes
echo ""
echo "请至少输入一个访问码"
echo "----------------------------------------"

CODES=()
for ((i=1; ;i++)); do
  hint_msg="请输入第$i个访问码"
  [ $i -eq 1 ] && hint_msg+="（必须输入）" || hint_msg+="（直接回车完成）"
  
  read -p "$hint_msg: " code
  
  # 首次输入验证
  if [ $i -eq 1 ] && [ -z "$code" ]; then
    echo "错误：至少输入一个访问码！"
    exit 1
  fi
  
  # 非首次输入可退出
  [ $i -ne 1 ] && [ -z "$code" ] && break
  
  CODES+=("$code")
done

# 创建域名目录
DOMAIN_DIR="$HOME/domains/$FILE_SERVER_DOMAIN"
mkdir -p "$DOMAIN_DIR/files"  # 同时创建文件存储目录

# 生成配置文件
printf "accessCodes=%s\n" "$(IFS=,; echo "${CODES[*]}")" > "$DOMAIN_DIR/env.conf"

# 自动获取可用端口（20000-40000）
echo ""
echo "正在申请端口..."
for port in {20000..40000}; do
  if devil port add tcp "$port" &>/dev/null; then
    echo "√ 成功分配端口：$port"
    PORT=$port
    break
  fi
done

if [ -z "$PORT" ]; then
  echo "错误：在20000-40000范围内找不到可用端口"
  exit 1
fi

# 域名相关配置
echo ""
echo "正在配置域名..."
devil www add "$FILE_SERVER_DOMAIN" proxy localhost "$PORT"
devil dns add "$FILE_SERVER_DOMAIN"
IP=$(devil dns list "$FILE_SERVER_DOMAIN" | grep -v '^#' | awk -F '[[:space:]]+' '$3 == "A" {print $7}')
devil ssl www add "$IP" le le "$FILE_SERVER_DOMAIN"

# 从GitHub获取Go程序
echo ""
echo "正在下载服务程序..."
curl -sL "$GITHUB_REPO/main.go" -o "$DOMAIN_DIR/main.go"

# 注入动态端口
sed -i "s/:12345/:$PORT/g" "$DOMAIN_DIR/main.go"

# 安装PM2
echo ""
echo "正在安装进程管理工具..."
bash <(curl -s https://raw.githubusercontent.com/k0baya/alist_repl/main/serv00/install-pm2.sh)

# 动态生成PM2配置
PM2_CONFIG=~/domains/ecosystem.config.js
APP_CONFIG="    {
      name: \"go-file-server\",
      script: \"go\",
      args: \"run main.go\",
      cwd: \"$DOMAIN_DIR\",
      log_date_format: \"YYYY-MM-DD HH:mm:ss\"
    }"

if [ -f "$PM2_CONFIG" ]; then
  # 备份配置文件
  cp "$PM2_CONFIG" "$PM2_CONFIG.bak"
  
  # 智能追加配置
  if grep -q 'name: "go-file-server"' "$PM2_CONFIG"; then
    echo "检测到已存在的go-file-server配置，跳过添加"
  else
    # 使用awk智能插入配置
    awk -v config="$APP_CONFIG" '
      BEGIN { in_apps = 0; inserted = 0 }
      /apps: \[/ { in_apps = 1 }
      in_apps && /\]/ {
        if (!inserted) {
          sub(/\]/, config "\n  ]")
          inserted = 1
        }
      }
      { print }
      END {
        if (!inserted) {
          print "module.exports = {"
          print "  apps: ["
          print config
          print "  ]"
          print "};"
        }
      }
    ' "$PM2_CONFIG.bak" > "$PM2_CONFIG"
    
    # 自动修复逗号格式
    sed -i '/},/{N; /},\n  ]/!s/}\n  ]/},\n  ]/}' "$PM2_CONFIG"
  fi
else
  # 创建全新配置
  cat > "$PM2_CONFIG" <<EOF
module.exports = {
  apps: [
$APP_CONFIG
  ]
};
EOF
fi

# 启动服务
echo ""
echo "正在启动服务..."
pm2 start "$PM2_CONFIG" && pm2 save

# 打印部署结果
echo ""
echo "✅ 部署完成！"
echo "========================================"
echo "访问地址：https://$FILE_SERVER_DOMAIN"
echo "访问码列表：${CODES[*]}"
echo "文件存储路径：$DOMAIN_DIR/files"
echo "========================================"
echo "管理命令："
echo "查看状态  : pm2 status go-file-server"
echo "查看日志  : pm2 logs go-file-server"
echo "重启服务  : pm2 restart go-file-server"
echo "========================================"
