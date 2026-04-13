# Bazzite-DX Silver Goggles: Shell Excellence (Declarative Wrapper)
# Sourced by /etc/zshrc → /etc/zshrc.d/ for Zsh interactive shells.
# For login shells, runs after ~/.zprofile where Homebrew sets up PATH.

BLING_PATH="/usr/share/ublue-os/silver-goggles/bling.sh"

if [ -f "$BLING_PATH" ]; then
    # shellcheck disable=SC1090
    . "$BLING_PATH"
fi
