#!/bin/sh
# This script targets Alpine's busybox ash, not strict POSIX sh.
# shellcheck disable=SC3043  # 'local' is supported by busybox ash
set -eu

# Files we create (tor.log etc.) are owner-only — tor circuit info and
# bridge parameters are visible in tor's startup logs.
umask 077

# Bridges MUST be supplied by the operator at runtime — no defaults are
# baked into the image. The previous defaults leaked real obfs4 fingerprints
# and certificates into every published image layer.
: "${BRIDGE1:?BRIDGE1 must be set (e.g. -e BRIDGE1='obfs4 IP:PORT FPR cert=... iat-mode=0')}"
: "${BRIDGE2:?BRIDGE2 must be set (e.g. -e BRIDGE2='obfs4 IP:PORT FPR cert=... iat-mode=0')}"

bridge_re='^obfs4 [^[:space:]]+ [0-9A-Fa-f]{40} cert=[^[:space:]]+ iat-mode=[012]$'
echo "$BRIDGE1" | grep -Eq "$bridge_re" || { echo "ERROR: BRIDGE1 has invalid obfs4 syntax" >&2; exit 1; }
echo "$BRIDGE2" | grep -Eq "$bridge_re" || { echo "ERROR: BRIDGE2 has invalid obfs4 syntax" >&2; exit 1; }

case "${PORT:-}" in
    ''|*[!0-9]*) echo "ERROR: PORT must be numeric (got '${PORT:-}')" >&2; exit 1 ;;
esac
if [ "$PORT" -lt 1 ] || [ "$PORT" -gt 65535 ]; then
    echo "ERROR: PORT $PORT out of range 1-65535" >&2; exit 1
fi

# Cap concurrent socat children to bound memory/FD use; tune via env if needed.
SOCAT_MAX_CHILDREN="${SOCAT_MAX_CHILDREN:-256}"
case "$SOCAT_MAX_CHILDREN" in
    ''|*[!0-9]*) echo "ERROR: SOCAT_MAX_CHILDREN must be numeric" >&2; exit 1 ;;
esac

TOR_LOG=/tmp/tor.log

cleanup() {
    [ -n "${TOR_PID:-}" ] && kill -TERM "$TOR_PID" 2>/dev/null || true
    [ -n "${SOCAT_PID:-}" ] && kill -TERM "$SOCAT_PID" 2>/dev/null || true
    wait 2>/dev/null || true
}
trap cleanup TERM INT

tor Bridge "$BRIDGE1" Bridge "$BRIDGE2" >"$TOR_LOG" 2>&1 &
TOR_PID=$!

echo "Waiting for Tor to bootstrap..."
for i in $(seq 1 60); do
    if grep -q "Bootstrapped 100%" "$TOR_LOG" 2>/dev/null; then
        echo "Tor bootstrapped successfully."
        break
    fi
    if ! kill -0 "$TOR_PID" 2>/dev/null; then
        echo "ERROR: tor exited before bootstrap." >&2
        cat "$TOR_LOG" >&2
        exit 1
    fi
    if [ "$i" -eq 60 ]; then
        echo "WARNING: Tor did not bootstrap in time, starting socat anyway."
    fi
    sleep 5
done

# Socat commands for each failover tier. max-children caps fanout.
LISTEN_OPTS="reuseaddr,fork,max-children=${SOCAT_MAX_CHILDREN}"
PRIMARY="socat -d -T3 TCP4-LISTEN:${PORT},${LISTEN_OPTS} SOCKS4A:127.0.0.1:dns4torpnlfs2ifuz2s2yf3fc7rdmsbhm6rw75euj35pac6ap25zgqad.onion:${PORT},socksport=9050,connect-timeout=2,so-rcvtimeo=20,so-sndtimeo=20"
BACKUP="socat -d -T3 TCP4-LISTEN:${PORT},${LISTEN_OPTS} SOCKS4A:127.0.0.1:1.1.1.1:${PORT},socksport=9050,connect-timeout=2,so-rcvtimeo=20,so-sndtimeo=20"
FALLBACK="socat -d -T3 TCP4-LISTEN:${PORT},${LISTEN_OPTS} SOCKS4A:127.0.0.1:9.9.9.9:${PORT},socksport=9050,connect-timeout=2,so-rcvtimeo=20,so-sndtimeo=20"

CHECK_INTERVAL=30
FAIL_THRESHOLD=3

run_tier() {
    local label="$1"
    local cmd="$2"
    local next_label="$3"
    local next_cmd="$4"
    local fallback_label="$5"
    local fallback_cmd="$6"

    echo "Starting $label..."
    $cmd &
    SOCAT_PID=$!
    fail_count=0

    while true; do
        sleep "$CHECK_INTERVAL"

        if ! kill -0 "$SOCAT_PID" 2>/dev/null; then
            echo "$label socat process died."
            if [ -n "$next_cmd" ]; then
                run_tier "$next_label" "$next_cmd" "$fallback_label" "$fallback_cmd" "" ""
            fi
            return
        fi

        if ! dig +short +tls +norecurse +retry=0 +time=5 -p "${PORT}" @127.0.0.1 google.com >/dev/null 2>&1; then
            fail_count=$((fail_count + 1))
            echo "$label health check failed ($fail_count/$FAIL_THRESHOLD)"
            if [ "$fail_count" -ge "$FAIL_THRESHOLD" ]; then
                echo "$label exceeded failure threshold, switching..."
                kill "$SOCAT_PID" 2>/dev/null
                wait "$SOCAT_PID" 2>/dev/null
                if [ -n "$next_cmd" ]; then
                    run_tier "$next_label" "$next_cmd" "$fallback_label" "$fallback_cmd" "" ""
                fi
                return
            fi
        else
            fail_count=0
        fi
    done
}

while true; do
    run_tier "PRIMARY" "$PRIMARY" "BACKUP" "$BACKUP" "FALLBACK" "$FALLBACK"
    echo "All tiers exhausted, retrying from PRIMARY in 30s..."
    sleep 30
done
