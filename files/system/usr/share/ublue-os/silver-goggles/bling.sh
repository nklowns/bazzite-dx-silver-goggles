#!/usr/bin/env sh

# Bazzite-DX Silver Goggles: Shell Excellence (Bling)
# Standardized Shell Experience for Bash and ZSH.
# Located in: /usr/share/ublue-os/silver-goggles/bling.sh

# Check if shell has already been sourced to prevent recursion
[ "${BLING_SOURCED:-0}" -eq 1 ] && return
BLING_SOURCED=1

# --- Configuration Toggles ---
# Set these in your private configs before this is sourced to override
: "${BLUEFIN_SHELL_ENABLE_EZA:=1}"
: "${BLUEFIN_SHELL_ENABLE_UGREP:=1}"
: "${BLUEFIN_SHELL_ENABLE_BAT:=1}"
: "${BLUEFIN_SHELL_ENABLE_ATUIN:=1}"
: "${BLUEFIN_SHELL_ENABLE_STARSHIP:=1}"
: "${BLUEFIN_SHELL_ENABLE_ZOXIDE:=1}"
: "${BLUEFIN_SHELL_ENABLE_MISE:=1}"
: "${BLUEFIN_SHELL_ENABLE_DIRENV:=1}"

# --- Power-User Extras ---
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'
alias mkdir='mkdir -p'
alias g='git'

# --- Alias Sections ---

# eza for ls
if [ "$BLUEFIN_SHELL_ENABLE_EZA" -eq 1 ] && [ "$(command -v eza)" ]; then
	alias ll='eza -l --icons=auto --group-directories-first'
	alias l.='eza -d .*'
	alias ls='eza'
	alias l1='eza -1'
fi

# ugrep for grep
if [ "$BLUEFIN_SHELL_ENABLE_UGREP" -eq 1 ]; then
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
if [ "$BLUEFIN_SHELL_ENABLE_BAT" -eq 1 ] && [ "$(command -v bat)" ]; then
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
		if [ -n "$BASH_VERSION" ]; then
			BLING_SHELL="bash"
		elif [ -n "$ZSH_VERSION" ]; then
			BLING_SHELL="zsh"
		else
			BLING_SHELL="$(ps -p $$ -o comm= 2>/dev/null | sed 's/^-//' | xargs basename 2>/dev/null)"
		fi
	fi

	# zsh: autoload add-zsh-hook before any tool tries to use it (atuin, direnv)
	[ "${BLING_SHELL}" = "zsh" ] && autoload -Uz add-zsh-hook

	# 1. Initialize direnv before bash-preexec to avoid PROMPT_COMMAND conflicts
	if [ "$BLUEFIN_SHELL_ENABLE_DIRENV" -eq 1 ] && [ "$(command -v direnv)" ]; then
		eval "$(direnv hook "${BLING_SHELL}")"
	fi

	# 2. bash-preexec support for Bash users
	if [ "${BLING_SHELL}" = "bash" ]; then
		# shellcheck disable=SC1091
		[ -f "/etc/profile.d/bash-preexec.sh" ] && . "/etc/profile.d/bash-preexec.sh"
		if [ -n "$HOMEBREW_PREFIX" ] && [ -f "${HOMEBREW_PREFIX}/etc/profile.d/bash-preexec.sh" ]; then
			# shellcheck disable=SC1091
			. "${HOMEBREW_PREFIX}/etc/profile.d/bash-preexec.sh"
		fi
	fi

	# 3. Atuin History Integration
	if [ "$BLUEFIN_SHELL_ENABLE_ATUIN" -eq 1 ] && [ "$(command -v atuin)" ]; then
		eval "$(atuin init "${BLING_SHELL}"${ATUIN_INIT_FLAGS:+ ${ATUIN_INIT_FLAGS}})"
	fi

	# 4. Starship Prompt
	if [ "$BLUEFIN_SHELL_ENABLE_STARSHIP" -eq 1 ] && [ "$(command -v starship)" ]; then
		eval "$(starship init "${BLING_SHELL}")"
	fi

	# 5. Zoxide (Better 'cd')
	if [ "$BLUEFIN_SHELL_ENABLE_ZOXIDE" -eq 1 ] && [ "$(command -v zoxide)" ]; then
		eval "$(zoxide init "${BLING_SHELL}")"
	fi

	# 6. Mise Runtime Manager
	if [ "$BLUEFIN_SHELL_ENABLE_MISE" -eq 1 ] && [ "$(command -v mise)" ]; then
		case "${BLING_SHELL}" in
		bash) [ "${MISE_BASH_AUTO_ACTIVATE:-1}" != "0" ] && eval "$(mise activate bash)" ;;
		zsh) [ "${MISE_ZSH_AUTO_ACTIVATE:-1}" != "0" ] && eval "$(mise activate zsh)" ;;
		*) eval "$(mise activate "${BLING_SHELL}")" ;;
		esac
	fi

	unset BLING_SHELL
	;;

esac
