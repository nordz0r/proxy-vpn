# proxy-vpn

[![Release](https://img.shields.io/github/v/release/nordz0r/proxy-vpn?style=flat-square&color=brightgreen)](https://github.com/nordz0r/proxy-vpn/releases)
[![Docker Image](https://img.shields.io/badge/ghcr.io-nordz0r%2Fproxy--vpn-blue?style=flat-square)](https://ghcr.io/nordz0r/proxy-vpn)
[![License: MIT](https://img.shields.io/badge/license-MIT-brightgreen?style=flat-square)](LICENSE)

**[Русская версия](README.md)**

HTTP and SOCKS5 proxy server powered by [Xray-core](https://github.com/XTLS/Xray-core) in a Docker container. Takes configurations exported from **[Amnezia VPN](https://amnezia.org/)** (VLESS + REALITY protocol) and turns them into a full-featured proxy for browsers, systems, or any application.

## Why

Amnezia VPN generates Xray configurations (VLESS + REALITY) for censorship circumvention. This project takes that config and spins up an HTTP and/or SOCKS5 proxy server you can connect to from:

- browsers (via proxy settings or extensions like FoxyProxy)
- mobile devices and IoT
- CLI tools and scripts (`curl`, `wget`, etc.)
- any device on your local network

```
Client ──► HTTP  :3128  ─┐
                          ├──► Xray ──► VLESS/REALITY ──► Internet
Client ──► SOCKS :1080  ─┘
```

Private networks and Russian domains are routed **directly**, bypassing the tunnel.

## Features

- **HTTP and SOCKS5 proxy** — both protocols simultaneously
- **Amnezia VPN configs** — use exported Xray JSON as-is
- **VLESS + REALITY** — modern DPI-resistant protocol
- **Split routing** — Russian domains/IPs and private networks go direct
- **Authentication** — multi-user support
- **Custom direct domains** — configurable via environment variables
- **Xray metrics** — optional HTTP statistics endpoint
- **Multi-arch** — `linux/amd64` and `linux/arm64`
- **Minimal image** — Alpine Linux, single process, ~30 MB

## Quick Start

### 1. Prepare Xray config

Export your configuration from Amnezia VPN in Xray JSON format, or create one manually:

```bash
cp conf/xray.json.example conf/xray.json
# Edit conf/xray.json — set your server address, UUID, REALITY keys
```

### 2. Configure environment

```bash
cp .env.example .env
# Edit .env — set proxy credentials
```

### 3. Run

```bash
docker compose up -d
```

The image is pulled automatically from GitHub Container Registry.

To build locally:

```bash
docker compose up --build -d
```

## Configuration

### Environment Variables

| Variable | Default | Description |
|---|---|---|
| `HTTP_PORT` | — | HTTP proxy port (e.g., `3128`). If not set — HTTP proxy is not started |
| `SOCKS_PORT` | — | SOCKS5 proxy port (e.g., `1080`). If not set — SOCKS5 proxy is not started |
| `PROXY_USERS` | — | Multi-user auth: `user1:pass1,user2:pass2` |
| `PROXY_USER` | — | Single-user login (fallback) |
| `PROXY_PASS` | — | Single-user password (fallback) |
| `XRAY_CONFIG` | `/etc/xray/conf.json` | Base config path inside container |
| `DIRECT_DOMAINS` | — | Domains for direct access (comma/semicolon separated), supports `*.example.com` |
| `LOG_LEVEL` | `warning` | Xray log level: `none`, `error`, `warning`, `info`, `debug`. At `info`/`debug` access log is enabled (client IP, destination, route) |
| `METRICS_PORT` | — | Xray HTTP metrics port (e.g., `9999`) |

> **Note:** at least one port (`HTTP_PORT` or `SOCKS_PORT`) must be set, otherwise the container will not start.

### Authentication

Configured via environment variables, **not** in `xray.json`:

```bash
# Multiple users (comma or semicolon separated)
PROXY_USERS=alice:secret1,bob:secret2

# Single user
PROXY_USER=alice
PROXY_PASS=secret1

# Empty/unset values = open proxy (no auth)
# For example, these can stay blank:
PROXY_USERS=
PROXY_USER=
```

### Routing

The entrypoint automatically injects routing rules:

| Match | Action |
|---|---|
| `geoip:private` + `geoip:ru` | Direct (bypass tunnel) |
| `geosite:private` + `geosite:category-ru` + `domain:local` + `DIRECT_DOMAINS` | Direct (bypass tunnel) |
| Everything else | Proxy (VLESS/REALITY) |

Add custom domains for direct access:

```bash
DIRECT_DOMAINS=*.corp.local,*.lan,example.internal
```

## Verify

```bash
# Should show your VPN server IP
curl -x http://user:pass@127.0.0.1:3128 https://ipinfo.io/json

# Should show your real IP (Russian site — goes direct)
curl -x http://user:pass@127.0.0.1:3128 https://2ip.ru

# SOCKS5 check
curl --socks5-hostname user:pass@127.0.0.1:1080 https://ipinfo.io/json
```

## TLS Termination (optional)

Example Angie/nginx stream config for TLS termination in front of local proxy ports:

```nginx
# Ensure your config has:
# stream {
#   include /etc/angie/stream.d/*.conf;
# }

# HTTPS proxy over TLS
server {
    listen 446 ssl;
    ssl_certificate     /etc/letsencrypt/live/example.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/example.com/privkey.pem;
    proxy_pass 127.0.0.1:3128;
}
```

## Architecture

- **entrypoint.sh** generates `/tmp/xray.runtime.json` at container start:
  - injects `http-in` / `socks-in` inbounds with auth and sniffing
  - injects `direct` outbound (freedom protocol) and routing rules
  - tags the first outbound in the base config as `proxy`
- **network_mode: host** — ports bind directly on the host
- **dumb-init** as PID 1 for proper signal handling
- Readiness check: both ports must respond within 30 seconds

## Debugging

```bash
# Container logs
docker compose logs -f vpn-proxy

# Inspect generated runtime config
docker exec vpn-proxy cat /tmp/xray.runtime.json | jq
```

## Keywords

Xray proxy, VLESS proxy, REALITY proxy, Amnezia VPN proxy, HTTP proxy Xray, SOCKS5 proxy Xray, Docker proxy VPN, censorship circumvention, Xray proxy server, browser proxy, Amnezia VPN config, Xray Docker, split tunneling, anti-censorship proxy, DPI bypass
