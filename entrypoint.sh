#!/bin/bash
set -e

XRAY_CONFIG="${XRAY_CONFIG:-/etc/xray/conf.json}"
XRAY_RUNTIME_CONFIG="/tmp/xray.runtime.json"
PROXY_PORT="${PROXY_PORT:-3128}"
SOCKS_PORT="${SOCKS_PORT:-1080}"

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

    jq \
        --argjson proxyPort "$PROXY_PORT" \
        --argjson socksPort "$SOCKS_PORT" \
        --arg authMode "$auth_mode" \
        --argjson accounts "$accounts_json" '
        .inbounds = (
            ((.inbounds // []) | map(select((.tag // "") != "http-in" and (.tag // "") != "socks-in")))
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
                    )
                },
                {
                    "tag": "socks-in",
                    "listen": "0.0.0.0",
                    "port": $socksPort,
                    "protocol": "socks",
                    "settings": (
                        {"udp": true, "auth": $authMode}
                        + (if $authMode == "password" then {"accounts": $accounts} else {} end)
                    )
                }
            ]
        )
    ' "$XRAY_CONFIG" > "$XRAY_RUNTIME_CONFIG"
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
