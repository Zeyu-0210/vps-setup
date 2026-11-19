#!/usr/bin/env bash
# Xray VLESS + REALITY 一键部署脚本
#
# 用法（在新服务器上以 root 身份运行，支持 Debian 11+ / Ubuntu 20.04+）：
#   bash <(curl -fsSL https://raw.githubusercontent.com/Zeyu-0210/vps-setup/main/install.sh)
#
# 可选环境变量：
#   PORT  监听端口，默认 443
#   SNI   伪装的网站，默认 www.microsoft.com
#   NAME  节点名称，默认 Reality-月日
# 例：PORT=8443 bash <(curl -fsSL ...)
#
# 每次运行都会生成全新的密钥和链接，脚本本身不包含任何密钥。

set -euo pipefail

PORT="${PORT:-443}"
SNI="${SNI:-www.microsoft.com}"
NAME="${NAME:-Reality-$(date +%m%d)}"
CONFIG=/usr/local/etc/xray/config.json
LINK_FILE=/root/vless-link.txt

red()   { printf '\033[31m%s\033[0m\n' "$*"; }
green() { printf '\033[32m%s\033[0m\n' "$*"; }
info()  { printf '\033[36m==> %s\033[0m\n' "$*"; }

[ "$(id -u)" -eq 0 ] || { red "请用 root 身份运行（先执行 sudo -i）"; exit 1; }
command -v apt-get >/dev/null 2>&1 || { red "只支持 Debian / Ubuntu 系统"; exit 1; }

info "安装依赖"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq curl openssl ca-certificates >/dev/null

info "安装 / 更新 Xray"
bash -c "$(curl -fsSL https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install

info "生成密钥"
UUID=$(xray uuid)
KEYS=$(xray x25519)
# 旧版输出 "Private key / Public key"，新版输出 "PrivateKey / Password"（Password 即公钥）
PRIV=$(printf '%s\n' "$KEYS" | awk -F': *' '/Private/{print $2; exit}' | tr -d '[:space:]')
PUB=$(printf '%s\n' "$KEYS" | awk -F': *' '/Public|Password/{print $2; exit}' | tr -d '[:space:]')
SID=$(openssl rand -hex 8)
if [ -z "$PRIV" ] || [ -z "$PUB" ]; then
  red "密钥解析失败，xray x25519 输出："
  echo "$KEYS"
  exit 1
fi

info "获取服务器公网 IP"
IP=$(curl -fs4 --max-time 5 https://api.ipify.org || curl -fs4 --max-time 5 https://ifconfig.me || hostname -I | awk '{print $1}')
[ -n "$IP" ] || { red "无法获取公网 IP"; exit 1; }

info "写入配置"
mkdir -p "$(dirname "$CONFIG")"
cat > "$CONFIG" <<EOF
{
  "log": { "loglevel": "warning" },
  "inbounds": [{
    "port": $PORT,
    "protocol": "vless",
    "settings": {
      "clients": [{ "id": "$UUID", "flow": "xtls-rprx-vision" }],
      "decryption": "none"
    },
    "streamSettings": {
      "network": "tcp",
      "security": "reality",
      "realitySettings": {
        "dest": "$SNI:443",
        "serverNames": ["$SNI"],
        "privateKey": "$PRIV",
        "shortIds": ["$SID"]
      }
    },
    "sniffing": { "enabled": true, "destOverride": ["http", "tls", "quic"] }
  }],
  "outbounds": [
    { "protocol": "freedom", "tag": "direct" },
    { "protocol": "blackhole", "tag": "block" }
  ],
  "routing": {
    "domainStrategy": "IPIfNonMatch",
    "rules": [
      { "type": "field", "domain": ["geosite:cn"], "outboundTag": "block" },
      { "type": "field", "ip": ["geoip:cn", "geoip:private"], "outboundTag": "block" }
    ]
  }
}
EOF
chmod 644 "$CONFIG"

xray run -test -config "$CONFIG" >/dev/null || { red "配置文件校验失败"; xray run -test -config "$CONFIG"; exit 1; }

info "开启 BBR 加速"
if ! sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null | grep -q bbr; then
  printf 'net.core.default_qdisc=fq\nnet.ipv4.tcp_congestion_control=bbr\n' > /etc/sysctl.d/99-bbr.conf
  sysctl --system >/dev/null 2>&1 || true
fi

info "放行防火墙端口 $PORT/tcp"
if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -q "Status: active"; then
  ufw allow "$PORT"/tcp >/dev/null
fi

info "启动 Xray"
systemctl enable xray >/dev/null 2>&1 || true
systemctl restart xray
sleep 2
if ! systemctl is-active --quiet xray; then
  red "Xray 启动失败，日志如下："
  journalctl -u xray -n 30 --no-pager
  exit 1
fi

info "检查 Anthropic (Claude) API 是否可访问"
CODE=$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 -X POST https://api.anthropic.com/v1/messages || true)
case "$CODE" in
  400|401|405) green "可以访问（HTTP $CODE，未带密钥时返回这个是正常的）" ;;
  403)         red   "返回 403：这个 IP 可能被限制，建议换一台服务器" ;;
  *)           red   "无法访问（HTTP $CODE）" ;;
esac

LINK="vless://${UUID}@${IP}:${PORT}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${SNI}&fp=chrome&pbk=${PUB}&sid=${SID}&type=tcp#${NAME}"
umask 077
echo "$LINK" > "$LINK_FILE"

echo
green "部署完成！把下面这条链接复制到 Shadowrocket："
echo
echo "$LINK"
echo
echo "链接已保存到 $LINK_FILE，以后可以用 cat $LINK_FILE 再次查看。"
echo "如果服务商有“安全组 / 防火墙”设置，记得放行 TCP $PORT 端口。"
