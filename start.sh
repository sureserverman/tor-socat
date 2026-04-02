#!/bin/sh

BRIDGE1="${BRIDGE1:-obfs4 REDACTED-IP-2:8088 REDACTED-FPR-2 cert=REDACTED-CERT-2 iat-mode=0}"
BRIDGE2="${BRIDGE2:-obfs4 107.4.186.44:8214 1B6CB332A1954FDF740DE75E8AFAEB41469D5821 cert=voxt3pqV5YWgLcqoHt+HDBieiUVzgxx3MOVHHa3RUPqlmsMGzSMu0Mv3AcY3XkQK9UirFw iat-mode=0}"

TOR_LOG=/var/log/tor.log

tor Bridge "$BRIDGE1" Bridge "$BRIDGE2" | tee "$TOR_LOG" &

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
PRIMARY="socat -d -T3 TCP4-LISTEN:${PORT},reuseaddr,fork SOCKS4A:127.0.0.1:dns4torpnlfs2ifuz2s2yf3fc7rdmsbhm6rw75euj35pac6ap25zgqad.onion:${PORT},socksport=9050,connect-timeout=2"
BACKUP="socat -d -T3 TCP4-LISTEN:${PORT},reuseaddr,fork SOCKS4A:127.0.0.1:1.1.1.1:${PORT},socksport=9050,connect-timeout=2"
FALLBACK="socat -d -T3 TCP4-LISTEN:${PORT},reuseaddr,fork SOCKS4A:127.0.0.1:9.9.9.9:${PORT},socksport=9050,connect-timeout=2"

CHECK_INTERVAL=30
FAIL_THRESHOLD=3
PROMOTE_INTERVAL=300

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
    seconds_on_tier=0

    while true; do
        sleep "$CHECK_INTERVAL"
        seconds_on_tier=$((seconds_on_tier + CHECK_INTERVAL))

        # Check if socat process is alive
        if ! kill -0 "$SOCAT_PID" 2>/dev/null; then
            echo "$label socat process died."
            if [ -n "$next_cmd" ]; then
                run_tier "$next_label" "$next_cmd" "$fallback_label" "$fallback_cmd" "" ""
            elif [ -n "$fallback_cmd" ]; then
                exec $fallback_cmd
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
                elif [ -n "$fallback_cmd" ]; then
                    exec $fallback_cmd
                fi
                return
            fi
        else
            fail_count=0
        fi
    done
}

run_tier "PRIMARY" "$PRIMARY" "BACKUP" "$BACKUP" "FALLBACK" "$FALLBACK"
