#!/bin/sh
# Stand-in for /usr/bin/tor in tests/run.sh (bind-mounted read-only over it).
# Records each spawn's arguments as one line in /app/data/tor-argv (arguments
# joined by single spaces), reports bootstrap the way Tor does, and answers
# every SOCKS4A request on 127.0.0.1:9050 as granted, so start.sh's
# working-stream probe passes and the supervisor reaches its main loop.
# Exits on TERM (the restart watcher's pkill -x tor), taking its SOCKS stub
# with it so a respawn can bind 9050 again.

printf '%s\n' "$*" >> /app/data/tor-argv
echo "Bootstrapped 100% (done): Done"

# A SOCKS4 "request granted" reply: VN 0, CD 90, then port and address.
GRANT=/tmp/fake-tor-socks-grant
printf '\000\132\000\000\000\000\000\000' > "$GRANT"
socat TCP4-LISTEN:9050,bind=127.0.0.1,reuseaddr,fork SYSTEM:"cat $GRANT" 2>/dev/null &
SOCKS_PID=$!
SLEEP_PID=""

trap 'kill "$SOCKS_PID" $SLEEP_PID 2>/dev/null; exit 0' TERM INT
while :; do
    sleep 3600 &
    SLEEP_PID=$!
    wait "$SLEEP_PID"
done
