# Project Coding Rules (Non-Obvious Only)

- Do not commit or template runtime secrets: real Xray config must stay in [`conf/xray.json`](conf/xray.json) and is intentionally gitignored in [`.gitignore`](.gitignore).
- Do not introduce a static 3proxy config file in repo; startup always regenerates it via [`generate_3proxy_config`](entrypoint.sh:19).
- Keep auth logic exactly pair-based: only BOTH `PROXY_USER` and `PROXY_PASS` enable `auth strong`; a single variable set falls back to open proxy (see [`entrypoint.sh`](entrypoint.sh)).
- Preserve the chained topology `3proxy -> local xray socks` and port coupling (`XRAY_SOCKS_PORT` in both Xray inbound and 3proxy parent) across edits in [`entrypoint.sh`](entrypoint.sh) and [`conf/xray.json.example`](conf/xray.json.example).
- Keep multi-process shell model (`xray` + `3proxy`) and shutdown behavior compatible with [`wait -n`](entrypoint.sh:85) and trap cleanup.
