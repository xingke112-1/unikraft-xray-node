#!/bin/sh
# 容器启动时用环境变量生成 xray 配置，再启动 xray。
# UUID / WS_PATH / XHTTP_PATH 由 deploy.sh 在 `unikraft run -e` 里传入，不写进镜像。
# 端口：8080 = VLESS+WS（主用），8081 = VLESS+XHTTP（备用）。
# 平台在外层终结 TLS 再以明文 HTTP 转进来，所以 xray 两个入站都不开 TLS、不放证书：
#   443:8080/http+tls  -> WS 入站（HTTP 模式，支持 WS Upgrade）
#   8443:8081/tls      -> XHTTP 入站（TCP 模式，TLS 终结后转发明文 HTTP；8443 只能用 tls，不能加 http）
# XHTTP 服务端 mode 用 auto（接受 packet-up / stream-up / stream-one），
# 客户端链接统一用 packet-up：对 CDN / 反向代理兼容性最高，CF 前置也走这条。
set -eu

UUID="${UUID:?必须设置 UUID 环境变量}"
WS_PATH="${WS_PATH:-/ws}"
XHTTP_PATH="${XHTTP_PATH:-/xhttp}"

mkdir -p /etc/xray
cat > /etc/xray/config.json <<EOF
{
  "log": { "loglevel": "warning" },
  "inbounds": [
    {
      "port": 8080,
      "listen": "0.0.0.0",
      "protocol": "vless",
      "settings": {
        "clients": [ { "id": "${UUID}" } ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "ws",
        "wsSettings": { "path": "${WS_PATH}" }
      },
      "sniffing": { "enabled": true, "destOverride": ["http", "tls"] }
    },
    {
      "port": 8081,
      "listen": "0.0.0.0",
      "protocol": "vless",
      "settings": {
        "clients": [ { "id": "${UUID}" } ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "xhttp",
        "xhttpSettings": { "path": "${XHTTP_PATH}", "mode": "auto" }
      },
      "sniffing": { "enabled": true, "destOverride": ["http", "tls"] }
    }
  ],
  "outbounds": [ { "protocol": "freedom", "settings": {} } ]
}
EOF

echo "[entrypoint] xray listening on 8080 (ws ${WS_PATH}) and 8081 (xhttp ${XHTTP_PATH})"
# 把节点链接也打到日志里，控制台 Logs 页就能直接复制导入。
# 容器启动时不知道平台分配的域名，所以 DOMAIN 要手动加一个环境变量：
# 控制台实例页 Runtime 里加 DOMAIN=<绿框里的域名> 再重启，日志里就会出现下面两条链接。
# （不加 DOMAIN 也没事，只是日志里不打印链接；链接照样可以用 gen_links.py 在本地生成。）
if [ -n "${DOMAIN:-}" ]; then
  _ws_noslash="${WS_PATH#/}"
  _xhttp_noslash="${XHTTP_PATH#/}"
  echo "[entrypoint] 节点链接（直接复制到 v2rayN / v2rayNG 导入）："
  echo "[entrypoint] vless://${UUID}@${DOMAIN}:443?encryption=none&security=tls&sni=${DOMAIN}&fp=chrome&type=ws&host=${DOMAIN}&path=%2F${_ws_noslash}#Unikraft-WS-Direct"
  echo "[entrypoint] vless://${UUID}@${DOMAIN}:8443?encryption=none&security=tls&sni=${DOMAIN}&fp=chrome&type=xhttp&host=${DOMAIN}&path=%2F${_xhttp_noslash}&mode=packet-up#Unikraft-XHTTP-Direct"
else
  echo "[entrypoint] 提示：加环境变量 DOMAIN=<你的域名> 再重启，日志里会直接打印节点链接（可复制导入）"
fi
# 可选：Beszel 监控探针（WebSocket 模式，主动连 Hub，不用开端口）。
# 只有设了 BESZEL_TOKEN 才启动；BESZEL_KEY/BESZEL_TOKEN 由实例环境变量传入，不进镜像。
if [ -n "${BESZEL_TOKEN:-}" ]; then
  echo "[entrypoint] starting beszel-agent (WS mode)"
  HUB_URL="${BESZEL_HUB_URL:-https://beszel.xxlxl.ggff.net}" KEY="${BESZEL_KEY:-}" TOKEN="$BESZEL_TOKEN" DISABLE_SSH=true /usr/local/bin/beszel-agent &
fi
exec /usr/local/bin/xray run -c /etc/xray/config.json
