# Project Debug Rules (Non-Obvious Only)

- Use [`docker compose logs -f vpn-proxy`](README.md:98) first: startup/auth parse errors are emitted only by `[entrypoint]` lines in [`entrypoint.sh`](entrypoint.sh).
- Readiness is strict in [`entrypoint.sh`](entrypoint.sh): timeout at 30s exits with code 1, so container restarts can look like random crashes under `restart: unless-stopped` in [`docker-compose.yml`](docker-compose.yml).
- To inspect generated runtime config, use [`cat /tmp/xray.runtime.json`](README.md:92); debugging only [`conf/xray.json`](conf/xray.json) misses injected `http-in`/`socks-in`.
- Auth debugging pitfall: malformed `PROXY_USERS` (including empty entries after `,`/`;`) can collapse to zero valid users and hard-fail at [`entrypoint.sh`](entrypoint.sh).
