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
BRIDGE_EVAL="${BRIDGE_EVAL:-off}"            # off (default): consume the host-selected bridges.env as-is.
                                             # Selection now runs HOST-SIDE (bridge-eval `manage` on a timer);
                                             # in-container eval (auto/moat/force) blocks startup ~150s and can
                                             # trip HealthStartPeriod into a restart loop. Opt in only for
                                             # debugging. Modes: off | auto | moat | force.
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

# Cap concurrent socat children to bound memory/FD use; tune via env if needed.
# SOCAT_MAX_CHILDREN bounds the legacy 853 listener, ROUTE_MAX_CHILDREN each
# identity-bound route listener.
SOCAT_MAX_CHILDREN="${SOCAT_MAX_CHILDREN:-256}"
ROUTE_MAX_CHILDREN="${ROUTE_MAX_CHILDREN:-128}"
for _v in "$SOCAT_MAX_CHILDREN" "$ROUTE_MAX_CHILDREN"; do
    case "$_v" in
        ''|*[!0-9]*) echo "ERROR: SOCAT_MAX_CHILDREN and ROUTE_MAX_CHILDREN must be numeric" >&2; exit 1 ;;
    esac
done

TOR_LOG=/tmp/tor.log
RESTART_FLAG=/tmp/tor-restart-flag
BRIDGES_REFRESH=/tmp/bridges-current.env
# Acknowledged restart contract (nice-dns ARCH-03 request_recovery), the same
# as tor-haproxy's:
#   host writes a request id to RESTART_REQUEST (atomically: tmp + mv);
#   the image restarts only tor and answers in RESTART_ACK, TSV lines
#     request_id <id>  status respawned|refused|rejected  generation <n>
#     tor_pid <pid>    utc <time>
#   GENERATION_FILE always holds the current generation and tor pid.
# An acknowledgement says tor was respawned, not that it bootstrapped:
# readiness is a separate, later observation. Touching RESTART_FLAG (the
# older interface) is acknowledged as request_id "legacy". If
# BRIDGES_REFRESH exists when tor is respawned, its bridges are used.
RESTART_REQUEST=/tmp/tor-restart-request
RESTART_PENDING=/tmp/tor-restart-pending
RESTART_ACK=/tmp/tor-restart-ack
GENERATION_FILE=/tmp/tor-generation
GENERATION=0

# write_kv <file> <request_id> <status> <generation> <tor_pid>: atomic TSV.
write_kv() {
    {
        [ -n "$2" ] && printf 'request_id\t%s\nstatus\t%s\n' "$2" "$3"
        printf 'generation\t%s\ntor_pid\t%s\nutc\t%s\n' "$4" "$5" "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    } > "$1.tmp" && mv "$1.tmp" "$1"
}

# gen_field <key>: a field of the current GENERATION_FILE (for the watcher,
# which runs in a subshell and cannot see GENERATION or TOR_PID).
gen_field() {
    awk -F '\t' -v k="$1" '$1 == k { print $2; exit }' "$GENERATION_FILE" 2>/dev/null
}

reload_bridges() {
    if [ -r "$BRIDGES_REFRESH" ]; then
        cp "$BRIDGES_REFRESH" "$SELECTED_ENV" 2>/dev/null || true
        echo "tor-supervisor: reloaded bridges from $BRIDGES_REFRESH"
    fi
}

# Launch tor with the selected bridges (1..N). With 3 link-disjoint guards,
# Tor's defaults (NumPrimaryGuards 3, ConfluxEnabled 1) give the 2-link Conflux
# pair on every onion-service circuit; with fewer, Conflux is disabled (warned
# above) but resolution still works. Returns 1 (tor not started) on invalid or
# empty bridges.
launch_tor() {
    reload_bridges
    if ! load_and_validate; then
        echo "tor-supervisor: REFUSING to launch tor on invalid/empty bridges" >&2
        return 1
    fi
    set --
    _n=1
    while [ "$_n" -le "$MAX_BRIDGE_SLOTS" ]; do
        eval "_b=\${BRIDGE${_n}:-}"
        [ -n "${_b:-}" ] && set -- "$@" Bridge "$_b"
        _n=$((_n + 1))
    done
    : > "$TOR_LOG"
    tor "$@" >"$TOR_LOG" 2>&1 &
    TOR_PID=$!
    GENERATION=$((GENERATION + 1))
    write_kv "$GENERATION_FILE" "" "" "$GENERATION" "$TOR_PID"
    echo "tor-supervisor: spawned tor pid=$TOR_PID generation=$GENERATION with $NBRIDGES bridge(s)"
}

# Wait for the most recent tor to reach Bootstrapped 100% (5 min cap).
# 0 bootstrapped, 1 tor exited first, 2 timed out (carry on).
wait_for_tor_bootstrap() {
    i=0
    while [ "$i" -lt 60 ]; do
        if grep -q "Bootstrapped 100%" "$TOR_LOG" 2>/dev/null; then
            echo "Tor bootstrapped successfully."
            return 0
        fi
        if ! kill -0 "$TOR_PID" 2>/dev/null; then
            echo "ERROR: tor exited before bootstrap." >&2
            cat "$TOR_LOG" >&2
            return 1
        fi
        sleep 5
        i=$((i + 1))
    done
    echo "WARNING: Tor did not bootstrap in time, starting socat anyway."
    return 2
}

# Every child, and each child's own socat, ends on shutdown: the legacy loop
# traps TERM to stop its socat before exiting.
cleanup() {
    for _p in "${TOR_PID:-}" "${ROUTE_ONION_PID:-}" "${ROUTE_CF_PID:-}" "${ROUTE_Q9_PID:-}" \
              "${LEGACY_PID:-}" "${WATCHER_PID:-}"; do
        [ -n "$_p" ] && kill -TERM "$_p" 2>/dev/null || true
    done
    wait 2>/dev/null || true
}
trap 'cleanup; exit 143' TERM INT

# Clear stale restart state so the watcher doesn't fire on a fresh start.
rm -f "$RESTART_FLAG" "$BRIDGES_REFRESH" "$RESTART_REQUEST" "$RESTART_PENDING" "$RESTART_ACK" "$GENERATION_FILE"

echo "Waiting for Tor to bootstrap..."
launch_tor || exit 1
wait_for_tor_bootstrap || [ "$?" -eq 2 ] || exit 1

ONION=dns4torpnlfs2ifuz2s2yf3fc7rdmsbhm6rw75euj35pac6ap25zgqad.onion
SOCKS_OPTS="socksport=9050,connect-timeout=2,so-rcvtimeo=20,so-sndtimeo=20"

# Identity-bound routes (nice-dns ARCH-04). Each listener carries streams
# through Tor to exactly one provider and never to another; choosing a route
# is the client's policy, and the client authenticates that provider's TLS
# name. Bound on every address so macOS reaches them on the container IP;
# nice-dns never publishes these ports.
#   18531 cloudflare-onion  18532 cloudflare-exit (1.1.1.1)  18533 quad9-exit (9.9.9.9)
ROUTE_LISTEN="reuseaddr,fork,max-children=${ROUTE_MAX_CHILDREN}"
socat -d -T3 "TCP4-LISTEN:18531,$ROUTE_LISTEN" "SOCKS4A:127.0.0.1:$ONION:853,$SOCKS_OPTS" &
ROUTE_ONION_PID=$!
socat -d -T3 "TCP4-LISTEN:18532,$ROUTE_LISTEN" "SOCKS4A:127.0.0.1:1.1.1.1:853,$SOCKS_OPTS" &
ROUTE_CF_PID=$!
socat -d -T3 "TCP4-LISTEN:18533,$ROUTE_LISTEN" "SOCKS4A:127.0.0.1:9.9.9.9:853,$SOCKS_OPTS" &
ROUTE_Q9_PID=$!

# Legacy DoT listener (:853), kept for compatibility: Cloudflare only, the
# .onion first and Cloudflare's Tor-exit DoT as backup. The former 9.9.9.9
# (Quad9) fallback is gone: a client authenticating a Cloudflare name must
# never have its stream handed to another provider (nice-dns ARCH-04).
# Clients that want Quad9 use the quad9-exit route.
LEGACY_LISTEN="reuseaddr,fork,max-children=${SOCAT_MAX_CHILDREN}"
PRIMARY="socat -d -T3 TCP4-LISTEN:853,${LEGACY_LISTEN} SOCKS4A:127.0.0.1:${ONION}:853,${SOCKS_OPTS}"
BACKUP="socat -d -T3 TCP4-LISTEN:853,${LEGACY_LISTEN} SOCKS4A:127.0.0.1:1.1.1.1:853,${SOCKS_OPTS}"

CHECK_INTERVAL="${LEGACY_CHECK_INTERVAL:-30}"
FAIL_THRESHOLD="${LEGACY_FAIL_THRESHOLD:-3}"
RETRY_DELAY="${LEGACY_RETRY_DELAY:-30}"

# nap <seconds>: an interruptible sleep, so the legacy loop's TERM trap runs
# at once instead of after the current sleep.
nap() {
    sleep "$1" &
    wait "$!" 2>/dev/null || true
}

run_tier() {
    local label="$1"
    local cmd="$2"
    local next_label="$3"
    local next_cmd="$4"

    echo "Starting $label..."
    $cmd &
    SOCAT_PID=$!
    fail_count=0

    while true; do
        nap "$CHECK_INTERVAL"

        if ! kill -0 "$SOCAT_PID" 2>/dev/null; then
            echo "$label socat process died."
            if [ -n "$next_cmd" ]; then
                run_tier "$next_label" "$next_cmd" "" ""
            fi
            return
        fi

        # An answer line is required: dig +tls exits 0 when the connection is
        # accepted and then dropped, so its exit status never failed and the
        # failover below never fired; dig +short also prints ";;" error lines
        # on stdout, so any output is not an answer either.
        if ! dig +short +tls +norecurse +retry=0 +time=5 -p 853 @127.0.0.1 google.com 2>/dev/null | grep -q '^[^;]'; then
            fail_count=$((fail_count + 1))
            echo "$label health check failed ($fail_count/$FAIL_THRESHOLD)"
            if [ "$fail_count" -ge "$FAIL_THRESHOLD" ]; then
                echo "$label exceeded failure threshold, switching..."
                # `|| true`: under set -e the killed socat's status (143)
                # from wait would end this loop instead of failing over.
                kill "$SOCAT_PID" 2>/dev/null || true
                wait "$SOCAT_PID" 2>/dev/null || true
                if [ -n "$next_cmd" ]; then
                    run_tier "$next_label" "$next_cmd" "" ""
                fi
                return
            fi
        else
            fail_count=0
        fi
    done
}

(
    trap '[ -n "${SOCAT_PID:-}" ] && kill -TERM "$SOCAT_PID" 2>/dev/null; exit 0' TERM INT
    while true; do
        run_tier "PRIMARY" "$PRIMARY" "BACKUP" "$BACKUP"
        echo "All tiers exhausted, retrying from PRIMARY in ${RETRY_DELAY}s..."
        nap "$RETRY_DELAY"
    done
) &
LEGACY_PID=$!

# Restart watcher: consumes a validated request (or the legacy flag) and
# stops tor; the main loop respawns it and acknowledges.
(
    while true; do
        sleep 5
        # A request is consumed only when no restart is in progress, so an
        # acknowledgement is never lost to a second request.
        if [ -f "$RESTART_REQUEST" ] && [ ! -f "$RESTART_FLAG" ]; then
            # Claim the request by rename before reading it: a request
            # written meanwhile lands as a new file and is not lost.
            _req=""
            if mv "$RESTART_REQUEST" "$RESTART_REQUEST.claimed" 2>/dev/null; then
                _req=$(head -n 1 "$RESTART_REQUEST.claimed" 2>/dev/null || true)
                rm -f "$RESTART_REQUEST.claimed"
            fi
            # "legacy" is reserved for the flag interface's acknowledgements.
            if [ "$_req" != legacy ] && printf '%s\n' "$_req" | grep -Eqx '[A-Za-z0-9._:-]{1,64}'; then
                printf '%s\n' "$_req" > "$RESTART_PENDING"
                echo "tor-supervisor: restart request $_req accepted"
                : > "$RESTART_FLAG"
            else
                echo "tor-supervisor: restart request rejected (invalid id)" >&2
                write_kv "$RESTART_ACK" invalid rejected "$(gen_field generation)" "$(gen_field tor_pid)"
            fi
        fi
        if [ -f "$RESTART_FLAG" ]; then
            echo "tor-supervisor: restart flag observed, sending SIGTERM to tor"
            pkill -TERM -x tor 2>/dev/null || true
            sleep 2
        fi
    done
) &
WATCHER_PID=$!

# Supervisory main loop. Poll rather than `wait -n`: busybox ash's `wait -n`
# returns only for a child that exits 0 (see tor-haproxy start.sh). ash reaps
# background children while `sleep` runs, so `kill -0` fails once one has
# exited, and `wait <pid>` then returns its recorded status. A planned tor
# exit is respawned and acknowledged; any other exit tears the container down.
while true; do
    while kill -0 "${TOR_PID:-0}" 2>/dev/null && kill -0 "$ROUTE_ONION_PID" 2>/dev/null \
        && kill -0 "$ROUTE_CF_PID" 2>/dev/null && kill -0 "$ROUTE_Q9_PID" 2>/dev/null \
        && kill -0 "$LEGACY_PID" 2>/dev/null && kill -0 "$WATCHER_PID" 2>/dev/null; do
        sleep 1
    done
    ec=0
    for _p in "${TOR_PID:-}" "$ROUTE_ONION_PID" "$ROUTE_CF_PID" "$ROUTE_Q9_PID" "$LEGACY_PID" "$WATCHER_PID"; do
        if [ -n "$_p" ] && ! kill -0 "$_p" 2>/dev/null; then
            wait "$_p" 2>/dev/null || ec=$?
            break
        fi
    done

    if ! kill -0 "${TOR_PID:-0}" 2>/dev/null; then
        if [ -f "$RESTART_FLAG" ]; then
            echo "tor-supervisor: tor exited as part of planned restart, respawning"
            _req=$(cat "$RESTART_PENDING" 2>/dev/null || true)
            [ -n "$_req" ] || _req=legacy
            rm -f "$RESTART_PENDING" "$RESTART_FLAG"
            if launch_tor; then
                write_kv "$RESTART_ACK" "$_req" respawned "$GENERATION" "$TOR_PID"
                wait_for_tor_bootstrap || true
                rm -f "$BRIDGES_REFRESH"
                continue
            fi
            write_kv "$RESTART_ACK" "$_req" refused "$GENERATION" 0
            echo "tor-supervisor: respawn refused (bad bridges); exiting" >&2
            cleanup
            exit 1
        fi
        echo "tor-supervisor: tor died unexpectedly (rc=$ec)" >&2
    else
        echo "tor-supervisor: a socat listener, the legacy loop or the restart watcher exited (rc=$ec); tearing down" >&2
    fi
    cleanup
    [ "$ec" -ne 0 ] || ec=1
    exit "$ec"
done
