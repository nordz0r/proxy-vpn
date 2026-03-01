# Project Documentation Rules (Non-Obvious Only)

- Runtime Xray config file naming is inconsistent across files: compose mounts to `/etc/xray/conf.json` while repo example is [`conf/xray.json.example`](conf/xray.json.example); treat [`conf/xray.json`](conf/xray.json) as canonical local runtime filename.
- The repo has no dedicated docs for test/lint; operational truth is in [`Dockerfile`](Dockerfile), [`docker-compose.yml`](docker-compose.yml), and [`entrypoint.sh`](entrypoint.sh).
- `angie/` examples are not app config; they are external TLS stream termination that forwards TCP to local container ports (3128/1080), per [`angie/proxy.goldfinches.ru.conf.example`](angie/proxy.goldfinches.ru.conf.example).
- `.claude/settings.local.json` is tool-permission metadata, not runtime/project behavior spec.
