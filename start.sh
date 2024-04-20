#!/bin/sh

tor Bridge "$bridge1" Bridge "$bridge2" &
socat TCP4-LISTEN:853,reuseaddr,fork SOCKS4A:127.0.0.1:dns4torpnlfs2ifuz2s2yf3fc7rdmsbhm6rw75euj35pac6ap25zgqad.onion:853,socksport=9050