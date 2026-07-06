#!/usr/bin/env bash
# shellcheck shell=bash
# Bazzite-DX Silver Goggles: Common Aliases & Config
# Shared between Bash, Zsh and Fish.
# Located in: /usr/share/ublue-os/silver-goggles/common-aliases.sh

# --- Configuration Toggles ---
[ -z "${BLUEFIN_SHELL_ENABLE_EZA:-}" ] && BLUEFIN_SHELL_ENABLE_EZA=1
[ -z "${BLUEFIN_SHELL_ENABLE_UGREP:-}" ] && BLUEFIN_SHELL_ENABLE_UGREP=1
[ -z "${BLUEFIN_SHELL_ENABLE_BAT:-}" ] && BLUEFIN_SHELL_ENABLE_BAT=1

# --- Core Navigation & Basics ---
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'
alias mkdir='mkdir -p'
alias g='git'

# --- Modern CLI Replacements (Scannable Blocks) ---

# <eza>
if [ "${BLUEFIN_SHELL_ENABLE_EZA:-1}" = "1" ] && [ "$(command -v eza)" ]; then
	alias ls='eza --icons=auto --group-directories-first'
	alias ll='eza -l --icons=auto --group-directories-first'
	alias la='eza -la --icons=auto --group-directories-first'
	alias l.='eza -d .* --icons=auto'
	alias tree='eza --tree --icons=auto'
fi
# </eza>

# <ugrep>
if [ "${BLUEFIN_SHELL_ENABLE_UGREP:-1}" = "1" ] && [ "$(command -v ug)" ]; then
	alias grep='ug'
	alias egrep='ug -E'
	alias fgrep='ug -F'
fi
# </ugrep>

# <ripgrep>
[ "$(command -v rg)" ] && alias rg='rg --smart-case'
# </ripgrep>

# <bat>
if [ "${BLUEFIN_SHELL_ENABLE_BAT:-1}" = "1" ] && [ "$(command -v bat)" ]; then
	alias cat='bat -pp --pager=never'
	export PAGER="bat"
	export MANPAGER="sh -c 'col -bx | bat -l man -p'"
fi
# </bat>

# <fd>
[ "$(command -v fd)" ] && alias f='fd'
# </fd>

# --- Cloud Native & Dev Tools ---

# <kubectl>
[ "$(command -v kubectl)" ] && alias k='kubectl'
[ "$(command -v kubecolor)" ] && alias kubectl='kubecolor'
# </kubectl>

# <helm>
[ "$(command -v helm)" ] && alias h='helm'
# </helm>

# Obsidian CLI Fix: Symlink the socket from the Flatpak sandbox to the expected host location
if [ "$(command -v obsidian)" ]; then
	alias obsidian='ln -sf "${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/.flatpak/md.obsidian.Obsidian/xdg-run/.obsidian-cli.sock" "${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/.obsidian-cli.sock" 2>/dev/null; command obsidian'
fi

# --- Modern Bling Integrations & Aliases ---

# <yazi>
if [ "$(command -v yazi)" ]; then
	alias y='yazi'
	yy() {
		local tmp
		tmp="$(mktemp -t "yazi-cwd.XXXXXX")"
		yazi "$@" --cwd-file="$tmp"
		if cwd="$(cat -- "$tmp")" && [ -n "$cwd" ] && [ "$cwd" != "$PWD" ]; then
			builtin cd -- "$cwd" || return
		fi
		rm -f -- "$tmp"
	}
fi
# </yazi>

# <delta>
if [ "$(command -v delta)" ]; then
	export GIT_PAGER="delta"
fi
# </delta>


