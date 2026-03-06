FROM node:20-slim

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        git ca-certificates curl \
        openssh-client \
        iputils-ping dnsutils net-tools netcat-openbsd iproute2 traceroute \
        jq less vim-tiny tree wget unzip file \
        procps htop \
    && rm -rf /var/lib/apt/lists/*

COPY banner.sh /usr/local/bin/banner.sh
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/banner.sh /usr/local/bin/entrypoint.sh

USER node
ENV PATH="/home/node/.local/bin:${PATH}"
RUN curl -fsSL https://claude.ai/install.sh | bash
WORKDIR /home/node/workspace

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
