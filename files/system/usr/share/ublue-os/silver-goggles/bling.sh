#!/usr/bin/env sh

# Bazzite-DX Silver Goggles: Shell Excellence (Bling)
# Standardized Shell Experience for Bash and ZSH.
# Located in: /usr/share/ublue-os/silver-goggles/bling.sh

# Check if shell has already been sourced to prevent recursion
# (Allow re-sourcing in interactive shells to ensure hooks are loaded)
if [ "${BLING_SOURCED:-0}" = "1" ]; then
	case $- in
	*i*) ;;
	*) return ;;
	esac
fi
BLING_SOURCED=1

# --- Configuration Toggles ---
# Set these in your private configs before this is sourced to override
[ -z "${BLUEFIN_SHELL_ENABLE_EZA:-}" ] && BLUEFIN_SHELL_ENABLE_EZA=1
[ -z "${BLUEFIN_SHELL_ENABLE_UGREP:-}" ] && BLUEFIN_SHELL_ENABLE_UGREP=1
[ -z "${BLUEFIN_SHELL_ENABLE_BAT:-}" ] && BLUEFIN_SHELL_ENABLE_BAT=1
[ -z "${BLUEFIN_SHELL_ENABLE_ATUIN:-}" ] && BLUEFIN_SHELL_ENABLE_ATUIN=1
[ -z "${BLUEFIN_SHELL_ENABLE_STARSHIP:-}" ] && BLUEFIN_SHELL_ENABLE_STARSHIP=1
[ -z "${BLUEFIN_SHELL_ENABLE_ZOXIDE:-}" ] && BLUEFIN_SHELL_ENABLE_ZOXIDE=1
[ -z "${BLUEFIN_SHELL_ENABLE_MISE:-}" ] && BLUEFIN_SHELL_ENABLE_MISE=1
[ -z "${BLUEFIN_SHELL_ENABLE_DIRENV:-}" ] && BLUEFIN_SHELL_ENABLE_DIRENV=1

# --- Power-User Extras ---
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'
alias mkdir='mkdir -p'
alias g='git'

# --- Alias Sections ---

# eza for ls
if [ "$BLUEFIN_SHELL_ENABLE_EZA" = "1" ] && [ "$(command -v eza)" ]; then
	alias ll='eza -l --icons=auto --group-directories-first'
	alias l.='eza -d .*'
	alias ls='eza'
	alias l1='eza -1'
fi

# ugrep for grep
if [ "$BLUEFIN_SHELL_ENABLE_UGREP" = "1" ]; then
	if [ "$(command -v ug)" ]; then
		alias grep='ug'
		alias egrep='ug -E'
		alias fgrep='ug -F'
		alias xzgrep='ug -z'
		alias xzegrep='ug -zE'
		alias xzfgrep='ug -zF'
	elif [ "$(command -v ugrep)" ]; then
		alias grep='ugrep'
		alias egrep='ugrep -E'
		alias fgrep='ugrep -F'
		alias xzgrep='ugrep -z'
		alias xzegrep='ugrep -zE'
		alias xzfgrep='ugrep -zF'
	fi
fi

# bat for cat
if [ "$BLUEFIN_SHELL_ENABLE_BAT" = "1" ] && [ "$(command -v bat)" ]; then
	alias cat='bat --style=plain --pager=never'
fi

# Kubernetes
if [ "$(command -v kubectl)" ]; then
	alias k='kubectl'
fi

# Obsidian CLI Fix: Symlink the socket from the Flatpak sandbox to the expected host location
if [ "$(command -v obsidian)" ]; then
	alias obsidian='ln -sf "${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/.flatpak/md.obsidian.Obsidian/xdg-run/.obsidian-cli.sock" "${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/.obsidian-cli.sock" 2>/dev/null; command obsidian'
fi

# --- Tool Activation (interactive shells only) ---
# Aliases above are always available. Evals (prompt, hooks, completions)
# only make sense for humans — skip in scripts and agent-driven subshells.
case $- in *i*)

	# Detect shell (macOS/Linux compatible)
	if [ -z "$BLING_SHELL" ]; then
		if [ -n "${BASH_VERSION:-}" ]; then
			BLING_SHELL="bash"
		elif [ -n "${ZSH_VERSION:-}" ]; then
			BLING_SHELL="zsh"
		else
			BLING_SHELL="$(ps -p $$ -o comm= 2>/dev/null | sed 's/^-//' | xargs basename 2>/dev/null)"
		fi
	fi

	if [ "${BLING_SHELL}" = "zsh" ]; then
		# Use native Zsh features and ensure options (like prompt_subst) persist.
		# We avoid 'emulate -L' to allow initializers to set global shell options.
		# shellcheck disable=SC3010,SC3014
		autoload -Uz add-zsh-hook
		# shellcheck disable=SC3044,SC2034,SC3010,SC3014
		typeset -gaU precmd_functions preexec_functions chpwd_functions

		# 1. direnv (before mise/starship to avoid hook ordering issues)
		# shellcheck disable=SC3010,SC3014
		if [[ "$BLUEFIN_SHELL_ENABLE_DIRENV" == "1" ]] && command -v direnv >/dev/null; then
			eval "$(direnv hook zsh)"
		fi

		# 2. Mise Runtime Manager (early for PATH availability)
		# shellcheck disable=SC3010,SC3014
		if [[ "$BLUEFIN_SHELL_ENABLE_MISE" == "1" ]] && command -v mise >/dev/null; then
			[[ "${MISE_ZSH_AUTO_ACTIVATE:-1}" != "0" ]] && eval "$(mise activate zsh)"
		fi

		# 3. Zoxide (Better 'cd')
		# shellcheck disable=SC3010,SC3014
		if [[ "$BLUEFIN_SHELL_ENABLE_ZOXIDE" == "1" ]] && command -v zoxide >/dev/null; then
			eval "$(zoxide init zsh)"
		fi

		# 4. Starship Prompt
		# shellcheck disable=SC3010,SC3014
		if [[ "$BLUEFIN_SHELL_ENABLE_STARSHIP" == "1" ]] && command -v starship >/dev/null; then
			eval "$(starship init zsh)"
		fi

		# 5. Atuin History Integration (last, to capture hook changes from other tools)
		# shellcheck disable=SC3010,SC3014
		if [[ "$BLUEFIN_SHELL_ENABLE_ATUIN" == "1" ]] && command -v atuin >/dev/null; then
			eval "$(atuin init zsh${ATUIN_INIT_FLAGS:+ ${ATUIN_INIT_FLAGS}})"
		fi

	else
		# 1. Initialize direnv first (before array-modifying tools)
		if [ "$BLUEFIN_SHELL_ENABLE_DIRENV" = "1" ] && [ "$(command -v direnv)" ]; then
			eval "$(direnv hook "${BLING_SHELL}")"
		fi

		# 2. Mise Runtime Manager (early for PATH availability)
		# Must run before bash-preexec: mise prepends _mise_hook_prompt_command as a new
		# PROMPT_COMMAND array element. If bash-preexec loaded first, its deferred install
		# string (containing `trap - DEBUG`) would be pushed to element[1] by mise's prepend,
		# where __bp_install's cleanup cannot reach it — causing trap - DEBUG to fire on every
		# prompt and permanently clear the DEBUG trap that atuin requires.
		if [ "$BLUEFIN_SHELL_ENABLE_MISE" = "1" ] && [ "$(command -v mise)" ]; then
			case "${BLING_SHELL}" in
			bash) [ "${MISE_BASH_AUTO_ACTIVATE:-1}" != "0" ] && eval "$(mise activate bash)" ;;
			*) eval "$(mise activate "${BLING_SHELL}")" ;;
			esac
		fi

		# 3. Zoxide (Better 'cd') — before bash-preexec for same array-ordering reason
		if [ "$BLUEFIN_SHELL_ENABLE_ZOXIDE" = "1" ] && [ "$(command -v zoxide)" ]; then
			eval "$(zoxide init "${BLING_SHELL}")"
		fi

		# 4. bash-preexec (after mise/zoxide so its install string lands in PROMPT_COMMAND[0])
		if [ "${BLING_SHELL}" = "bash" ]; then
			# shellcheck source=/dev/null
			[ -f "/etc/profile.d/bash-preexec.sh" ] && . "/etc/profile.d/bash-preexec.sh"
			if [ -n "$HOMEBREW_PREFIX" ] && [ -f "${HOMEBREW_PREFIX}/etc/profile.d/bash-preexec.sh" ]; then
				# shellcheck source=/dev/null
				. "${HOMEBREW_PREFIX}/etc/profile.d/bash-preexec.sh"
			fi
		fi

		# 5. Starship Prompt (after bash-preexec so it detects bash_preexec_imported)
		if [ "$BLUEFIN_SHELL_ENABLE_STARSHIP" = "1" ] && [ "$(command -v starship)" ]; then
			eval "$(starship init "${BLING_SHELL}")"
		fi

		# 6. Atuin History Integration (last, to capture hook changes from other tools)
		if [ "$BLUEFIN_SHELL_ENABLE_ATUIN" = "1" ] && [ "$(command -v atuin)" ]; then
			eval "$(atuin init "${BLING_SHELL}"${ATUIN_INIT_FLAGS:+ ${ATUIN_INIT_FLAGS}})"
		fi
	fi

	unset BLING_SHELL
	;;

esac
