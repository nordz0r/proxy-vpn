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
    cp "$XRAY_CONFIG" "$XRAY_RUNTIME_CONFIG"

    local users_raw="${PROXY_USERS:-}"
    if [ -z "$users_raw" ] && [ -n "${PROXY_USER:-}" ] && [ -n "${PROXY_PASS:-}" ]; then
        users_raw="${PROXY_USER}:${PROXY_PASS}"
    fi

    local auth_mode="noauth"
    local accounts_json='[]'

    if [ -n "$users_raw" ]; then
        auth_mode="password"
        accounts_json=$(printf '%s' "$users_raw" | jq -R '
            split(",")
            | map(select(length > 0) | split(":"))
            | map({user: .[0], pass: (.[1:] | join(":"))})
        ')
    fi

    jq \
        --argjson proxyPort "$PROXY_PORT" \
        --argjson socksPort "$SOCKS_PORT" \
        --arg authMode "$auth_mode" \
        --argjson accounts "$accounts_json" '
        .inbounds = [
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
    ' "$XRAY_RUNTIME_CONFIG" > "${XRAY_RUNTIME_CONFIG}.tmp"

    mv "${XRAY_RUNTIME_CONFIG}.tmp" "$XRAY_RUNTIME_CONFIG"
}

prepare_xray_config

echo "[entrypoint] Starting Xray..."
xray run -config "$XRAY_RUNTIME_CONFIG" &
XRAY_PID=$!

echo "[entrypoint] Waiting for HTTP proxy on port ${PROXY_PORT} and SOCKS proxy on port ${SOCKS_PORT}..."
for i in $(seq 1 30); do
    if ! kill -0 "$XRAY_PID" 2>/dev/null; then
        echo "[entrypoint] ERROR: Xray process died. Check your config."
        exit 1
    fi

    if nc -z 127.0.0.1 "${PROXY_PORT}" 2>/dev/null && nc -z 127.0.0.1 "${SOCKS_PORT}" 2>/dev/null; then
        echo "[entrypoint] Xray is ready (HTTP:${PROXY_PORT}, SOCKS:${SOCKS_PORT})."
        break
    fi

    if [ "$i" -eq 30 ]; then
        echo "[entrypoint] ERROR: Xray readiness check timed out."
        exit 1
    fi
    sleep 1
done

wait "$XRAY_PID"
