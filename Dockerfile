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
    unzip /tmp/xray.zip xray -d /usr/bin/ && \
    chmod +x /usr/bin/xray

# Stage 2: Final image
FROM alpine:3.21

RUN apk add --no-cache bash ca-certificates netcat-openbsd curl nmap jq dumb-init tzdata

ENV TZ=Europe/Moscow
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

COPY --from=xray-downloader /usr/bin/xray /usr/bin/xray

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 3128 1080

HEALTHCHECK --interval=30s --timeout=5s --retries=3 \
  CMD wget -q --spider --proxy http://127.0.0.1:3128 http://ifconfig.me || exit 1

ENTRYPOINT ["dumb-init", "--", "/entrypoint.sh"]
