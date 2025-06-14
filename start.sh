#!/bin/sh
if [ $BRIDGED = "Y" ]; then
    tor UseBridges 1 Bridge "$BRIDGE1" Bridge "$BRIDGE2" &
else
    tor &
fi
while true; do
    socat TCP4-LISTEN:${PORT},reuseaddr,fork SOCKS4A:127.0.0.1:dns4torpnlfs2ifuz2s2yf3fc7rdmsbhm6rw75euj35pac6ap25zgqad.onion:${PORT},socksport=9050 && break
    socat TCP4-LISTEN:${PORT},reuseaddr,fork SOCKS4A:127.0.0.1:1.1.1.1:${PORT},socksport=9050 && break
    sleep 1
done