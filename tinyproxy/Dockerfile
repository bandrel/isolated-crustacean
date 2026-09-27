FROM alpine:3.22

RUN apk add --no-cache tinyproxy \
    && mkdir -p /var/log/tinyproxy \
    && chown nobody:nogroup /var/log/tinyproxy \
    && mkdir -p /var/run/tinyproxy \
    && chown nobody:nogroup /var/run/tinyproxy

COPY tinyproxy.conf /etc/tinyproxy/tinyproxy.conf
COPY allowlist /etc/tinyproxy/allowlist

USER nobody

EXPOSE 8888

CMD ["tinyproxy", "-d", "-c", "/etc/tinyproxy/tinyproxy.conf"]
