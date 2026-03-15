#!/bin/bash
set -e

XRAY_CONFIG="${XRAY_CONFIG:-/etc/xray/conf.json}"
XRAY_RUNTIME_CONFIG="/tmp/xray.runtime.json"
PROXY_PORT="${PROXY_PORT:-3128}"
SOCKS_PORT="${SOCKS_PORT:-1080}"
METRICS_PORT="${METRICS_PORT:-}"
DIRECT_DOMAINS="${DIRECT_DOMAINS:-}"

cleanup() {
    echo "[entrypoint] Shutting down..."
    kill "$XRAY_PID" 2>/dev/null || true
    wait
    exit 0
}
trap cleanup SIGTERM SIGINT

prepare_xray_config() {
    echo "[entrypoint] Preparing runtime Xray config..."

    local users_raw="${PROXY_USERS:-}"
    if [ -z "$users_raw" ] && [ -n "${PROXY_USER:-}" ] && [ -n "${PROXY_PASS:-}" ]; then
        users_raw="${PROXY_USER}:${PROXY_PASS}"
    fi

    local auth_mode="noauth"
    local accounts_json='[]'

    if [ -n "$users_raw" ]; then
        auth_mode="password"
        users_raw="${users_raw//;/,}"
        accounts_json=$(printf '%s' "$users_raw" | jq -R '
            split(",")
            | map(gsub("^\\s+|\\s+$"; ""))
            | map(select(length > 0) | split(":"))
            | map({
                user: (.[0] | gsub("^\\s+|\\s+$"; "") | gsub("\\r$"; "")),
                pass: (.[1:] | join(":") | gsub("^\\s+|\\s+$"; "") | gsub("\\r$"; ""))
            })
            | map(select(.user != "" and .pass != ""))
        ')

        if [ "$(printf '%s' "$accounts_json" | jq 'length')" -eq 0 ]; then
            echo "[entrypoint] ERROR: Auth is enabled but no valid users parsed from PROXY_USERS/PROXY_USER+PROXY_PASS."
            exit 1
        fi
        echo "[entrypoint] Auth users: $(printf '%s' "$accounts_json" | jq -r '[.[].user] | join(", ")')"
    else
        echo "[entrypoint] No auth configured, proxy is open."
    fi

    local metrics_port="${METRICS_PORT:-0}"
    if ! [[ "$metrics_port" =~ ^[0-9]+$ ]]; then
        metrics_port=0
    fi

    local direct_domains_raw="${DIRECT_DOMAINS:-}"
    local direct_domains_json='[]'
    if [ -n "$direct_domains_raw" ]; then
        direct_domains_raw="${direct_domains_raw//;/,}"
        direct_domains_json=$(printf '%s' "$direct_domains_raw" | jq -R '
            split(",")
            | map(gsub("^\\s+|\\s+$"; ""))
            | map(select(length > 0))
            | map(
                if startswith("*.") then .[2:]
                elif startswith(".") then .[1:]
                else .
                end
            )
            | map(ascii_downcase)
            | map(select(test("^[a-z0-9.-]+$")))
            | map("domain:" + .)
            | unique
        ')

        if [ "$(printf '%s' "$direct_domains_json" | jq 'length')" -eq 0 ]; then
            echo "[entrypoint] ERROR: DIRECT_DOMAINS is set but no valid domains parsed."
            exit 1
        fi
        echo "[entrypoint] Extra direct domains: $(printf '%s' "$direct_domains_json" | jq -r 'map(sub("^domain:"; "")) | join(", ")')"
    fi

    jq \
        --argjson proxyPort "$PROXY_PORT" \
        --argjson socksPort "$SOCKS_PORT" \
        --arg authMode "$auth_mode" \
        --argjson accounts "$accounts_json" \
        --argjson directDomains "$direct_domains_json" \
        --argjson metricsPort "$metrics_port" '

        # Strip managed inbounds and any untagged leftovers
        .inbounds = (
            ((.inbounds // []) | map(select(
                (.tag // "") != "http-in" and
                (.tag // "") != "socks-in" and
                (.tag // "") != ""
            )))
            + [
                {
                    "tag": "http-in",
                    "listen": "0.0.0.0",
                    "port": $proxyPort,
                    "protocol": "http",
                    "settings": (
                        if $authMode == "password"
                        then {"accounts": $accounts}
                        else {}
                        end
                    ),
                    "sniffing": {
                        "enabled": true,
                        "destOverride": ["http", "tls"]
                    }
                },
                {
                    "tag": "socks-in",
                    "listen": "0.0.0.0",
                    "port": $socksPort,
                    "protocol": "socks",
                    "settings": (
                        {"udp": true, "auth": $authMode}
                        + (if $authMode == "password" then {"accounts": $accounts} else {} end)
                    ),
                    "sniffing": {
                        "enabled": true,
                        "destOverride": ["http", "tls"]
                    }
                }
            ]
        )

        # Tag first outbound as "proxy" if not tagged
        | .outbounds = (
            (.outbounds // [])
            | if length > 0 and ((.[0].tag // "") == "")
              then [.[0] + {"tag": "proxy"}] + .[1:]
              else . end
        )

        # Add "direct" outbound (strip existing to avoid duplicates)
        | .outbounds = (
            [.outbounds[] | select((.tag // "") != "direct")]
            + [{"tag": "direct", "protocol": "freedom", "settings": {}}]
        )

        # Routing: private networks, Russian and .local domains bypass proxy
        | .routing = {
            "domainStrategy": "IPIfNonMatch",
            "rules": [
                {"type": "field", "domain": (["geosite:private", "geosite:category-ru", "domain:local"] + $directDomains), "outboundTag": "direct"},
                {"type": "field", "ip": ["geoip:private", "geoip:ru"], "outboundTag": "direct"}
            ]
        }

        # Metrics: stats collection + HTTP endpoint
        | if $metricsPort > 0 then
            .stats = {}
            | .metrics = {
                "tag": "metrics",
                "listen": ("127.0.0.1:" + ($metricsPort | tostring))
            }
            | .policy = ((.policy // {}) * {
                "system": {
                    "statsInboundUplink": true,
                    "statsInboundDownlink": true,
                    "statsOutboundUplink": true,
                    "statsOutboundDownlink": true
                }
            })
          else del(.stats, .metrics)
          end
    ' "$XRAY_CONFIG" > "$XRAY_RUNTIME_CONFIG"

    echo "[entrypoint] Routing: private networks, RU and .local domains bypass proxy (direct)."

    if [ "$metrics_port" -gt 0 ] 2>/dev/null; then
        echo "[entrypoint] Metrics enabled on port ${metrics_port} (http://127.0.0.1:${metrics_port}/debug/vars)"
    fi
}

prepare_xray_config

echo "[entrypoint] Starting Xray..."
xray run -config "$XRAY_RUNTIME_CONFIG" &
XRAY_PID=$!

echo "[entrypoint] Waiting for HTTP proxy on port ${PROXY_PORT} and SOCKS proxy on port ${SOCKS_PORT}..."
ready=false
for i in $(seq 1 30); do
    if ! kill -0 "$XRAY_PID" 2>/dev/null; then
        echo "[entrypoint] ERROR: Xray process died. Check your config."
        exit 1
    fi

    if nc -z 127.0.0.1 "${PROXY_PORT}" 2>/dev/null && nc -z 127.0.0.1 "${SOCKS_PORT}" 2>/dev/null; then
        echo "[entrypoint] Xray is ready (HTTP:${PROXY_PORT}, SOCKS:${SOCKS_PORT})."
        ready=true
        break
    fi
    echo "[entrypoint] Waiting... (${i}/30)"
    sleep 1
done

if ! $ready; then
    echo "[entrypoint] ERROR: Xray readiness check timed out."
    exit 1
fi

wait "$XRAY_PID"
