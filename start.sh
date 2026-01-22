#!/bin/sh

BRIDGE_URL="https://bridges.torproject.org/bridges?transport=obfs4"
BRIDGE_COUNT="${BRIDGE_COUNT:-2}"

fetch_bridges() {
  curl -fsSL "https://bridges.torproject.org/bridges?transport=obfs4" \
    | sed -E 's/<br[[:space:]]*\/?>/\n/gI' \
    | sed -E 's/<[^>]+>//g' \
    | sed -E 's/&#43;/+/g; s/&amp;/\&/g; s/&#x2[Bb];/+/g' \
    | awk '
        /^[[:space:]]*obfs4 / {
          gsub(/^[[:space:]]+/, "");
          gsub(/[[:space:]]+$/, "");
          print
        }
      ' \
    | head -n "${BRIDGE_COUNT:-2}"
}

BRIDGES="$(fetch_bridges || true)"

if [ -z "${BRIDGES}" ]; then
  echo "ERROR: could not fetch obfs4 bridges from $BRIDGE_URL"
  exit 1
fi
BRIDGE1="$(echo "${BRIDGES}" | sed -n '1p')"
BRIDGE2="$(echo "${BRIDGES}" | sed -n '2p')"

tor Bridge "$BRIDGE1" Bridge "$BRIDGE2" &

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