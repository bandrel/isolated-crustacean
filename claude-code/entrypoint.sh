#!/bin/bash
set -euo pipefail

export PATH="$HOME/.local/bin:$PATH"

source /usr/local/bin/banner.sh

exec claude "$@"
