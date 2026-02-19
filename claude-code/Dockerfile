FROM node:20-slim

RUN apt-get update \
    && apt-get install -y --no-install-recommends git ca-certificates curl \
    && rm -rf /var/lib/apt/lists/*

RUN npm install -g @anthropic-ai/claude-code

COPY banner.sh /usr/local/bin/banner.sh
RUN chmod +x /usr/local/bin/banner.sh \
    && echo 'source /usr/local/bin/banner.sh' >> /etc/bash.bashrc

USER node
WORKDIR /home/node/workspace

ENTRYPOINT ["/bin/bash"]
