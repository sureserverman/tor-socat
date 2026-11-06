#!/usr/bin/env bash
# Bridges mode tests: builds the image from this repo and runs start.sh with
# tests/fake-tor.sh bind-mounted over /usr/bin/tor, so no Tor network is used
# (every container runs with --network none). Each case prints PASS or FAIL;
# the script exits non-zero if any case fails, and always removes its
# containers.
#
#   bash tests/run.sh
#
# Podman must work from the calling shell (on the laptop: run it through
# systemd-run --user, see the task notes). LYREBIRD_VERSION, when set, is
# passed to the build (the Dockerfile pins a v3.24/community release, which
# the repository drops when it moves on).

set -u

cd "$(dirname "$0")/.." || exit 2

IMAGE=localhost/tor-socat:bridges-test
FAKE_TOR=$PWD/tests/fake-tor.sh
PREFIX=tor-socat-bridges-test-$$
# A syntactically valid obfs4 line (TEST-NET address; the fake tor never dials it).
BRIDGE_LINE='obfs4 192.0.2.1:443 0123456789ABCDEF0123456789ABCDEF01234567 cert=AAAAexampleCertAAAA iat-mode=0'
WAIT=30
TAB=$'\t'

CONTAINERS=()
FAILED=0

cleanup() {
    local c
    for c in "${CONTAINERS[@]}"; do
        podman rm -f -t 0 "$c" >/dev/null 2>&1 || true
    done
}
trap cleanup EXIT
trap 'exit 130' INT TERM

pass() { echo "PASS $1"; }
fail() {
    echo "FAIL $1: $2"
    FAILED=1
}

# start <name> [podman run options...]: a detached container of the test image.
start() {
    local name=$PREFIX-$1
    shift
    CONTAINERS+=("$name")
    podman run -d --name "$name" --network none \
        -v "$FAKE_TOR:/usr/bin/tor:ro" "$@" "$IMAGE" >/dev/null
}

logs() { podman logs "$PREFIX-$1" 2>&1; }
state() { podman inspect -f '{{.State.Status}}' "$PREFIX-$1" 2>/dev/null; }
exit_code() { podman inspect -f '{{.State.ExitCode}}' "$PREFIX-$1" 2>/dev/null; }
argv() { podman exec "$PREFIX-$1" cat /app/data/tor-argv 2>/dev/null; }
count() { grep -cF -- "$2" <<<"$1"; }

# wait_log <name> <fixed string> [n]: until the log holds the string n times
# (default 1). Fails at once if the container stops first.
wait_log() {
    local i=0 n=${3:-1}
    while [ "$i" -lt "$WAIT" ]; do
        [ "$(logs "$1" | grep -cF -- "$2")" -ge "$n" ] && return 0
        [ "$(state "$1")" = running ] || return 1
        sleep 1
        i=$((i + 1))
    done
    return 1
}

# wait_exit <name>: until the container has stopped.
wait_exit() {
    local i=0
    while [ "$i" -lt "$WAIT" ]; do
        case "$(state "$1")" in exited|stopped) return 0 ;; esac
        sleep 1
        i=$((i + 1))
    done
    return 1
}

# has_bridge_arg <argv line>: a Bridge argument survived.
has_bridge_arg() { grep -Eq '(^| )Bridge ' <<<"$1"; }

# wait_ack <name> <request id>: until the acknowledgement names the request.
wait_ack() {
    local i=0
    while [ "$i" -lt "$WAIT" ]; do
        podman exec "$PREFIX-$1" cat /app/data/control/tor-restart-ack 2>/dev/null \
            | grep -qx "request_id${TAB}$2" && return 0
        sleep 1
        i=$((i + 1))
    done
    return 1
}

# request_restart <name> <id>: the way nice-dns asks (lib/recovery.sh): as the
# image user, a temp file in the control directory, then mv.
request_restart() {
    podman exec "$PREFIX-$1" sh -c \
        'printf "%s\n" "$1" >"$2/tor-restart-request.tmp" && mv "$2/tor-restart-request.tmp" "$2/tor-restart-request"' \
        sh "$2" /app/data/control
}

echo "Building $IMAGE..."
BUILD_ARGS=()
[ -n "${LYREBIRD_VERSION:-}" ] && BUILD_ARGS+=(--build-arg "LYREBIRD_VERSION=$LYREBIRD_VERSION")
if ! podman build -q "${BUILD_ARGS[@]}" -t "$IMAGE" . >/dev/null; then
    echo "FAIL build: podman build failed"
    exit 1
fi

# 1. off without bridges: tor runs direct.
c=off-direct
start "$c" -e TOR_BRIDGES=off
if ! wait_log "$c" "direct (no bridges)"; then
    fail "$c" "no 'direct (no bridges)' spawn line; state=$(state "$c") log: $(logs "$c" | tail -n 5)"
else
    a=$(argv "$c")
    if ! grep -q 'UseBridges 0' <<<"$a"; then
        fail "$c" "argv lacks 'UseBridges 0': $a"
    elif has_bridge_arg "$a"; then
        fail "$c" "a Bridge argument survived: $a"
    else
        pass "$c"
    fi
fi

# 2. TOR_BRIDGES unset, no BRIDGE1: refuses as before.
c=unset-no-bridges
start "$c"
if ! wait_exit "$c"; then
    fail "$c" "still $(state "$c") after ${WAIT}s"
elif [ "$(exit_code "$c")" = 0 ]; then
    fail "$c" "exited 0"
elif ! logs "$c" | grep -qF 'REFUSING to launch tor on invalid/empty bridges'; then
    fail "$c" "no refusal message: $(logs "$c" | tail -n 5)"
else
    pass "$c"
fi

# 3. Any other value: exit 1 before any other work.
c=invalid-value
start "$c" -e TOR_BRIDGES=maybe -e "BRIDGE1=$BRIDGE_LINE"
if ! wait_exit "$c"; then
    fail "$c" "still $(state "$c") after ${WAIT}s"
elif [ "$(exit_code "$c")" != 1 ]; then
    fail "$c" "exit code $(exit_code "$c"), want 1"
elif ! logs "$c" | grep -qF 'TOR_BRIDGES must be on or off'; then
    fail "$c" "no 'TOR_BRIDGES must be on or off': $(logs "$c" | tail -n 5)"
elif logs "$c" | grep -qF 'tor-supervisor:'; then
    fail "$c" "the supervisor did work first: $(logs "$c" | tail -n 5)"
else
    pass "$c"
fi

# 4. off with BRIDGE1 and BRIDGE_EVAL set: each ignored once, still direct.
c=off-ignores-bridges
start "$c" -e TOR_BRIDGES=off -e "BRIDGE1=$BRIDGE_LINE" -e BRIDGE_EVAL=auto
if ! wait_log "$c" "direct (no bridges)"; then
    fail "$c" "no 'direct (no bridges)' spawn line; state=$(state "$c") log: $(logs "$c" | tail -n 5)"
else
    l=$(logs "$c")
    a=$(argv "$c")
    if [ "$(count "$l" 'tor-supervisor: bridges off: BRIDGE1..16 ignored')" != 1 ]; then
        fail "$c" "BRIDGE1..16 ignored line count $(count "$l" 'tor-supervisor: bridges off: BRIDGE1..16 ignored'), want 1"
    elif [ "$(count "$l" 'tor-supervisor: bridges off: BRIDGE_EVAL=auto ignored')" != 1 ]; then
        fail "$c" "BRIDGE_EVAL ignored line count $(count "$l" 'tor-supervisor: bridges off: BRIDGE_EVAL=auto ignored'), want 1"
    elif ! grep -q 'UseBridges 0' <<<"$a"; then
        fail "$c" "argv lacks 'UseBridges 0': $a"
    elif has_bridge_arg "$a"; then
        fail "$c" "a Bridge argument survived: $a"
    else
        pass "$c"
    fi
fi

# 5. The acknowledged restart contract in off mode (case 4's container, so
# the ignored lines are also checked across a respawn).
c=off-ignores-bridges
n=off-restart
if ! wait_log "$c" "Tor bootstrapped successfully."; then
    fail "$n" "the supervisor never reported readiness: $(logs "$c" | tail -n 5)"
elif ! request_restart "$c" bridges-off-1; then
    fail "$n" "could not write the restart request"
elif ! wait_ack "$c" bridges-off-1; then
    fail "$n" "no acknowledgement for bridges-off-1; log: $(logs "$c" | tail -n 5)"
else
    ack=$(podman exec "$PREFIX-$c" cat /app/data/control/tor-restart-ack 2>/dev/null)
    a=$(argv "$c")
    second=$(sed -n 2p <<<"$a")
    l=$(logs "$c")
    if ! grep -qx "status${TAB}respawned" <<<"$ack"; then
        fail "$n" "acknowledgement is not respawned: $ack"
    elif [ "$(grep -c . <<<"$a")" != 2 ]; then
        fail "$n" "want 2 tor spawns, argv: $a"
    elif ! grep -q 'UseBridges 0' <<<"$second" || has_bridge_arg "$second"; then
        fail "$n" "the respawn is not direct: $second"
    elif [ "$(count "$l" 'direct (no bridges)')" != 2 ]; then
        fail "$n" "want 2 'direct (no bridges)' spawn lines: $(grep -F spawned <<<"$l")"
    elif [ "$(count "$l" 'BRIDGE1..16 ignored')" != 1 ] || [ "$(count "$l" 'BRIDGE_EVAL=auto ignored')" != 1 ]; then
        fail "$n" "an ignored line repeated on the respawn"
    elif [ "$(state "$c")" != running ]; then
        fail "$n" "the container stopped: $(state "$c")"
    else
        pass "$n"
    fi
fi

# 6. on with a bridge: unchanged, Bridge arguments and no UseBridges 0.
c=on-bridges
start "$c" -e TOR_BRIDGES=on -e "BRIDGE1=$BRIDGE_LINE"
if ! wait_log "$c" "with 1 bridge(s)"; then
    fail "$c" "no 'with 1 bridge(s)' spawn line; state=$(state "$c") log: $(logs "$c" | tail -n 5)"
else
    a=$(argv "$c")
    if ! has_bridge_arg "$a"; then
        fail "$c" "no Bridge argument: $a"
    elif grep -q 'UseBridges 0' <<<"$a"; then
        fail "$c" "argv has 'UseBridges 0': $a"
    else
        pass "$c"
    fi
fi

# 7. The restart contract in on mode still respawns over the bridges.
n=on-restart
if ! wait_log "$c" "Tor bootstrapped successfully."; then
    fail "$n" "the supervisor never reported readiness: $(logs "$c" | tail -n 5)"
elif ! request_restart "$c" bridges-on-1; then
    fail "$n" "could not write the restart request"
elif ! wait_ack "$c" bridges-on-1; then
    fail "$n" "no acknowledgement for bridges-on-1; log: $(logs "$c" | tail -n 5)"
else
    ack=$(podman exec "$PREFIX-$c" cat /app/data/control/tor-restart-ack 2>/dev/null)
    second=$(argv "$c" | sed -n 2p)
    if ! grep -qx "status${TAB}respawned" <<<"$ack"; then
        fail "$n" "acknowledgement is not respawned: $ack"
    elif ! has_bridge_arg "$second" || grep -q 'UseBridges 0' <<<"$second"; then
        fail "$n" "the respawn is not over the bridge: $second"
    else
        pass "$n"
    fi
fi

if [ "$FAILED" -ne 0 ]; then
    echo "RESULT: FAIL"
    exit 1
fi
echo "RESULT: PASS"
