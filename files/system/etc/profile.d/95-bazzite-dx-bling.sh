#!/usr/bin/env sh
# Bazzite-DX Silver Goggles: Shell Excellence (Declarative Wrapper)
# Sourced by /etc/profile.d/ for Bash and Zsh.
# To disable: BLING_ENABLE=0 bash -l  /  BLING_ENABLE=0 zsh -l

# Exit if disabled
[ "${BLING_ENABLE:-1}" = "0" ] && return

if [ -n "${ZSH_VERSION:-}" ]; then
	# Zsh specialized initialization
	if [ -f "/usr/share/ublue-os/silver-goggles/bling.zsh" ]; then
		# shellcheck source=/dev/null
		. "/usr/share/ublue-os/silver-goggles/bling.zsh"
	fi
else
	if [ -f "/usr/share/ublue-os/silver-goggles/bling.sh" ]; then
		# shellcheck source=/dev/null
		. "/usr/share/ublue-os/silver-goggles/bling.sh"
	fi
fi
