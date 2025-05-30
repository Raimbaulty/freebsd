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

# 查询域名
export PRIVATEBIN_DOMAIN="$(whoami).serv00.net"

# 拼接目录
export PRIVATEBIN_DIR="/home/$(whoami)/domains/$PRIVATEBIN_DOMAIN"

# 创建目录
mkdir -p "$PRIVATEBIN_DIR"

# 查询DNS
export PRIVATEBIN_IP=$(dig +short a "web$(echo $HOSTNAME | grep -oE 's[0-9]+' | grep -oE '[0-9]+').serv00.com" | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | head -n1)

# 配置站点
devil www add "$PRIVATEBIN_DOMAIN"

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
export DB_PASSWORD="$(echo "$CLEANED_OUT" | awk -F': ' '/Password:/ {print $2}' | tr -d '[:space:]')"

# 克隆仓库
rm -rf "$PRIVATEBIN_DIR/public_html" && git clone https://github.com/PrivateBin/PrivateBin "$PRIVATEBIN_DIR/public_html"

# 修改配置
cat > "$PRIVATEBIN_DIR/public_html/cfg/conf.php" <<EOF
;<?php http_response_code(403); /*
; config file for PrivateBin
;
; An explanation of each setting can be find online at https://github.com/PrivateBin/PrivateBin/wiki/Configuration.

[main]
; (optional) set a project name to be displayed on the website
; name = "PrivateBin"

; The full URL, with the domain name and directories that point to the
; PrivateBin files, including an ending slash (/). This URL is essential to
; allow Opengraph images to be displayed on social networks.
; basepath = "https://privatebin.example.com/"

; enable or disable the discussion feature, defaults to true
discussion = true

; preselect the discussion feature, defaults to false
opendiscussion = true

; enable or disable the display of dates & times in the comments, defaults to true
; Note that internally the creation time will still get tracked in order to sort
; the comments by creation time, but you can choose not to display them.
discussiondatedisplay = true

; enable or disable the password feature, defaults to true
password = true

; enable or disable the file upload feature, defaults to false
fileupload = true

; preselect the burn-after-reading feature, defaults to false
burnafterreadingselected = true

; which display mode to preselect by default, defaults to "plaintext"
; make sure the value exists in [formatter_options]
defaultformatter = "plaintext"

; (optional) set a syntax highlighting theme, as found in css/prettify/
; syntaxhighlightingtheme = "sons-of-obsidian"

; size limit per paste or comment in bytes, defaults to 10 Mebibytes
sizelimit = 10485760

; by default PrivateBin use "bootstrap" template (tpl/bootstrap.php).
; Optionally you can enable the template selection menu, which uses
; a session cookie to store the choice until the browser is closed.
templateselection = false

; List of available for selection templates when "templateselection" option is enabled
availabletemplates[] = "bootstrap"
availabletemplates[] = "bootstrap-page"
availabletemplates[] = "bootstrap-dark"
availabletemplates[] = "bootstrap-dark-page"
availabletemplates[] = "bootstrap-compact"
availabletemplates[] = "bootstrap-compact-page"
availabletemplates[] = "bootstrap5"
availabletemplates[] = "page"

; set the template your installs defaults to, defaults to "bootstrap" (tpl/bootstrap.php), also
; available are "page" (tpl/page.php), the classic ZeroBin style and several
; bootstrap variants: "bootstrap-dark", "bootstrap-compact", "bootstrap-page",
; which can be combined with "-dark" and "-compact" for "bootstrap-dark-page",
; "bootstrap-compact-page" and finally "bootstrap5" (tpl/bootstrap5.php) - previews at:
; https://privatebin.info/screenshots.html
; template = "bootstrap"

; (optional) info text to display
; use single, instead of double quotes for HTML attributes
;info = "More information on the <a href='https://privatebin.info/'>project page</a>."

; (optional) notice to display
; notice = "Note: This is a test service: Data may be deleted anytime. Kittens will die if you abuse this service."

; by default PrivateBin will guess the visitors language based on the browsers
; settings. Optionally you can enable the language selection menu, which uses
; a session cookie to store the choice until the browser is closed.
languageselection = false

; set the language your installs defaults to, defaults to English
; if this is set and language selection is disabled, this will be the only language
; languagedefault = "en"

; (optional) URL shortener address to offer after a new paste is created.
; It is suggested to only use this with self-hosted shorteners as this will leak
; the pastes encryption key.
; urlshortener = "https://shortener.example.com/api?link="

; (optional) Let users create a QR code for sharing the paste URL with one click.
; It works both when a new paste is created and when you view a paste.
; qrcode = true

; (optional) Let users send an email sharing the paste URL with one click.
; It works both when a new paste is created and when you view a paste.
; email = true

; (optional) IP based icons are a weak mechanism to detect if a comment was from
; a different user when the same username was used in a comment. It might get
; used to get the IP of a comment poster if the server salt is leaked and a
; SHA512 HMAC rainbow table is generated for all (relevant) IPs.
; Can be set to one these values:
; "none" / "identicon" (default) / "jdenticon" / "vizhash".
; icon = "none"

; Content Security Policy headers allow a website to restrict what sources are
; allowed to be accessed in its context. You need to change this if you added
; custom scripts from third-party domains to your templates, e.g. tracking
; scripts or run your site behind certain DDoS-protection services.
; Check the documentation at https://content-security-policy.com/
; Notes:
; - If you use any bootstrap theme, you can remove the allow-popups from the
;   sandbox restrictions.
; - If you use the bootstrap5 theme, you must change default-src to 'self' to
;   enable display of the svg icons
; - By default this disallows to load images from third-party servers, e.g. when
;   they are embedded in pastes. If you wish to allow that, you can adjust the
;   policy here. See https://github.com/PrivateBin/PrivateBin/wiki/FAQ#why-does-not-it-load-embedded-images
;   for details.
; - The 'wasm-unsafe-eval' is used to enable webassembly support (used for zlib
;   compression). You can remove it if compression doesn't need to be supported.
; cspheader = "default-src 'none'; base-uri 'self'; form-action 'none'; manifest-src 'self'; connect-src * blob:; script-src 'self' 'wasm-unsafe-eval'; style-src 'self'; font-src 'self'; frame-ancestors 'none'; img-src 'self' data: blob:; media-src blob:; object-src blob:; sandbox allow-same-origin allow-scripts allow-forms allow-popups allow-modals allow-downloads"

; stay compatible with PrivateBin Alpha 0.19, less secure
; if enabled will use base64.js version 1.7 instead of 2.1.9 and sha1 instead of
; sha256 in HMAC for the deletion token
; zerobincompatibility = false

; Enable or disable the warning message when the site is served over an insecure
; connection (insecure HTTP instead of HTTPS), defaults to true.
; Secure transport methods like Tor and I2P domains are automatically whitelisted.
; It is **strongly discouraged** to disable this.
; See https://github.com/PrivateBin/PrivateBin/wiki/FAQ#why-does-it-show-me-an-error-about-an-insecure-connection for more information.
; httpwarning = true

; Pick compression algorithm or disable it. Only applies to pastes/comments
; created after changing the setting.
; Can be set to one these values: "none" / "zlib" (default).
; compression = "zlib"

[expire]
; expire value that is selected per default
; make sure the value exists in [expire_options]
default = "1week"

[expire_options]
; Set each one of these to the number of seconds in the expiration period,
; or 0 if it should never expire
5min = 300
10min = 600
1hour = 3600
1day = 86400
1week = 604800
; Well this is not *exactly* one month, it's 30 days:
1month = 2592000
1year = 31536000
never = 0

[formatter_options]
; Set available formatters, their order and their labels
plaintext = "Plain Text"
syntaxhighlighting = "Source Code"
markdown = "Markdown"

[traffic]
; time limit between calls from the same IP address in seconds
; Set this to 0 to disable rate limiting.
limit = 10

; (optional) Set IPs addresses (v4 or v6) or subnets (CIDR) which are exempted
; from the rate-limit. Invalid IPs will be ignored. If multiple values are to
; be exempted, the list needs to be comma separated. Leave unset to disable
; exemptions.
; exempted = "1.2.3.4,10.10.10/24"

; (optional) If you want only some source IP addresses (v4 or v6) or subnets
; (CIDR) to be allowed to create pastes, set these here. Invalid IPs will be
; ignored. If multiple values are to be exempted, the list needs to be comma
; separated. Leave unset to allow anyone to create pastes.
; creators = "1.2.3.4,10.10.10/24"

; (optional) if your website runs behind a reverse proxy or load balancer,
; set the HTTP header containing the visitors IP address, i.e. X_FORWARDED_FOR
; header = "X_FORWARDED_FOR"

[purge]
; minimum time limit between two purgings of expired pastes, it is only
; triggered when pastes are created
; Set this to 0 to run a purge every time a paste is created.
limit = 300

; maximum amount of expired pastes to delete in one purge
; Set this to 0 to disable purging. Set it higher, if you are running a large
; site
batchsize = 10

;[model]
; name of data model class to load and directory for storage
; the default model "Filesystem" stores everything in the filesystem
;class = Filesystem
;[model_options]
;dir = PATH "data"

;[model]
; example of a Google Cloud Storage configuration
;class = GoogleCloudStorage
;[model_options]
;bucket = "my-private-bin"
;prefix = "pastes"
;uniformacl = false

;[model]
; example of DB configuration for MySQL
;class = Database
;[model_options]
;dsn = "mysql:host=localhost;dbname=privatebin;charset=UTF8"
;tbl = "privatebin_"	; table prefix
;usr = "privatebin"
;pwd = "Z3r0P4ss"
;opt[12] = true	  ; PDO::ATTR_PERSISTENT

;[model]
; example of DB configuration for SQLite
;class = Database
;[model_options]
;dsn = "sqlite:" PATH "data/db.sq3"
;usr = null
;pwd = null
;opt[12] = true	; PDO::ATTR_PERSISTENT

[model]
; example of DB configuration for PostgreSQL
class = Database
[model_options]
dsn = "pgsql:host=$DB_HOST;dbname=$DB_NAME"
tbl = "privatebin_"     ; table prefix
usr = "$DB_USER"
pwd = "$DB_PASSWORD"
opt[12] = true    ; PDO::ATTR_PERSISTENT

;[model]
; example of S3 configuration for Rados gateway / CEPH
;class = S3Storage
;[model_options]
;region = ""
;version = "2006-03-01"
;endpoint = "https://s3.my-ceph.invalid"
;use_path_style_endpoint = true
;bucket = "my-bucket"
;accesskey = "my-rados-user"
;secretkey = "my-rados-pass"

;[model]
; example of S3 configuration for AWS
;class = S3Storage
;[model_options]
;region = "eu-central-1"
;version = "latest"
;bucket = "my-bucket"
;accesskey = "access key id"
;secretkey = "secret access key"

;[model]
; example of S3 configuration for AWS using its SDK default credential provider chain
; if relying on environment variables, the AWS SDK will look for the following:
; - AWS_ACCESS_KEY_ID
; - AWS_SECRET_ACCESS_KEY
; - AWS_SESSION_TOKEN (if needed)
; for more details, see https://docs.aws.amazon.com/sdk-for-php/v3/developer-guide/guide_credentials.html#default-credential-chain
;class = S3Storage
;[model_options]
;region = "eu-central-1"
;version = "latest"
;bucket = "my-bucket"

;[yourls]
; When using YOURLS as a "urlshortener" config item:
; - By default, "urlshortener" will point to the YOURLS API URL, with or without
;   credentials, and will be visible in public on the PrivateBin web page.
;   Only use this if you allow short URL creation without credentials.
; - Alternatively, using the parameters in this section ("signature" and
;   "apiurl"), "urlshortener" needs to point to the base URL of your PrivateBin
;   instance with "?shortenviayourls&link=" appended. For example:
;   urlshortener = "${basepath}?shortenviayourls&link="
;   This URL will in turn call YOURLS on the server side, using the URL from
;   "apiurl" and the "access signature" from the "signature" parameters below.

; (optional) the "signature" (access key) issued by YOURLS for the using account
; signature = ""
; (optional) the URL of the YOURLS API, called to shorten a PrivateBin URL
; apiurl = "https://yourls.example.com/yourls-api.php"

;[sri]
; Subresource integrity (SRI) hashes used in template files. Uncomment and set
; these for all js files used. See:
; https://github.com/PrivateBin/PrivateBin/wiki/FAQ#user-content-how-to-make-privatebin-work-when-i-have-changed-some-javascript-files
;js/privatebin.js = "sha512-[…]"
EOF

echo "PrivateBin服务已部署在：https://$PRIVATEBIN_DOMAIN"
