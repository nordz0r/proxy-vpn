# AGENTS.md

This file provides guidance to agents when working with code in this repository.

- Stack is Xray-only in one container: runtime inbounds are generated in [`entrypoint.sh`](entrypoint.sh), not stored statically.
- No app-level lint/type/test runner exists; operational checks are Docker + curl from [`README.md`](README.md).
- Build/run: `docker compose up --build -d`.
- Logs: `docker compose logs -f vpn-proxy`.
- Single-path check (HTTP only): `curl --noproxy '' -x http://127.0.0.1:3128 https://ipinfo.io/json | jq`.
- Single-path check (SOCKS only): `curl --socks5-hostname 127.0.0.1:1080 https://ipinfo.io/json | jq`.
- Base config mount is mandatory: [`docker-compose.yml`](docker-compose.yml) binds host [`conf/xray.json`](conf/xray.json) to `/etc/xray/conf.json`; [`conf/xray.json.example`](conf/xray.json.example) is just a template.
- Inbound ownership is tag-based in [`prepare_xray_config()`](entrypoint.sh:17): tags `http-in` and `socks-in` are replaced at startup.
- Auth parser in [`prepare_xray_config()`](entrypoint.sh:17) accepts comma/semicolon separators and keeps `:` inside password (`split(":")` + join tail); invalid/empty user list is fatal (`exit 1`).
- Auth precedence is fixed: `PROXY_USERS` first, fallback to `PROXY_USER`+`PROXY_PASS`, otherwise open proxy (see [`entrypoint.sh`](entrypoint.sh)).
- Runtime style conventions in shell code: `set -e`, uppercase env knobs, lowercase `local` vars, explicit fail-fast `exit 1`, and `[entrypoint]` log prefix.
- Readiness is hard-fail: both ports (`3128` and `1080`) must open within 30 seconds or container exits (see [`entrypoint.sh`](entrypoint.sh)).
- Secrets boundary is file-based and gitignored in [`.gitignore`](.gitignore): [`.env`](.env) and [`conf/xray.json`](conf/xray.json).
- External AI rules: no `CLAUDE.md`/`.cursorrules`/Copilot instructions in repo; [`.claude/settings.local.json`](.claude/settings.local.json) is tool-permission metadata only.
