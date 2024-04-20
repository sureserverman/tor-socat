FROM alpine:latest

RUN apk -U --no-cache upgrade
RUN apk add --no-cache tor
RUN apk --no-cache add socat
ADD hosts /etc/
ENTRYPOINT ["tor & && socat TCP4-LISTEN:853,reuseaddr,fork SOCKS4A:127.0.0.1:dns4torpnlfs2ifuz2s2yf3fc7rdmsbhm6rw75euj35pac6ap25zgqad.onion:853,socksport=9150"]