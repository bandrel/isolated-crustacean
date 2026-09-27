# MCP fetch server (upstream reference server, stdio only) wrapped with
# supergateway as a stdio -> Streamable HTTP bridge.
#
# Upstream: https://github.com/modelcontextprotocol/servers/tree/main/src/fetch
# Package:  https://pypi.org/project/mcp-server-fetch/
# Bridge:   https://github.com/supercorp-ai/supergateway
#
# Outbound fetches go through tinyproxy (--proxy-url plus HTTP(S)_PROXY env
# from the template), so only allowlisted HTTPS hosts are reachable.
FROM node:24-bookworm-slim

ARG SERVER_VERSION=2026.8.18
# The server declares mcp<2,>=1.29.0; pin the SDK so rebuilds are reproducible.
ARG MCP_SDK_VERSION=1.30.0
ARG SUPERGATEWAY_VERSION=4.0.0

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        python3 python3-venv ca-certificates \
    && rm -rf /var/lib/apt/lists/* \
    && python3 -m venv /opt/venv \
    && /opt/venv/bin/pip install --no-cache-dir \
        "mcp-server-fetch==${SERVER_VERSION}" "mcp==${MCP_SDK_VERSION}" \
    && npm install -g --no-fund --no-audit "supergateway@${SUPERGATEWAY_VERSION}" \
    && npm cache clean --force

ENV PATH="/opt/venv/bin:${PATH}"

USER node
EXPOSE 3003

CMD ["supergateway", \
     "--stdio", "mcp-server-fetch --proxy-url http://tinyproxy:8888", \
     "--outputTransport", "streamableHttp", \
     "--port", "3003", \
     "--streamableHttpPath", "/mcp"]
