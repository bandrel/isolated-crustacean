#!/bin/bash
# Static crab banner for container startup
# Only prints to interactive TTY; silent in non-interactive contexts

# Only print banner if stdout is a TTY (interactive terminal)
if [ -t 1 ]; then
    echo "(\/) (o o) (\/)"
fi
