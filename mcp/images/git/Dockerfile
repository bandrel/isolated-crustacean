# MCP git server (upstream reference server, stdio only) wrapped with
# supergateway as a stdio -> Streamable HTTP bridge.
#
# Upstream: https://github.com/modelcontextprotocol/servers/tree/main/src/git
# Package:  https://pypi.org/project/mcp-server-git/
# Bridge:   https://github.com/supercorp-ai/supergateway
#
# node base (for supergateway) + Debian python3 (3.11) in a venv for the
# server. Everything is installed at build time; runtime has no internet.
FROM node:24-bookworm-slim

ARG SERVER_VERSION=2026.8.18
ARG SUPERGATEWAY_VERSION=4.0.0

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        git python3 python3-venv ca-certificates \
    && rm -rf /var/lib/apt/lists/* \
    && python3 -m venv /opt/venv \
    && /opt/venv/bin/pip install --no-cache-dir "mcp-server-git==${SERVER_VERSION}" \
    && npm install -g --no-fund --no-audit "supergateway@${SUPERGATEWAY_VERSION}" \
    && npm cache clean --force

ENV PATH="/opt/venv/bin:${PATH}"

USER node
WORKDIR /data
EXPOSE 3002

# No --repository: the server would exit at startup if /data itself is not a
# git repo. Tools take a repo_path argument (e.g. /data/myproject) instead.
CMD ["supergateway", \
     "--stdio", "mcp-server-git", \
     "--outputTransport", "streamableHttp", \
     "--port", "3002", \
     "--streamableHttpPath", "/mcp"]
