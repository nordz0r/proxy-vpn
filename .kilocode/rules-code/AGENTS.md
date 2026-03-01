# Project Coding Rules (Non-Obvious Only)

- Do not commit runtime secrets: real [`conf/xray.json`](conf/xray.json) and [`.env`](.env) are gitignored in [`.gitignore`](.gitignore).
- Treat [`conf/xray.json`](conf/xray.json) as base outbound/log config: runtime inbounds are rebuilt by [`prepare_xray_config()`](entrypoint.sh:17) and tags `http-in`/`socks-in` are replaced every start.
- Preserve auth precedence in [`prepare_xray_config()`](entrypoint.sh:17): `PROXY_USERS` > (`PROXY_USER` + `PROXY_PASS`) > open proxy.
- Keep parser behavior in [`prepare_xray_config()`](entrypoint.sh:31): both `,` and `;` separators are valid, and `:` inside password is preserved via `split(":")` + tail join.
- Keep fail-fast behavior: invalid/empty parsed auth list exits with code 1 in [`prepare_xray_config()`](entrypoint.sh:42).
- If changing ports, update all coupled points together: env defaults in [`entrypoint.sh`](entrypoint.sh), readiness probes in [`entrypoint.sh`](entrypoint.sh), and published endpoints in [`README.md`](README.md)/[`angie/proxy.goldfinches.ru.conf.example`](angie/proxy.goldfinches.ru.conf.example).
