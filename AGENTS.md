# AGENTS.md

This file provides guidance to agents when working with code in this repository.

- Stack is container-only: `alpine` image with runtime composition of `xray` + `3proxy` via [`entrypoint.sh`](entrypoint.sh).
- There is no app-level build/lint/test framework in repo (no `package.json`/`pyproject`/test tree). Use Docker workflows only.
- Main run command: `docker compose up --build -d` from repo root; config mount expects real [`conf/xray.json`](conf/xray.json) (example file is [`conf/xray.json.example`](conf/xray.json.example)).
- Smoke test used by image healthcheck mirrors [`Dockerfile`](Dockerfile): `wget -q --spider --proxy http://127.0.0.1:3128 http://ifconfig.me`.
- “Single test” equivalent is a one-proxy check, e.g. HTTP-only path through 3128; there are no unit/integration test targets.
- Auth is enabled only when BOTH `PROXY_USER` and `PROXY_PASS` are non-empty; otherwise [`entrypoint.sh`](entrypoint.sh) writes `auth none` and `allow *`.
- Do not add/edit static `3proxy.cfg`: it is always regenerated at container start by [`generate_3proxy_config`](entrypoint.sh:19).
- Internal chain is fixed: `3proxy -> socks5 127.0.0.1:${XRAY_SOCKS_PORT}` (default `10808`) then xray outbound.
- Xray readiness gate is TCP probe (`nc -z`) with 30s timeout; on timeout proxy still starts (warning only), so failures can be partially hidden.
- Trap-based shutdown is already implemented; keep background-process model compatible with [`wait -n`](entrypoint.sh:85).
- Important repo convention: secrets/runtime config are ignored by git (`.env`, `conf/xray.json`) per [`.gitignore`](.gitignore).
- Angie TLS termination examples in [`angie/proxy.goldfinches.ru.conf.example`](angie/proxy.goldfinches.ru.conf.example) forward raw TCP to local 3128/1080; keep container ports unchanged unless updating that mapping.
