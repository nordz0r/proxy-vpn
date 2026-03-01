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

# Stage 2: Build 3proxy
FROM alpine:3.21 AS proxy-builder
RUN apk add --no-cache gcc musl-dev make git
RUN git clone --depth 1 https://github.com/3proxy/3proxy.git /src
WORKDIR /src
RUN make -f Makefile.Linux
RUN strip bin/3proxy

# Stage 3: Final image
FROM alpine:3.21

RUN apk add --no-cache bash ca-certificates netcat-openbsd

COPY --from=xray-downloader /usr/bin/xray /usr/bin/xray
COPY --from=proxy-builder /src/bin/3proxy /usr/bin/3proxy

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 3128 1080

HEALTHCHECK --interval=30s --timeout=5s --retries=3 \
  CMD wget -q --spider --proxy http://127.0.0.1:3128 http://ifconfig.me || exit 1

ENTRYPOINT ["/entrypoint.sh"]
