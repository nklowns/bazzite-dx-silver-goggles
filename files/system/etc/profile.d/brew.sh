#!/usr/bin/env sh
# Bazzite-DX: Homebrew PATH and interactive extras for bash/zsh login shells.
# HOMEBREW_PREFIX is set system-wide via /usr/lib/environment.d/homebrew.conf
# Interactive guard prevents execution in bwrap/sandbox non-interactive contexts.

_BREW_BIN="/home/linuxbrew/.linuxbrew/bin/brew"

if [ -x "$_BREW_BIN" ] && [ "$(/usr/bin/id -u)" != "0" ] && [ -z "${HOMEBREW_PREFIX_INITIALIZED:-}" ]; then
	case $- in
	*i*)
		# Add brew to PATH — appended so system tools keep priority over brew tools.
		export PATH="${PATH}:${HOMEBREW_PREFIX}/bin:${HOMEBREW_PREFIX}/sbin"
		export HOMEBREW_PREFIX_INITIALIZED=1

		# Set MANPATH and INFOPATH so man/info find brew-installed documentation.
		eval "$($_BREW_BIN shellenv | grep -E '(MANPATH|INFOPATH)=')"
		;;
	esac
fi

unset _BREW_BIN
