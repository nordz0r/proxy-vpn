# Stage 1: Download Xray release binary
FROM alpine:3.21 AS xray-downloader
RUN apk add --no-cache curl unzip
ARG TARGETARCH
RUN case "$TARGETARCH" in \
      amd64)  ARCH="64" ;; \
      arm64)  ARCH="arm64-v8a" ;; \
      *)      ARCH="64" ;; \
    esac && \
    LATEST=$(curl -fsSL https://api.github.com/repos/XTLS/Xray-core/releases/latest | grep '"tag_name"' | cut -d'"' -f4) && \
    curl -fsSL -o /tmp/xray.zip "https://github.com/XTLS/Xray-core/releases/download/${LATEST}/Xray-linux-${ARCH}.zip" && \
    mkdir -p /tmp/xray-release && \
    unzip /tmp/xray.zip xray geoip.dat geosite.dat -d /tmp/xray-release/ && \
    chmod +x /tmp/xray-release/xray

# Stage 2: Final image
FROM alpine:3.21

RUN apk add --no-cache bash ca-certificates netcat-openbsd curl jq dumb-init tzdata nmap bind-tools

ENV TZ=Europe/Moscow
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

COPY --from=xray-downloader /tmp/xray-release/xray /usr/bin/xray
COPY --from=xray-downloader /tmp/xray-release/geoip.dat /usr/share/xray/geoip.dat
COPY --from=xray-downloader /tmp/xray-release/geosite.dat /usr/share/xray/geosite.dat
ENV XRAY_LOCATION_ASSET=/usr/share/xray/

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 3128 1080

HEALTHCHECK --interval=30s --timeout=5s --retries=3 \
  CMD ([ -z "$HTTP_PORT" ] || nc -z 127.0.0.1 "$HTTP_PORT") && \
      ([ -z "$SOCKS_PORT" ] || nc -z 127.0.0.1 "$SOCKS_PORT") || exit 1

ENTRYPOINT ["dumb-init", "--", "/entrypoint.sh"]
