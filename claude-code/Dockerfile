# Stage 1 (builder): download and install Claude Code using curl.
# curl is intentionally absent from the runtime stage to reduce the attack
# surface available to prompt-injected code attempting data exfiltration.
FROM node:20-slim AS builder

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        curl ca-certificates \
    && rm -rf /var/lib/apt/lists/*

USER node
ENV PATH="/home/node/.local/bin:${PATH}"
RUN curl -fsSL https://claude.ai/install.sh | bash

# Stage 2 (runtime): lean image with only what Claude Code needs at runtime.
FROM node:20-slim

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        git ca-certificates \
        openssh-client \
        jq less vim-tiny \
    && rm -rf /var/lib/apt/lists/*

COPY banner.sh /usr/local/bin/banner.sh
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/banner.sh /usr/local/bin/entrypoint.sh

USER node
ENV PATH="/home/node/.local/bin:${PATH}"
COPY --from=builder /home/node/.local /home/node/.local
WORKDIR /home/node/workspace

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
