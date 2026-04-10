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
alias d='docker'

# --- Alias Sections ---

# eza for ls
if [ "$BLUEFIN_SHELL_ENABLE_EZA" -eq 1 ] && [ "$(command -v eza)" ]; then
	alias ll='eza -l --icons=auto --group-directories-first'
	alias l.='eza -d .*'
	alias ls='eza'
	alias l1='eza -1'
fi

# ugrep for grep
if [ "$BLUEFIN_SHELL_ENABLE_UGREP" -eq 1 ] && [ "$(command -v ug)" ]; then
	alias grep='ug'
	alias egrep='ug -E'
	alias fgrep='ug -F'
	alias xzgrep='ug -z'
	alias xzegrep='ug -zE'
	alias xzfgrep='ug -zF'
fi

# bat for cat
if [ "$BLUEFIN_SHELL_ENABLE_BAT" -eq 1 ] && [ "$(command -v bat)" ]; then
	alias cat='bat --style=plain --pager=never' 2>/dev/null
fi

# Kubernetes
if [ "$(command -v kubectl)" ]; then
	alias k='kubectl'
fi

# Obsidian CLI Fix: Symlink the socket from the Flatpak sandbox to the expected host location
if [ "$(command -v obsidian)" ]; then
    alias obsidian='ln -sf "${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/.flatpak/md.obsidian.Obsidian/xdg-run/.obsidian-cli.sock" "${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/.obsidian-cli.sock" 2>/dev/null; command obsidian'
fi

# --- Tool Activation ---

# Detect shell
BLING_SHELL="$(basename "$(readlink /proc/$$/exe)")"

# 1. Initialize direnv before bash-preexec to avoid PROMPT_COMMAND conflicts
if [ "$BLUEFIN_SHELL_ENABLE_DIRENV" -eq 1 ] && [ "$(command -v direnv)" ]; then
	eval "$(direnv hook "${BLING_SHELL}")"
fi

# 2. bash-preexec support for Bash users
if [ "${BLING_SHELL}" = "bash" ]; then
	[ -f "/etc/profile.d/bash-preexec.sh" ] && . "/etc/profile.d/bash-preexec.sh"
	[ -f "/usr/share/bash-prexec" ] && . "/usr/share/bash-prexec"
	[ -f "/usr/share/bash-prexec.sh" ] && . "/usr/share/bash-prexec.sh"
	if [ -n "$HOMEBREW_PREFIX" ] && [ -f "${HOMEBREW_PREFIX}/etc/profile.d/bash-preexec.sh" ]; then
		. "${HOMEBREW_PREFIX}/etc/profile.d/bash-preexec.sh"
	fi
fi

# 3. Atuin History Integration
if [ "$BLUEFIN_SHELL_ENABLE_ATUIN" -eq 1 ] && [ "$(command -v atuin)" ]; then
	ATUIN_INIT_FLAGS="${ATUIN_INIT_FLAGS:-}"
	eval "$(atuin init "${BLING_SHELL}" "${ATUIN_INIT_FLAGS}")"
fi

# 4. Starship
if [ "$BLUEFIN_SHELL_ENABLE_STARSHIP" -eq 1 ] && [ "$(command -v starship)" ]; then
	eval "$(starship init "${BLING_SHELL}")"
fi

# 5. Zoxide (Better 'cd')
if [ "$BLUEFIN_SHELL_ENABLE_ZOXIDE" -eq 1 ] && [ "$(command -v zoxide)" ]; then
	eval "$(zoxide init "${BLING_SHELL}")"
fi

# 6. Mise
if [ "$BLUEFIN_SHELL_ENABLE_MISE" -eq 1 ] && [ "$(command -v mise)" ]; then
	case "${BLING_SHELL}" in
		bash) [ "${MISE_BASH_AUTO_ACTIVATE:-1}" != "0" ] && eval "$(mise activate bash)" ;;
		zsh)  [ "${MISE_ZSH_AUTO_ACTIVATE:-1}" != "0" ] && eval "$(mise activate zsh)" ;;
		*)    eval "$(mise activate "${BLING_SHELL}")" ;;
	esac
fi
