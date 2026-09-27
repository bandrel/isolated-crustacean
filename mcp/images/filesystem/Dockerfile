# MCP filesystem server (upstream reference server, stdio only) wrapped with
# supergateway as a stdio -> Streamable HTTP bridge.
#
# Upstream: https://github.com/modelcontextprotocol/servers/tree/main/src/filesystem
# Package:  https://www.npmjs.com/package/@modelcontextprotocol/server-filesystem
# Bridge:   https://github.com/supercorp-ai/supergateway
#
# Everything is installed at build time (builds run with host networking);
# the runtime container has no internet access.
FROM node:24-bookworm-slim

ARG SERVER_VERSION=2026.8.31
ARG SUPERGATEWAY_VERSION=4.0.0

RUN npm install -g --no-fund --no-audit \
        "@modelcontextprotocol/server-filesystem@${SERVER_VERSION}" \
        "supergateway@${SUPERGATEWAY_VERSION}" \
    && npm cache clean --force

USER node
WORKDIR /data
EXPOSE 3000

CMD ["supergateway", \
     "--stdio", "mcp-server-filesystem /data", \
     "--outputTransport", "streamableHttp", \
     "--port", "3000", \
     "--streamableHttpPath", "/mcp"]
