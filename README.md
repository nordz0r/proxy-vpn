# proxy-vpn

Containerized HTTP/SOCKS5 proxy over Xray (VLESS + REALITY). Single Alpine container, single process, zero additional daemons.

```
client ──► HTTP :3128  ─┐
                        ├──► xray ──► VLESS/REALITY ──► internet
client ──► SOCKS :1080 ─┘
```

Private networks and Russian domains are routed **directly**, bypassing the tunnel.

## Quick Start

**1. Prepare Xray config**

```bash
cp conf/xray.json.example conf/xray.json
# Edit conf/xray.json — set your server address, UUID, REALITY keys
```

**2. Configure environment**

```bash
cp .env.example .env
# Edit .env — set proxy credentials
```

**3. Run**

```bash
docker compose up --build -d
```

## Configuration

### Environment Variables

| Variable | Default | Description |
|---|---|---|
| `PROXY_PORT` | `3128` | HTTP proxy port |
| `SOCKS_PORT` | `1080` | SOCKS5 proxy port |
| `PROXY_USERS` | — | Multi-user auth: `user1:pass1,user2:pass2` |
| `PROXY_USER` | — | Single-user auth (fallback) |
| `PROXY_PASS` | — | Single-user password (fallback) |
| `XRAY_CONFIG` | `/etc/xray/conf.json` | Base config path inside container |
| `DIRECT_DOMAINS` | — | Comma/semicolon list of domains for direct bypass, supports wildcard prefix (`*.example.com`) |

### Authentication

Auth is configured via environment variables, **not** in `xray.json`.

```bash
# Multiple users (comma or semicolon separated)
PROXY_USERS=alice:secret1,bob:secret2

# Single user (legacy)
PROXY_USER=alice
PROXY_PASS=secret1

# No variables set = open proxy (no auth)
```

Direct bypass domains via env:

```bash
DIRECT_DOMAINS=*.corp.local,*.lan,example.internal
```

### Routing

The entrypoint automatically injects routing rules:

| Match | Action |
|---|---|
| `geoip:private` + `geoip:ru` | Direct (bypass tunnel) |
| `geosite:private` + `geosite:category-ru` + `domain:local` + `DIRECT_DOMAINS` | Direct (bypass tunnel) |
| Everything else | Proxy (VLESS/REALITY) |

## Verify

```bash
# Should show your VPN server IP
curl -x http://127.0.0.1:3128 https://ipinfo.io/json

# Should show your real IP (Russian site, bypassed)
curl -x http://127.0.0.1:3128 https://2ip.ru

# SOCKS5 check
curl --socks5-hostname 127.0.0.1:1080 https://ipinfo.io/json
```

## TLS Termination (optional)

Example stream config for Angie/nginx (TLS termination in front of local proxy ports):

```nginx
# Ensure angie/nginx has:
# stream {
#   include /etc/angie/stream.d/*.conf;
# }

# HTTP proxy without TLS
server {
    listen 444;
    proxy_pass 127.0.0.1:3128;
}

# HTTPS proxy over TLS
server {
    listen 446 ssl;
    ssl_certificate     /etc/letsencrypt/live/example.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/example.com/privkey.pem;
    proxy_pass 127.0.0.1:3128;
}

# SOCKS5 over TLS (optional)
# server {
#     listen 445 ssl;
#     ssl_certificate     /etc/letsencrypt/live/example.com/fullchain.pem;
#     ssl_certificate_key /etc/letsencrypt/live/example.com/privkey.pem;
#     proxy_pass 127.0.0.1:1080;
# }
```

## Architecture

- **entrypoint.sh** generates `/tmp/xray.runtime.json` at container start:
  - Injects `http-in` / `socks-in` inbounds with auth and sniffing
  - Injects `direct` outbound (freedom protocol) and routing rules
  - Tags the first outbound in base config as `proxy`
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
