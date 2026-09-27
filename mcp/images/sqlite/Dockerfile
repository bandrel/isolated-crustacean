# MCP sqlite server (reference server, now in servers-archived; stdio only)
# wrapped with supergateway as a stdio -> Streamable HTTP bridge.
#
# Upstream: https://github.com/modelcontextprotocol/servers-archived/tree/main/src/sqlite
# Package:  https://pypi.org/project/mcp-server-sqlite/
# Bridge:   https://github.com/supercorp-ai/supergateway
#
# The database lives on the shared workspace at /data/sqlite.db so Claude and
# the server see the same file.
FROM node:24-bookworm-slim

ARG SERVER_VERSION=2025.4.25
# The archived server declares mcp>=1.6.0 but breaks on mcp 1.30.0
# (Server.list_resources was removed). 1.29.0 is the newest SDK that works.
ARG MCP_SDK_VERSION=1.29.0
ARG SUPERGATEWAY_VERSION=4.0.0

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        python3 python3-venv ca-certificates \
    && rm -rf /var/lib/apt/lists/* \
    && python3 -m venv /opt/venv \
    && /opt/venv/bin/pip install --no-cache-dir \
        "mcp-server-sqlite==${SERVER_VERSION}" "mcp==${MCP_SDK_VERSION}" \
    && npm install -g --no-fund --no-audit "supergateway@${SUPERGATEWAY_VERSION}" \
    && npm cache clean --force

ENV PATH="/opt/venv/bin:${PATH}"

USER node
WORKDIR /data
EXPOSE 3005

CMD ["supergateway", \
     "--stdio", "mcp-server-sqlite --db-path /data/sqlite.db", \
     "--outputTransport", "streamableHttp", \
     "--port", "3005", \
     "--streamableHttpPath", "/mcp"]
