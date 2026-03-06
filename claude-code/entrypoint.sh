#!/bin/bash
set -euo pipefail

export PATH="$HOME/.local/bin:$PATH"

if [ -d /mnt/host-claude ]; then
    cp -a /mnt/host-claude/. "$HOME/.claude/"
fi

if [ -f /mnt/host-claude.json ]; then
    cp /mnt/host-claude.json "$HOME/.claude.json"
fi

source /usr/local/bin/banner.sh

exec claude "$@"
