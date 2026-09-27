FROM alpine:3.22

RUN apk add --no-cache tinyproxy \
    && mkdir -p /var/log/tinyproxy \
    && chown nobody:nogroup /var/log/tinyproxy \
    && mkdir -p /var/run/tinyproxy \
    && chown nobody:nogroup /var/run/tinyproxy

# --chmod: tinyproxy runs as 'nobody' and exits 65 ("filter file: Permission
# denied") if the host copy of these files happens to be 0600.
COPY --chmod=0644 tinyproxy.conf /etc/tinyproxy/tinyproxy.conf
COPY --chmod=0644 allowlist /etc/tinyproxy/allowlist

USER nobody

EXPOSE 8888

CMD ["tinyproxy", "-d", "-c", "/etc/tinyproxy/tinyproxy.conf"]
