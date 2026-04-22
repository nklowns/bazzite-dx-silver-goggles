#!/usr/bin/env zsh
# Bazzite-DX Silver Goggles: Shell Excellence (Zsh)
# Native Zsh implementation.
# Located in: /usr/share/ublue-os/silver-goggles/bling.zsh

# Force Zsh native mode if we are being sourced from a POSIX-emulated environment (like /etc/profile.d)
if [ -n "$ZSH_VERSION" ]; then
	emulate zsh
	# Ensure prompt substitution is on, otherwise Starship will show raw $(...) strings
	setopt prompt_subst
fi

# Check if already sourced to prevent recursion
# (Allow re-sourcing in interactive shells to ensure hooks are loaded)
if [ "${BLING_ZSH_SOURCED:-0}" = "1" ]; then
	case $- in
	*i*) ;;
	*) return ;;
	esac
fi
export BLING_ZSH_SOURCED=1

# --- Configuration Toggles ---
[ -z "${BLUEFIN_SHELL_ENABLE_ATUIN:-}" ] && BLUEFIN_SHELL_ENABLE_ATUIN=1
[ -z "${BLUEFIN_SHELL_ENABLE_STARSHIP:-}" ] && BLUEFIN_SHELL_ENABLE_STARSHIP=1
[ -z "${BLUEFIN_SHELL_ENABLE_ZOXIDE:-}" ] && BLUEFIN_SHELL_ENABLE_ZOXIDE=1
[ -z "${BLUEFIN_SHELL_ENABLE_MISE:-}" ] && BLUEFIN_SHELL_ENABLE_MISE=1
[ -z "${BLUEFIN_SHELL_ENABLE_DIRENV:-}" ] && BLUEFIN_SHELL_ENABLE_DIRENV=1

# --- Load Common Aliases ---
if [ -f "/usr/share/ublue-os/silver-goggles/common-aliases.sh" ]; then
	# shellcheck source=./common-aliases.sh
	. "/usr/share/ublue-os/silver-goggles/common-aliases.sh"
fi

# --- Tool Activation (interactive shells only) ---
case $- in *i*)
	# Zsh configuration
	autoload -Uz add-zsh-hook
	typeset -gaU precmd_functions preexec_functions chpwd_functions

	# 1. direnv
	if [ "${BLUEFIN_SHELL_ENABLE_DIRENV:-1}" = "1" ] && command -v direnv >/dev/null; then
		eval "$(direnv hook zsh)"
	fi

	# 2. Mise Runtime Manager
	if [ "${BLUEFIN_SHELL_ENABLE_MISE:-1}" = "1" ] && command -v mise >/dev/null; then
		if [ "${MISE_ZSH_AUTO_ACTIVATE:-1}" != "0" ]; then
			eval "$(mise activate zsh)"
		fi
	fi

	# 3. Zoxide (Better 'cd')
	if [ "${BLUEFIN_SHELL_ENABLE_ZOXIDE:-1}" = "1" ] && command -v zoxide >/dev/null; then
		eval "$(zoxide init zsh)"
	fi

	# 4. Starship Prompt
	if [ "${BLUEFIN_SHELL_ENABLE_STARSHIP:-1}" = "1" ] && command -v starship >/dev/null; then
		eval "$(starship init zsh)"
	fi

	# 5. Atuin History Integration (last)
	if [ "${BLUEFIN_SHELL_ENABLE_ATUIN:-1}" = "1" ] && command -v atuin >/dev/null; then
		eval "$(atuin init zsh${ATUIN_INIT_FLAGS:+ ${ATUIN_INIT_FLAGS}})"
	fi
	;;
esac
