# AGENTS.md

This file provides guidance to agents when working with code in this repository.

- Stack is container-only: `alpine` image with `xray` via [`entrypoint.sh`](entrypoint.sh). No 3proxy.
- There is no app-level build/lint/test framework in repo (no `package.json`/`pyproject`/test tree). Use Docker workflows only.
- Main run command: `docker compose up --build -d` from repo root; config mount expects real [`conf/xray.json`](conf/xray.json) (example file is [`conf/xray.json.example`](conf/xray.json.example)).
- `conf/xray.json` should contain only `log` and `outbounds` sections. Inbounds (HTTP 3128 + SOCKS 1080) are injected at runtime by [`entrypoint.sh`](entrypoint.sh).
- Smoke test: `curl -x http://127.0.0.1:3128 https://ipinfo.io/json | jq`.
- Auth is configured via `PROXY_USERS=user1:pass1,user2:pass2` (preferred) or legacy `PROXY_USER`+`PROXY_PASS`. If nothing is set, proxy runs without authentication.
- Xray readiness gate is TCP probe (`nc -z`) with 30s timeout; on timeout proxy still starts (warning only), so failures can be partially hidden.
- Important repo convention: secrets/runtime config are ignored by git (`.env`, `conf/xray.json`) per [`.gitignore`](.gitignore).
- Angie TLS termination examples in [`angie/proxy.goldfinches.ru.conf.example`](angie/proxy.goldfinches.ru.conf.example) forward raw TCP to local 3128/1080; keep container ports unchanged unless updating that mapping.
