FROM node:20-slim

RUN apt-get update \
    && apt-get install -y --no-install-recommends git ca-certificates curl \
    && rm -rf /var/lib/apt/lists/*

RUN npm install -g @anthropic-ai/claude-code

USER node
WORKDIR /home/node/workspace

ENTRYPOINT ["/bin/bash"]
