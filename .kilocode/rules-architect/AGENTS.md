# Project Architecture Rules (Non-Obvious Only)

- Runtime architecture is intentionally two-process-in-one-container: [`entrypoint.sh`](entrypoint.sh) starts `xray` and `3proxy` in background, then orchestrates lifecycle via trap + [`wait -n`](entrypoint.sh:85).
- Data path is hard-coupled: client -> 3proxy (`3128` HTTP / `1080` SOCKS) -> local Xray SOCKS inbound (`127.0.0.1:${XRAY_SOCKS_PORT}`) -> Xray outbound; changing one leg requires synchronized edits in [`entrypoint.sh`](entrypoint.sh) and [`conf/xray.json.example`](conf/xray.json.example).
- Deployment assumes external TLS termination (Angie stream proxy) rather than TLS in 3proxy container; examples map TLS listeners to raw local ports in [`angie/proxy.goldfinches.ru.conf.example`](angie/proxy.goldfinches.ru.conf.example).
- Secrets boundary is file-based, not env-only: compose bind-mounts host [`conf/xray.json`](conf/xray.json) into container as read-only `/etc/xray/conf.json` from [`docker-compose.yml`](docker-compose.yml).
