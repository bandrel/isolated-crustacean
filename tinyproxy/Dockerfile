FROM alpine:3.21

RUN apk add --no-cache tinyproxy \
    && mkdir -p /var/log/tinyproxy \
    && chown nobody:nogroup /var/log/tinyproxy

COPY tinyproxy.conf /etc/tinyproxy/tinyproxy.conf
COPY allowlist /etc/tinyproxy/allowlist

EXPOSE 8888

CMD ["tinyproxy", "-d"]
