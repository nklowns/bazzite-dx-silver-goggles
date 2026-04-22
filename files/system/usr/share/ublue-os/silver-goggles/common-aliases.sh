#!/usr/bin/env sh
# Bazzite-DX Silver Goggles: Common Aliases & Config
# Shared between Bash, Zsh and Fish.
# Located in: /usr/share/ublue-os/silver-goggles/common-aliases.sh

# --- Configuration Toggles ---
# Set these in your private configs before this is sourced to override
[ -z "${BLUEFIN_SHELL_ENABLE_EZA:-}" ] && BLUEFIN_SHELL_ENABLE_EZA=1
[ -z "${BLUEFIN_SHELL_ENABLE_UGREP:-}" ] && BLUEFIN_SHELL_ENABLE_UGREP=1
[ -z "${BLUEFIN_SHELL_ENABLE_BAT:-}" ] && BLUEFIN_SHELL_ENABLE_BAT=1

# --- Navigation & Basics ---
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'
alias mkdir='mkdir -p'
alias g='git'

# --- Alias Sections ---

# eza for ls
if [ "${BLUEFIN_SHELL_ENABLE_EZA:-1}" = "1" ] && [ "$(command -v eza)" ]; then
	alias ll='eza -l --icons=auto --group-directories-first'
	alias l.='eza -d .*'
	alias ls='eza'
	alias l1='eza -1'
fi

# ugrep for grep
if [ "${BLUEFIN_SHELL_ENABLE_UGREP:-1}" = "1" ]; then
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
if [ "${BLUEFIN_SHELL_ENABLE_BAT:-1}" = "1" ] && [ "$(command -v bat)" ]; then
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
