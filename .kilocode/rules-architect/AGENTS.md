# Project Architecture Rules (Non-Obvious Only)

- Runtime architecture is single-process-in-container now: [`entrypoint.sh`](entrypoint.sh) starts only Xray and waits on one PID via [`wait "$XRAY_PID"`](entrypoint.sh:122).
- Inbound lifecycle is declarative-by-tag: [`prepare_xray_config()`](entrypoint.sh:17) removes existing `http-in`/`socks-in` entries and recreates them each start; static edits to those tags in base config are overwritten.
- Readiness gate is part of architecture, not monitoring only: both HTTP+SOCKS listeners must come up before service is considered alive ([`entrypoint.sh`](entrypoint.sh), loop around [`nc -z`](entrypoint.sh:108)).
- Deployment contract depends on `network_mode: host` in [`docker-compose.yml`](docker-compose.yml): docs and Angie stream mapping assume host-local `127.0.0.1:3128/1080` reachability.
- TLS is intentionally externalized: [`angie/proxy.goldfinches.ru.conf.example`](angie/proxy.goldfinches.ru.conf.example) terminates TLS and forwards raw TCP to local proxy ports.
