FROM node:20-slim

ARG USERNAME=node
ARG USER_UID=1000
ARG USER_GID=1000

RUN apt-get update \
    && apt-get install -y --no-install-recommends git ca-certificates curl \
    && rm -rf /var/lib/apt/lists/*

RUN npm install -g @anthropic-ai/claude-code

COPY banner.sh /usr/local/bin/banner.sh
RUN chmod +x /usr/local/bin/banner.sh \
    && echo 'source /usr/local/bin/banner.sh' >> /etc/bash.bashrc

RUN if [ "$USERNAME" != "node" ]; then \
        getent group "$USER_GID" >/dev/null 2>&1 \
        || groupadd --gid "$USER_GID" "$USERNAME"; \
        useradd --uid "$USER_UID" --gid "$USER_GID" --no-log-init -m "$USERNAME"; \
    elif [ "$USER_UID" != "1000" ] || [ "$USER_GID" != "1000" ]; then \
        groupmod --gid "$USER_GID" node; \
        usermod --uid "$USER_UID" --gid "$USER_GID" node; \
    fi

USER ${USERNAME}
WORKDIR /home/${USERNAME}/workspace

ENTRYPOINT ["/bin/bash"]
