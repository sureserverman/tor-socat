#!/bin/sh
if [ $BRIDGED = "Y" ]; then
    tor UseBridges 1 Bridge "$BRIDGE1" Bridge "$BRIDGE2" &
else
    tor &
fi

TIMEOUT=5
monitor_and_failover() {
    local primary_cmd="$1"
    local backup_cmd="$2"
    
    # Start primary with output monitoring
    $primary_cmd 2>&1 | while IFS= read -r line; do
        echo "[PRIMARY] $line"
        
        # Check for failure patterns
        if echo "$line" | grep -E -q "(rejected|failed|refused|unreachable|timeout)"; then
            echo "Primary connection failed, starting backup..."
            pkill -f "$primary_cmd"
            exec $backup_cmd
        fi
    done
}

# Usage
monitor_and_failover \
    "socat -d -T3 TCP4-LISTEN:${PORT},reuseaddr,fork SOCKS4A:127.0.0.1:dns4torpnlfs2ifuz2s2yf3fc7rdmsbhm6rw75euj35pac6ap25zgqad.onion:${PORT},socksport=9050,connect-timeout=2" \
    "socat -d -T3 TCP4-LISTEN:${PORT},reuseaddr,fork SOCKS4A:127.0.0.1:1.1.1.1:${PORT},socksport=9050,connect-timeout=2"