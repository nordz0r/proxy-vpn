# Project Documentation Rules (Non-Obvious Only)

- Canonical runtime input file is host [`conf/xray.json`](conf/xray.json), mounted as `/etc/xray/conf.json` by [`docker-compose.yml`](docker-compose.yml); [`conf/xray.json.example`](conf/xray.json.example) is a bootstrap template only.
- When explaining auth behavior, cite implementation in [`prepare_xray_config()`](entrypoint.sh:17), not only docs: separators `,`/`;` are both valid and `:` inside password is supported.
- For troubleshooting instructions, reference generated config [`/tmp/xray.runtime.json`](README.md:92); base config alone does not show runtime-injected inbounds.
- [`angie/proxy.goldfinches.ru.conf.example`](angie/proxy.goldfinches.ru.conf.example) documents external TLS termination (stream proxy), not container-internal Xray settings.
- No Claude/Cursor/Copilot rule files define project behavior; [`.claude/settings.local.json`](.claude/settings.local.json) is permissions metadata only.
