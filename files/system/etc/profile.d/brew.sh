#!/usr/bin/env sh
# Bazzite-DX: Homebrew PATH and interactive extras for bash/zsh login shells.
# HOMEBREW_PREFIX is set system-wide via /usr/lib/environment.d/homebrew.conf
# Interactive guard prevents execution in bwrap/sandbox non-interactive contexts.

_BREW_BIN="/home/linuxbrew/.linuxbrew/bin/brew"
[ -z "${HOMEBREW_PREFIX:-}" ] && HOMEBREW_PREFIX="/home/linuxbrew/.linuxbrew"

if [ -x "$_BREW_BIN" ] && [ "$(/usr/bin/id -u)" != "0" ]; then
	# Add brew to PATH if not already present.
	# We check the actual PATH content instead of relying on an environment variable,
	# as variables can be inherited by processes (like IDEs) while the PATH is reset.
	case ":${PATH}:" in
	*:"${HOMEBREW_PREFIX}/bin":*) ;;
	*)
		# Add brew to PATH — appended so system tools keep priority over brew tools.
		# This follows the Bazzite-DX "Standard" priority to ensure system stability.
		export PATH="${PATH}:${HOMEBREW_PREFIX}/bin:${HOMEBREW_PREFIX}/sbin"
		;;
	esac

	# Interactive extras (slow bits and completions)
	case $- in
	*i*)
		if [ -z "${HOMEBREW_PREFIX_INITIALIZED:-}" ]; then
			# Set MANPATH and INFOPATH so man/info find brew-installed documentation.
			eval "$($_BREW_BIN shellenv | grep -E '(MANPATH|INFOPATH)=')"
			export HOMEBREW_PREFIX_INITIALIZED=1
		fi
		;;
	esac
fi

unset _BREW_BIN
