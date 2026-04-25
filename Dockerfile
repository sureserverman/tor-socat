FROM alpine:3.21.3

LABEL org.opencontainers.image.source="https://github.com/sureserverman/tor-socat"

SHELL ["/bin/sh", "-o", "pipefail", "-c"]

# HTTPS-only apk repositories
RUN echo "https://alpine.global.ssl.fastly.net/alpine/v$(cut -d . -f 1,2 < /etc/alpine-release)/main" > /etc/apk/repositories \
    && echo "https://alpine.global.ssl.fastly.net/alpine/v$(cut -d . -f 1,2 < /etc/alpine-release)/community" >> /etc/apk/repositories

ENV APP_USER=app
ENV APP_DIR="/$APP_USER"
ENV DATA_DIR="$APP_DIR/data"
ENV CONF_DIR="$APP_DIR/conf"

# Edge-community release pin: bump alongside the alpine major version above.
# lyrebird is only available from edge/community; pinning the version makes
# rebuilds reproducible regardless of edge package churn.
ARG LYREBIRD_VERSION=0.8.1-r4

RUN apk add --no-cache ca-certificates

# App user and directories. tor's DataDirectory lives under $DATA_DIR so the
# unprivileged app user owns it.
RUN adduser -s /bin/true -u 1000 -D -h $APP_DIR $APP_USER \
    && mkdir "$DATA_DIR" "$CONF_DIR" "$DATA_DIR/tor" \
    && chown -R "$APP_USER" "$APP_DIR" "$CONF_DIR" "$DATA_DIR" \
    && chmod 700 "$APP_DIR" "$DATA_DIR" "$CONF_DIR"

# Hardening (mirrors ironpeakservices/iron-alpine)
RUN rm -fr /var/spool/cron /etc/crontabs /etc/periodic \
    && find /sbin /usr/sbin ! -type d -a ! -name apk -a ! -name ln -delete \
    && find / -xdev -type d -perm +0002 -exec chmod o-w {} + \
    && find / -xdev -type f -perm +0002 -exec chmod o-w {} + \
    && chmod 777 /tmp/ && chown $APP_USER:root /tmp/ \
    && sed -i -r "/^($APP_USER|root|nobody)/!d" /etc/group \
    && sed -i -r "/^($APP_USER|root|nobody)/!d" /etc/passwd \
    && sed -i -r 's#^(.*):[^:]*$#\1:/sbin/nologin#' /etc/passwd \
    && { while IFS=: read -r username _; do passwd -l "$username"; done < /etc/passwd || true; } \
    && find /bin /etc /lib /sbin /usr -xdev -type f -regex '.*-$' -exec rm -f {} + \
    && find /bin /etc /lib /sbin /usr -xdev -type d -exec chown root:root {} \; -exec chmod 0755 {} \; \
    && find /bin /etc /lib /sbin /usr -xdev -type f -a \( -perm +4000 -o -perm +2000 \) -delete \
    && find /bin /etc /lib /sbin /usr -xdev \( \
         -iname hexdump -o -iname chgrp -o -iname ln -o -iname od -o \
         -iname strings -o -iname su -o -iname sudo \) -delete \
    && rm -fr /etc/init.d /lib/rc /etc/conf.d /etc/inittab /etc/runlevels /etc/rc.conf /etc/logrotate.d \
    && rm -fr /etc/sysctl* /etc/modprobe.d /etc/modules /etc/mdev.conf /etc/acpi \
    && rm -fr /root \
    && rm -f /etc/fstab \
    && find /bin /etc /lib /sbin /usr -xdev -type l -exec test ! -e {} \; -delete

COPY post-install.sh $APP_DIR/
RUN chmod 500 $APP_DIR/post-install.sh

WORKDIR $APP_DIR

# --- Application layer ---
# socat needs CAP_NET_BIND_SERVICE to bind PORT=853; libcap is installed
# temporarily for setcap and removed before post-install runs.
RUN apk -U --no-cache upgrade \
    && apk add --no-cache tor socat bind-tools tini libcap \
    && apk add --no-cache "lyrebird=${LYREBIRD_VERSION}" \
        --repository=https://dl-cdn.alpinelinux.org/alpine/edge/community/ \
    && setcap 'cap_net_bind_service=+ep' /usr/bin/socat \
    && apk del libcap

COPY torrc /etc/tor/
COPY start.sh /bin/

ENV PORT=853
HEALTHCHECK CMD dig +short +tls +norecurse +retry=0 -p 853 @127.0.0.1 google.com || exit 1

# Remove apk and lock down app directory
RUN $APP_DIR/post-install.sh

USER app

ENTRYPOINT ["tini", "--"]
CMD ["/bin/start.sh"]
