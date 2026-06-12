#!/bin/bash
set -e

CONFIG_DIR="/etc/ocserv"
CONFIG_FILE="${CONFIG_DIR}/ocserv.conf"
TEMPLATE_FILE="${CONFIG_DIR}/ocserv.conf.template"
PASSWD_FILE="${CONFIG_DIR}/ocpasswd"

VPN_PORT=${VPN_PORT:-443}

# ================= 1. 检查并自动生成配置文件 =================
if [ ! -f "$CONFIG_FILE" ]; then
    echo "⚠️ 未检测到配置文件，正在从本地源码模板生成..."
    
    # 【修改点】不再使用 wget，直接从打包进去的源码模板拷贝
    if [ -f "$TEMPLATE_FILE" ]; then
        cp "$TEMPLATE_FILE" "$CONFIG_FILE"
    else
        echo "❌ 严重错误：未在容器内找到源码配置模板！"
        exit 1
    fi
    
    # 针对容器环境自动微调关键配置
    sed -i 's|^auth = .*|auth = "plain[passwd=/etc/ocserv/ocpasswd]"|g' "$CONFIG_FILE"
    sed -i 's|^run-as-user = .*|run-as-user = ocserv|g' "$CONFIG_FILE"
    sed -i 's|^run-as-group = .*|run-as-group = ocserv|g' "$CONFIG_FILE"
    sed -i 's|^server-cert = .*|server-cert = /etc/ocserv/server-cert.pem|g' "$CONFIG_FILE"
    sed -i 's|^server-key = .*|server-key = /etc/ocserv/server-key.pem|g' "$CONFIG_FILE"
    sed -i 's|^ipv4-network = .*|ipv4-network = 192.168.10.0|g' "$CONFIG_FILE"
    sed -i 's|^ipv4-netmask = .*|ipv4-netmask = 255.255.255.0|g' "$CONFIG_FILE"
    
    # 动态注入非 443 端口
    sed -i "s|^tcp-port = .*|tcp-port = ${VPN_PORT}|g" "$CONFIG_FILE"
    sed -i "s|^udp-port = .*|udp-port = ${VPN_PORT}|g" "$CONFIG_FILE"
    
    # 将默认 DNS 修改为 8.8.8.8
    sed -i 's|^dns =|#dns =|g' "$CONFIG_FILE"
    sed -i '/#dns =/a dns = 8.8.8.8' "$CONFIG_FILE"
    
    # 注释掉默认可能冲突的 route 选项，默认让全流量走 VPN
    sed -i 's|^route =|#route =|g' "$CONFIG_FILE"
    
    # 精准定位 www.example.com 所在的花括号配置块并注释
    sed -i '/www.example.com/,/^[[:space:]]*}/ s/^/#/' "$CONFIG_FILE"
    
    # 强行把可能存在的后台模式掰回前台
    sed -i 's|^run-as-status = daemon|run-as-status = foreground|g' "$CONFIG_FILE"
    
    # 关闭 1.5.0 模板中默认开启的自定义级防火墙限制
    sed -i 's|^restrict-user-to-routes =|#restrict-user-to-routes =|g' "$CONFIG_FILE"
    sed -i 's|^restrict-user-to-ports =|#restrict-user-to-ports =|g' "$CONFIG_FILE"
    
    # 关闭引发 Certificate is bad 的各种证书客户端策略
    sed -i 's|^enable-auth-passthrough =|#enable-auth-passthrough =|g' "$CONFIG_FILE"
    
    echo "✅ 配置文件初始化成功！(运行端口: ${VPN_PORT})"
fi

# ================= 2. 检查并自动生成自签名证书 =================
if [ ! -f "${CONFIG_DIR}/server-cert.pem" ] || [ ! -f "${CONFIG_DIR}/server-key.pem" ]; then
    echo "⚠️ 未检测到 SSL 证书，正在自动生成自签名证书..."
    cd /tmp
    echo -e "cn = \"VPN CA\"\norganization = \"Docker\"\nserial = 1\nexpiration_days = 3650\nca\ncert_signing_key\ncrl_signing_key" > ca.tmpl
    certtool --generate-privkey --outfile ca-key.pem
    certtool --generate-self-signed --load-privkey ca-key.pem --template ca.tmpl --outfile ca-cert.pem
    echo -e "cn = \"VPN Server\"\norganization = \"Docker\"\nexpiration_days = 3650\nsigning_key\nencryption_key\ntls_www_server" > server.tmpl
    certtool --generate-privkey --outfile server-key.pem
    certtool --generate-certificate --load-privkey server-key.pem --load-ca-certificate ca-cert.pem --load-ca-privkey ca-key.pem --template server.tmpl --outfile server-cert.pem
    mv server-cert.pem "${CONFIG_DIR}/server-cert.pem"
    mv server-key.pem "${CONFIG_DIR}/server-key.pem"
    rm -f ca.tmpl ca-key.pem ca-cert.pem server.tmpl
    echo "✅ SSL 证书自动生成并配置完成！"
fi

# ================= 3. 解析环境变量并自动生成用户 =================
if [ -n "$VPN_USER" ] && [ -n "$VPN_PASSWORD" ]; then
    echo "👤 检测到账号环境变量，正在配置默认用户: ${VPN_USER}..."
    printf "${VPN_PASSWORD}\n${VPN_PASSWORD}\n" | ocpasswd -c "$PASSWD_FILE" "$VPN_USER"
    echo "✅ 用户密码文件同步成功！"
fi

chmod 644 ${CONFIG_DIR}/* 2>/dev/null || true

# ================= 4. 开启网络转发并启动服务 =================
iptables -t nat -A POSTROUTING -j MASQUERADE
iptables -A FORWARD -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu

echo "🚀 正在启动 ocserv 1.5.0 服务..."
exec ocserv -c "$CONFIG_FILE" --foreground -d 1