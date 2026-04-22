#!/usr/bin/env zsh
# Bazzite-DX Silver Goggles: Shell Excellence (Zsh)
# Native Zsh implementation.
# Located in: /usr/share/ublue-os/silver-goggles/bling.zsh

# Check if already sourced to prevent recursion
# (Allow re-sourcing in interactive shells to ensure hooks are loaded)
if [[ "${BLING_ZSH_SOURCED:-0}" == "1" ]]; then
	[[ "$ZSH_SUBSHELL" == "0" ]] && [[ ! -o interactive ]] && return
fi
export BLING_ZSH_SOURCED=1

# --- Configuration Toggles ---
# Set these in your private configs before this is sourced to override
[ -z "${BLUEFIN_SHELL_ENABLE_ATUIN:-}" ] && BLUEFIN_SHELL_ENABLE_ATUIN=1
[ -z "${BLUEFIN_SHELL_ENABLE_STARSHIP:-}" ] && BLUEFIN_SHELL_ENABLE_STARSHIP=1
[ -z "${BLUEFIN_SHELL_ENABLE_ZOXIDE:-}" ] && BLUEFIN_SHELL_ENABLE_ZOXIDE=1
[ -z "${BLUEFIN_SHELL_ENABLE_MISE:-}" ] && BLUEFIN_SHELL_ENABLE_MISE=1
[ -z "${BLUEFIN_SHELL_ENABLE_DIRENV:-}" ] && BLUEFIN_SHELL_ENABLE_DIRENV=1

# --- Load Common Aliases ---
if [[ -f /usr/share/ublue-os/silver-goggles/common-aliases.sh ]]; then
	source /usr/share/ublue-os/silver-goggles/common-aliases.sh
fi

# --- Tool Activation (interactive shells only) ---
if [[ -o interactive ]]; then

	# Zsh configuration
	# Use native Zsh features and ensure options (like prompt_subst) persist.
	autoload -Uz add-zsh-hook
	typeset -gaU precmd_functions preexec_functions chpwd_functions

	# 1. direnv
	if [[ "${BLUEFIN_SHELL_ENABLE_DIRENV:-1}" == "1" ]] && command -v direnv >/dev/null; then
		eval "$(direnv hook zsh)"
	fi

	# 2. Mise Runtime Manager
	if [[ "${BLUEFIN_SHELL_ENABLE_MISE:-1}" == "1" ]] && command -v mise >/dev/null; then
		if [[ "${MISE_ZSH_AUTO_ACTIVATE:-1}" != "0" ]]; then
			eval "$(mise activate zsh)"
		fi
	fi

	# 3. Zoxide (Better 'cd')
	if [[ "${BLUEFIN_SHELL_ENABLE_ZOXIDE:-1}" == "1" ]] && command -v zoxide >/dev/null; then
		eval "$(zoxide init zsh)"
	fi

	# 4. Starship Prompt
	if [[ "${BLUEFIN_SHELL_ENABLE_STARSHIP:-1}" == "1" ]] && command -v starship >/dev/null; then
		eval "$(starship init zsh)"
	fi

	# 5. Atuin History Integration (last)
	if [[ "${BLUEFIN_SHELL_ENABLE_ATUIN:-1}" == "1" ]] && command -v atuin >/dev/null; then
		eval "$(atuin init zsh${ATUIN_INIT_FLAGS:+ ${ATUIN_INIT_FLAGS}})"
	fi

fi
