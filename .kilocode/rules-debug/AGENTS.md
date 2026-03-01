# Project Debug Rules (Non-Obvious Only)

- First check container logs because both daemons are started from one shell entrypoint: `docker compose logs -f vpn-proxy` (startup failures in one process can terminate both via [`wait -n`](entrypoint.sh:85)).
- Xray can fail “softly”: readiness loop in [`entrypoint.sh`](entrypoint.sh) times out after 30s and still starts 3proxy, so an open proxy port does not prove tunnel health.
- Validate the chain in order: xray local socks (`${XRAY_SOCKS_PORT}`) -> 3proxy (`3128/1080`) -> external endpoint; mismatch between [`entrypoint.sh`](entrypoint.sh) and [`conf/xray.json`](conf/xray.json) is a common hidden breakage.
- If auth behaves unexpectedly, confirm BOTH env vars are set; a single missing var silently switches to open access path in [`generate_3proxy_config`](entrypoint.sh:19).
