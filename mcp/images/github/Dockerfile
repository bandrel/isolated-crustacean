# Official GitHub MCP server binary, taken from the pinned upstream image and
# wrapped with supergateway as a stdio -> Streamable HTTP bridge.
#
# Upstream: https://github.com/github/github-mcp-server
# Image:    ghcr.io/github/github-mcp-server (distroless, static Go binary)
# Bridge:   https://github.com/supercorp-ai/supergateway
#
# Why bridge stdio instead of the server's native `http` mode: in `http` mode
# the server ignores GITHUB_PERSONAL_ACCESS_TOKEN and requires a per-request
# `Authorization: Bearer` header (returns 401 otherwise), which would force
# the token into claude.json. In `stdio` mode the token is read from the
# environment and `initialize` succeeds even without one.
ARG UPSTREAM_TAG=v1.12.2
FROM ghcr.io/github/github-mcp-server:${UPSTREAM_TAG} AS upstream

FROM node:24-bookworm-slim

ARG SUPERGATEWAY_VERSION=4.0.0

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates \
    && rm -rf /var/lib/apt/lists/* \
    && npm install -g --no-fund --no-audit "supergateway@${SUPERGATEWAY_VERSION}" \
    && npm cache clean --force

COPY --from=upstream /server/github-mcp-server /usr/local/bin/github-mcp-server

USER node
EXPOSE 3001

CMD ["supergateway", \
     "--stdio", "github-mcp-server stdio", \
     "--outputTransport", "streamableHttp", \
     "--port", "3001", \
     "--streamableHttpPath", "/mcp"]
