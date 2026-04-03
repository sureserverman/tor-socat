#!/bin/sh

BRIDGE1="${BRIDGE1:-obfs4 109.110.170.208:29323 B93BAE4F17CEACD9E491920C5D283C0D4C3D6D3D cert=p+n8+6mTYmEMpFy+rDuQSyNy4X5pxarA9MzDknqk+WAukqpVa+uE0JJymTK8b8wSyK5pJw iat-mode=0}"
BRIDGE2="${BRIDGE2:-obfs4 84.22.109.77:8088 CEF423251E83353BD875CB5327B458F4C8751170 cert=HMCEwtFxM3OK68PTtZ0NXeYlabBRrRGF1IddIEfXk0J7Dmuq7Y2zgohCwjluwFE0AuH8Zg iat-mode=0}"

TOR_LOG=/var/log/tor.log

tor Bridge "$BRIDGE1" Bridge "$BRIDGE2" 2>&1 | tee "$TOR_LOG" &

# Wait for Tor to bootstrap (up to 5 minutes)
echo "Waiting for Tor to bootstrap..."
for i in $(seq 1 60); do
    if grep -q "Bootstrapped 100%" "$TOR_LOG" 2>/dev/null; then
        echo "Tor bootstrapped successfully."
        break
    fi
    if [ "$i" -eq 60 ]; then
        echo "WARNING: Tor did not bootstrap in time, starting socat anyway."
    fi
    sleep 5
done

# Socat commands for each failover tier
PRIMARY="socat -d -T3 TCP4-LISTEN:${PORT},reuseaddr,fork SOCKS4A:127.0.0.1:dns4torpnlfs2ifuz2s2yf3fc7rdmsbhm6rw75euj35pac6ap25zgqad.onion:${PORT},socksport=9050,connect-timeout=2,so-rcvtimeo=20,so-sndtimeo=20"
BACKUP="socat -d -T3 TCP4-LISTEN:${PORT},reuseaddr,fork SOCKS4A:127.0.0.1:1.1.1.1:${PORT},socksport=9050,connect-timeout=2,so-rcvtimeo=20,so-sndtimeo=20"
FALLBACK="socat -d -T3 TCP4-LISTEN:${PORT},reuseaddr,fork SOCKS4A:127.0.0.1:9.9.9.9:${PORT},socksport=9050,connect-timeout=2,so-rcvtimeo=20,so-sndtimeo=20"

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

        # Check if socat process is alive
        if ! kill -0 "$SOCAT_PID" 2>/dev/null; then
            echo "$label socat process died."
            if [ -n "$next_cmd" ]; then
                run_tier "$next_label" "$next_cmd" "$fallback_label" "$fallback_cmd" "" ""
            fi
            return
        fi

        # Health check: quick DNS probe
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

# Retry from PRIMARY if all tiers are exhausted (Tor circuits may be temporarily unstable)
while true; do
    run_tier "PRIMARY" "$PRIMARY" "BACKUP" "$BACKUP" "FALLBACK" "$FALLBACK"
    echo "All tiers exhausted, retrying from PRIMARY in 30s..."
    sleep 30
done
