#!/bin/sh
# Install herdr (https://herdr.dev) into ~/.local/bin if it isn't there yet.
# Later updates are done by ~/.local/bin/herdr-update-check on shell start.
set -eu

if command -v herdr >/dev/null 2>&1 || [ -x "$HOME/.local/bin/herdr" ]; then
  exit 0
fi
curl -fsSL https://herdr.dev/install.sh | sh
