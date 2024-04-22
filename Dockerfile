FROM alpine:latest

RUN apk -U --no-cache upgrade
RUN apk add --no-cache tor
RUN apk --no-cache add socat
RUN apk add lyrebird --repository=http://dl-cdn.alpinelinux.org/alpine/edge/testing/
ADD torrc /etc/tor/
ADD start.sh /bin/
ENV BRIDGE1='obfs4 217.182.78.247:52234 FF98116BB1530B18EDFBD0721FEF9874ADB1346A cert=tPXL+y4Wk+oFiqWdGtSAJ2BhcJBBcSD3gNn6dbgvmojNXy7DSeygNuHx4PYXvM9B+fTCPg iat-mode=0'
ENV BRIDGE2='obfs4 198.98.53.149:443 886CA31F71272FC8B3808C601FA3ABB8A2905DB4 cert=D+zypuFdMpP8riBUbInxIguzqClR0JKkP1DbkKz5es1+OP2Fao8jiXyM+B/+DYA2ZFy6UA iat-mode=0'
ENV PORT=853
CMD /bin/start.sh