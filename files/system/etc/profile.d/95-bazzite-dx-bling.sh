#!/usr/bin/env sh
# Bazzite-DX Silver Goggles: Shell Excellence (Declarative Wrapper)
# Sourced by /etc/profile.d/ for Bash and Zsh login shells.
# Homebrew PATH is already set by 10-homebrew.sh at this point.
# To disable: BLING_ENABLE=0 bash -l  /  BLING_ENABLE=0 zsh -l

if [ "${BLING_ENABLE:-1}" != "0" ] && [ -f "/usr/share/ublue-os/silver-goggles/bling.sh" ]; then
    # shellcheck disable=SC1090
    . "/usr/share/ublue-os/silver-goggles/bling.sh"
fi
