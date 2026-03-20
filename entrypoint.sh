#!/bin/bash
set -e

XRAY_CONFIG="${XRAY_CONFIG:-/etc/xray/conf.json}"
XRAY_RUNTIME_CONFIG="/tmp/xray.runtime.json"
HTTP_PORT="${HTTP_PORT:-}"
SOCKS_PORT="${SOCKS_PORT:-}"
METRICS_PORT="${METRICS_PORT:-}"
DIRECT_DOMAINS="${DIRECT_DOMAINS:-}"
LOG_LEVEL="${LOG_LEVEL:-warning}"

# Validate: at least one inbound protocol must be enabled
if [ -z "$HTTP_PORT" ] && [ -z "$SOCKS_PORT" ]; then
    echo "[entrypoint] ERROR: No inbound protocols enabled. Set HTTP_PORT and/or SOCKS_PORT in .env"
    exit 1
fi

# Validate port values are numeric
for _var in HTTP_PORT SOCKS_PORT; do
    _val="${!_var}"
    if [ -n "$_val" ] && ! [[ "$_val" =~ ^[0-9]+$ ]]; then
        echo "[entrypoint] ERROR: ${_var}=${_val} is not a valid port number."
        exit 1
    fi
done

cleanup() {
    echo "[entrypoint] Shutting down..."
    kill "$XRAY_PID" 2>/dev/null || true
    wait
    exit 0
}
trap cleanup SIGTERM SIGINT

normalize_optional_env() {
    local value="${1:-}"

    value="${value//$'\r'/}"
    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"

    if [ "$value" = '""' ] || [ "$value" = "''" ]; then
        value=""
    fi

    printf '%s' "$value"
}

prepare_xray_config() {
    echo "[entrypoint] Preparing runtime Xray config..."

    local users_raw
    local proxy_user
    local proxy_pass

    users_raw="$(normalize_optional_env "${PROXY_USERS:-}")"
    proxy_user="$(normalize_optional_env "${PROXY_USER:-}")"
    proxy_pass="$(normalize_optional_env "${PROXY_PASS:-}")"

    if [ -z "$users_raw" ] && [ -n "$proxy_user" ] && [ -n "$proxy_pass" ]; then
        users_raw="${proxy_user}:${proxy_pass}"
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

    local proxy_port_num="${HTTP_PORT:-0}"
    local socks_port_num="${SOCKS_PORT:-0}"

    jq \
        --argjson proxyPort "$proxy_port_num" \
        --argjson socksPort "$socks_port_num" \
        --arg authMode "$auth_mode" \
        --argjson accounts "$accounts_json" \
        --argjson directDomains "$direct_domains_json" \
        --argjson metricsPort "$metrics_port" \
        --arg logLevel "$LOG_LEVEL" '

        # Logging: access log enabled at info/debug level
        .log = {
            "loglevel": $logLevel,
            "access": (if ($logLevel == "info" or $logLevel == "debug") then "" else "none" end),
            "error": ""
        }

        # Strip managed inbounds and any untagged leftovers
        |
        .inbounds = (
            ((.inbounds // []) | map(select(
                (.tag // "") != "http-in" and
                (.tag // "") != "socks-in" and
                (.tag // "") != ""
            )))
            + (if $proxyPort > 0 then [{
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
                }] else [] end)
            + (if $socksPort > 0 then [{
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
                }] else [] end)
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
    echo "[entrypoint] Log level: ${LOG_LEVEL}$([ "$LOG_LEVEL" = "info" ] || [ "$LOG_LEVEL" = "debug" ] && echo ' (access log enabled)' || echo '')"

    if [ "$metrics_port" -gt 0 ] 2>/dev/null; then
        echo "[entrypoint] Metrics enabled on port ${metrics_port} (http://127.0.0.1:${metrics_port}/debug/vars)"
    fi
}

prepare_xray_config

# Log enabled protocols
enabled=()
[ -n "$HTTP_PORT" ] && enabled+=("HTTP:${HTTP_PORT}")
[ -n "$SOCKS_PORT" ] && enabled+=("SOCKS:${SOCKS_PORT}")
echo "[entrypoint] Enabled protocols: ${enabled[*]}"

echo "[entrypoint] Starting Xray..."
xray run -config "$XRAY_RUNTIME_CONFIG" &
XRAY_PID=$!

echo "[entrypoint] Waiting for readiness..."
ready=false
for i in $(seq 1 30); do
    if ! kill -0 "$XRAY_PID" 2>/dev/null; then
        echo "[entrypoint] ERROR: Xray process died. Check your config."
        exit 1
    fi

    all_up=true
    [ -n "$HTTP_PORT" ] && ! nc -z 127.0.0.1 "${HTTP_PORT}" 2>/dev/null && all_up=false
    [ -n "$SOCKS_PORT" ] && ! nc -z 127.0.0.1 "${SOCKS_PORT}" 2>/dev/null && all_up=false

    if $all_up; then
        echo "[entrypoint] Xray is ready (${enabled[*]})."
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
