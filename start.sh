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
#
# Three working bridges are ideal: that's the minimum for Tor 0.4.8+ Conflux
# (≥3 distinct primary guards) on the onion-service traffic this image carries.
# The operator may pass a *pool* of up to 16 candidates (BRIDGE1..BRIDGE16);
# when the in-image evaluator (/bin/bridge-eval) is present it tests the pool
# for real obfs4 usability and keeps the fastest-handshaking ones. At least one
# usable bridge is required; fewer than 3 still runs but disables Conflux.

# obfs4 line shape: 'obfs4 host:port 40-hex-fingerprint cert=<base64> iat-mode=[012]'
bridge_re='^obfs4 [^[:space:]]+ [0-9A-Fa-f]{40} cert=[^[:space:]]+ iat-mode=[012]$'

MAX_BRIDGE_SLOTS=16
SELECTED_ENV=/tmp/bridges-selected.env       # canonical chosen-bridge set (BRIDGE1..k)
BRIDGE_EVAL="${BRIDGE_EVAL:-auto}"           # auto | off | moat | force
BRIDGE_COUNT="${BRIDGE_COUNT:-3}"
NBRIDGES=0

# collect_pool: emit every set BRIDGEn (n=1..MAX) as a bare obfs4 line.
collect_pool() {
    _n=1
    while [ "$_n" -le "$MAX_BRIDGE_SLOTS" ]; do
        eval "_v=\${BRIDGE${_n}:-}"
        [ -n "${_v:-}" ] && printf '%s\n' "$_v"
        _n=$((_n + 1))
    done
}

# select_bridges: write the chosen BRIDGE1..k to $SELECTED_ENV. Uses bridge-eval
# to test real usability when enabled (default: only when a >count pool, or an
# empty pool, is given — so exact-N deployments keep their existing fast path
# and pay no extra bootstrap). Falls back to a straight passthrough of the pool
# on any evaluator failure, so behaviour is never worse than before.
select_bridges() {
    _pool=/tmp/bridge-candidates.txt
    collect_pool > "$_pool"
    _pooln=$(grep -c . "$_pool" 2>/dev/null || true); _pooln=${_pooln:-0}

    _do_eval=0
    case "$BRIDGE_EVAL" in
        off)        _do_eval=0 ;;
        moat|force) _do_eval=1 ;;
        auto)       [ "$_pooln" -gt "$BRIDGE_COUNT" ] && _do_eval=1
                    [ "$_pooln" -eq 0 ] && _do_eval=1 ;;
    esac

    if [ "$_do_eval" = 1 ] && [ -x /bin/bridge-eval ]; then
        echo "tor-supervisor: selecting bridges via bridge-eval (pool=$_pooln, want=$BRIDGE_COUNT, mode=$BRIDGE_EVAL)..."
        if [ "$BRIDGE_EVAL" = moat ] || [ "$_pooln" -eq 0 ]; then
            /bin/bridge-eval -count "$BRIDGE_COUNT" -min 1 -out "$SELECTED_ENV" && return 0
        else
            /bin/bridge-eval -candidates "$_pool" -count "$BRIDGE_COUNT" -min 1 -out "$SELECTED_ENV" && return 0
        fi
        echo "tor-supervisor: bridge-eval failed; using operator-supplied bridges as-is" >&2
    fi

    : > "$SELECTED_ENV"
    _i=1
    while IFS= read -r _line; do
        [ -n "$_line" ] || continue
        printf 'BRIDGE%d=%s\n' "$_i" "$_line" >> "$SELECTED_ENV"
        _i=$((_i + 1))
    done < "$_pool"
}

# load_and_validate: reset BRIDGE slots, source $SELECTED_ENV, validate each,
# and set NBRIDGES. Returns non-zero if nothing usable.
load_and_validate() {
    _n=1
    while [ "$_n" -le "$MAX_BRIDGE_SLOTS" ]; do eval "unset BRIDGE${_n}"; _n=$((_n + 1)); done
    # Parse KEY=VALUE WITHOUT sourcing. The values are unquoted and contain
    # spaces (the --env-file / EnvironmentFile= format), so `. file` would try
    # to execute the value as a command (e.g. "1.2.3.4:80: not found", exit
    # 127). Assign each BRIDGEn literally from the line instead.
    if [ -r "$SELECTED_ENV" ]; then
        while IFS= read -r _ln; do
            case "$_ln" in
                BRIDGE[0-9]*=*)
                    _k=${_ln%%=*}
                    _v=${_ln#*=}
                    eval "$_k=\$_v"
                    ;;
            esac
        done < "$SELECTED_ENV"
    fi
    NBRIDGES=0
    _n=1
    while [ "$_n" -le "$MAX_BRIDGE_SLOTS" ]; do
        eval "_b=\${BRIDGE${_n}:-}"
        if [ -n "${_b:-}" ]; then
            if ! echo "$_b" | grep -Eq "$bridge_re"; then
                echo "ERROR: BRIDGE${_n} has invalid obfs4 syntax: $_b" >&2
                return 1
            fi
            NBRIDGES=$((NBRIDGES + 1))
        fi
        _n=$((_n + 1))
    done
    if [ "$NBRIDGES" -lt 1 ]; then
        echo "ERROR: no usable bridges (supply BRIDGE1.. at runtime, or enable bridge-eval)" >&2
        return 1
    fi
    [ "$NBRIDGES" -ge 3 ] || echo "tor-supervisor: WARNING: only $NBRIDGES bridge(s); Tor Conflux needs 3 — running without it." >&2
    return 0
}

select_bridges
load_and_validate || exit 1

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

# Launch tor with the selected bridges (1..N). With 3 link-disjoint guards,
# Tor's defaults (NumPrimaryGuards 3, ConfluxEnabled 1) give the 2-link Conflux
# pair on every onion-service circuit; with fewer, Conflux is disabled (warned
# above) but resolution still works.
set --
_n=1
while [ "$_n" -le "$MAX_BRIDGE_SLOTS" ]; do
    eval "_b=\${BRIDGE${_n}:-}"
    [ -n "${_b:-}" ] && set -- "$@" Bridge "$_b"
    _n=$((_n + 1))
done
tor "$@" >"$TOR_LOG" 2>&1 &
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
PRIMARY="socat -d -T3 TCP4-LISTEN:853,${LISTEN_OPTS} SOCKS4A:127.0.0.1:dns4torpnlfs2ifuz2s2yf3fc7rdmsbhm6rw75euj35pac6ap25zgqad.onion:853,socksport=9050,connect-timeout=2,so-rcvtimeo=20,so-sndtimeo=20"
BACKUP="socat -d -T3 TCP4-LISTEN:853,${LISTEN_OPTS} SOCKS4A:127.0.0.1:1.1.1.1:853,socksport=9050,connect-timeout=2,so-rcvtimeo=20,so-sndtimeo=20"
FALLBACK="socat -d -T3 TCP4-LISTEN:853,${LISTEN_OPTS} SOCKS4A:127.0.0.1:9.9.9.9:853,socksport=9050,connect-timeout=2,so-rcvtimeo=20,so-sndtimeo=20"

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

        if ! dig +short +tls +norecurse +retry=0 +time=5 -p 853 @127.0.0.1 google.com >/dev/null 2>&1; then
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
