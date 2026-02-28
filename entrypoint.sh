#!/bin/bash
set -e

XRAY_CONFIG="${XRAY_CONFIG:-/etc/xray/conf.json}"
PROXY_PORT="${PROXY_PORT:-3128}"
SOCKS_PORT="${SOCKS_PORT:-1080}"
XRAY_SOCKS_PORT="${XRAY_SOCKS_PORT:-10808}"

cleanup() {
    echo "[entrypoint] Shutting down..."
    kill "$XRAY_PID" 2>/dev/null || true
    kill "$PROXY_PID" 2>/dev/null || true
    wait
    exit 0
}
trap cleanup SIGTERM SIGINT

# Generate 3proxy config
generate_3proxy_config() {
    cat > /etc/3proxy.cfg <<EOF
nscache 65536
nserver 8.8.8.8
nserver 1.1.1.1

log /dev/stdout
logformat "L%t %N:%p %E %C:%c %R:%r %O %I"

maxconn 200
timeouts 1 5 30 60 180 1800 15 60

parent 1000 socks5 127.0.0.1 ${XRAY_SOCKS_PORT}
EOF

    if [ -n "$PROXY_USER" ] && [ -n "$PROXY_PASS" ]; then
        cat >> /etc/3proxy.cfg <<EOF

auth strong
users ${PROXY_USER}:CL:${PROXY_PASS}

allow ${PROXY_USER}
EOF
    else
        cat >> /etc/3proxy.cfg <<EOF

auth none
allow *
EOF
    fi

    cat >> /etc/3proxy.cfg <<EOF

proxy -p${PROXY_PORT} -a
socks -p${SOCKS_PORT} -a
EOF
}

echo "[entrypoint] Generating 3proxy config..."
generate_3proxy_config

echo "[entrypoint] Starting Xray..."
xray run -config "$XRAY_CONFIG" &
XRAY_PID=$!

# Wait for Xray SOCKS5 port to open (nc -z checks TCP connect)
echo "[entrypoint] Waiting for Xray SOCKS5 on port ${XRAY_SOCKS_PORT}..."
for i in $(seq 1 30); do
    # Check process is still alive
    if ! kill -0 "$XRAY_PID" 2>/dev/null; then
        echo "[entrypoint] ERROR: Xray process died. Check your config."
        exit 1
    fi
    if nc -z 127.0.0.1 "${XRAY_SOCKS_PORT}" 2>/dev/null; then
        echo "[entrypoint] Xray is ready."
        break
    fi
    if [ "$i" -eq 30 ]; then
        echo "[entrypoint] WARNING: Xray readiness check timed out, starting 3proxy anyway."
    fi
    sleep 1
done

echo "[entrypoint] Starting 3proxy..."
3proxy /etc/3proxy.cfg &
PROXY_PID=$!

wait -n
cleanup
