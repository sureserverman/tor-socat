FROM alpine:latest

RUN apk -U --no-cache upgrade
RUN apk add --no-cache tor
RUN apk --no-cache add socat
RUN apk add --no-cache bind-tools
RUN apk add --no-cache tini
RUN apk add --no-cache lyrebird 
ADD torrc /etc/tor/
ADD start.sh /bin/
ENV BRIDGE1=''
ENV BRIDGE2=''
ENV PORT=853
ENV BRIDGED="N"
HEALTHCHECK CMD dig +short +tls +norecurse +retry=0 @127.0.0.1 google.com || kill 1
ENTRYPOINT ["tini", "--"]
CMD ["/bin/start.sh"]