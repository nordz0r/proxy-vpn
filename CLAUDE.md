# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Containerized HTTP/SOCKS proxy wrapping Xray (VLESS/REALITY). Single Alpine container, single process (`xray`), no additional proxy daemons.

Traffic flow: `client (HTTP:3128 | SOCKS:1080) → xray inbound → xray outbound (VLESS/REALITY)`

## Build & Run

```bash
docker compose up --build -d       # build and start
docker compose logs -f vpn-proxy   # watch logs
```

## Operational Checks

No test framework — verification is Docker + curl:

```bash
# HTTP proxy
curl --noproxy '' -x http://127.0.0.1:3128 https://ipinfo.io/json | jq

# SOCKS5 proxy
curl --socks5-hostname 127.0.0.1:1080 https://ipinfo.io/json | jq

# Inspect runtime config inside container
docker exec vpn-proxy cat /tmp/xray.runtime.json
```

Both IPs should match and differ from your host IP.

## Architecture

### Runtime Inbound Injection

`entrypoint.sh` is the core logic. The `prepare_xray_config()` function (line 17):

1. Reads base config from `$XRAY_CONFIG` (default `/etc/xray/conf.json`, mounted from `conf/xray.json`)
2. Strips any existing inbounds tagged `http-in` / `socks-in` (preserves all other inbounds)
3. Injects fresh HTTP and SOCKS5 inbounds with auth and sniffing settings
4. Writes result to `/tmp/xray.runtime.json`

Static edits to `http-in`/`socks-in` in the base config are overwritten on every container start.

### Auth Precedence (fixed order)

1. `PROXY_USERS` — comma or semicolon-separated `user:pass` pairs (supports `:` in passwords via join-tail)
2. `PROXY_USER` + `PROXY_PASS` — single-user fallback
3. No auth — open proxy

Invalid/empty user list when auth is enabled is fatal (`exit 1`).

### Readiness

Both ports must respond to `nc -z` within 30 seconds or the container exits with code 1. This is a hard fail, not a soft warning.

### Network Mode

`docker-compose.yml` uses `network_mode: host` — ports `3128`/`1080` bind directly on the host. Bridge mode won't work for the intended deployment.

### TLS Termination

External to this container. Angie reverse proxy config example in `angie/` handles HTTPS→TCP forwarding to local Xray ports.

## Secrets & Configuration

- `conf/xray.json` — real Xray config (gitignored), must exist for container to start. `conf/xray.json.example` is a template.
- `.env` — runtime env vars (gitignored). `.env.example` is a template.

### Configurable Env Vars

| Variable | Default | Purpose |
|---|---|---|
| `PROXY_PORT` | `3128` | HTTP proxy port |
| `SOCKS_PORT` | `1080` | SOCKS5 proxy port |
| `XRAY_CONFIG` | `/etc/xray/conf.json` | Base config path inside container |
| `PROXY_USERS` | — | Multi-user auth (`user1:pass1,user2:pass2`) |
| `PROXY_USER` | — | Single-user auth (legacy) |
| `PROXY_PASS` | — | Single-user password (legacy) |

## Shell Conventions

- `set -e` fail-fast
- Uppercase for env knobs, lowercase for `local` vars
- `[entrypoint]` log prefix for all startup messages
- `dumb-init` as PID 1 for signal forwarding

## Commit Style

Conventional commits: `fix(scope): message`, `feat(scope): message`, `build(scope): message`, `docs(scope): message`.
