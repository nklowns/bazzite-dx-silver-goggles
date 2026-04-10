#!/usr/bin/env sh

# Bazzite-DX Silver Goggles: Shell Excellence (Declarative Wrapper)
# This file ensures that the Silver Goggles 'bling' is sourced for Bash and ZSH.

BLING_PATH="/usr/share/ublue-os/silver-goggles/bling.sh"

if [ -f "$BLING_PATH" ]; then
    # shellcheck disable=SC1090
    . "$BLING_PATH"
fi
