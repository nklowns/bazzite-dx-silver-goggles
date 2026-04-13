#!/usr/bin/env sh

# Bazzite-DX Silver Goggles: Shell Excellence (Declarative Wrapper)
# Sourced by /etc/bashrc → /etc/bashrc.d/ for Bash interactive shells.
# Runs after ~/.local/bin and Homebrew are already in PATH.

BLING_PATH="/usr/share/ublue-os/silver-goggles/bling.sh"

if [ -f "$BLING_PATH" ]; then
    # shellcheck disable=SC1090
    . "$BLING_PATH"
fi
