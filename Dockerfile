# Unikraft Cloud 用 xray VLESS 节点镜像：WS 主用 + XHTTP 备用
# 做法：平台在外层终结 TLS，xray 只在容器内监听明文端口，不放证书，也不用 REALITY。
#   443:8080/http+tls -> VLESS+WS（主用，兼容性最好）
#   8443:8081/tls     -> VLESS+XHTTP（备用，mode=auto，客户端用 packet-up 走 CDN 最稳）
# Xray 版本固定写死，升级时只改 XRAY_VERSION 一个地方。
# 已验证：v26.11.9 是 2026-11-09 发布的 Latest（GitHub API 当日复核，非 pre-release），
# Xray-linux-64.zip 可下载，解压出的 xray 能正常启动。
ARG XRAY_VERSION=v26.11.9
ARG BESZEL_VERSION=0.21.2

FROM alpine:latest AS fetch
ARG XRAY_VERSION
ARG BESZEL_VERSION
RUN apk add --no-cache curl unzip ca-certificates \
 && curl -fsSL -o /tmp/xray.zip \
      "https://github.com/XTLS/Xray-core/releases/download/${XRAY_VERSION}/Xray-linux-64.zip" \
 && unzip -q /tmp/xray.zip -d /tmp/xray \
 && install -m 0755 /tmp/xray/xray /usr/local/bin/xray \
 && /usr/local/bin/xray version \
 && curl -fsSL -o /tmp/beszel-agent.tar.gz \
      "https://github.com/henrygd/beszel/releases/download/v${BESZEL_VERSION}/beszel-agent_${BESZEL_VERSION}_linux_amd64.tar.gz" \
 && tar -xzf /tmp/beszel-agent.tar.gz -C /tmp \
 && install -m 0755 /tmp/beszel-agent /usr/local/bin/beszel-agent \
 && /usr/local/bin/beszel-agent --version || /usr/local/bin/beszel-agent -v || true

FROM alpine:latest
RUN apk add --no-cache ca-certificates
COPY --from=fetch /usr/local/bin/xray /usr/local/bin/xray
COPY --from=fetch /usr/local/bin/beszel-agent /usr/local/bin/beszel-agent
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
# EXPOSE 在 Unikraft Cloud 上会被忽略（以 -p 发布端口为准），写在这里只作文档。
EXPOSE 8080 8081
ENTRYPOINT ["/entrypoint.sh"]
