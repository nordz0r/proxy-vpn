# Stage 1: Build Xray
FROM golang:1.24-alpine AS xray-builder
RUN apk add --no-cache git
RUN git clone --depth 1 https://github.com/XTLS/Xray-core.git /src
WORKDIR /src
RUN CGO_ENABLED=0 go build -trimpath -ldflags "-s -w" -o /usr/bin/xray ./main

# Stage 2: Build 3proxy
FROM alpine:3.21 AS proxy-builder
RUN apk add --no-cache gcc musl-dev make git
RUN git clone --depth 1 https://github.com/3proxy/3proxy.git /src
WORKDIR /src
RUN make -f Makefile.Linux
RUN strip bin/3proxy

# Stage 3: Final image
FROM alpine:3.21

RUN apk add --no-cache bash ca-certificates

COPY --from=xray-builder /usr/bin/xray /usr/bin/xray
COPY --from=proxy-builder /src/bin/3proxy /usr/bin/3proxy

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 3128 1080

HEALTHCHECK --interval=30s --timeout=5s --retries=3 \
  CMD wget -q --spider --proxy http://127.0.0.1:3128 http://ifconfig.me || exit 1

ENTRYPOINT ["/entrypoint.sh"]
