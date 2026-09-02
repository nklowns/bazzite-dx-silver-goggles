#!/usr/bin/env bash
# shellcheck shell=bash
# Bazzite-DX Silver Goggles: Common Aliases & Config
# Shared between Bash, Zsh and Fish.
# Located in: /usr/share/ublue-os/silver-goggles/common-aliases.sh

# Only configure host-specific aliases and environments on the host (not inside containers/distrobox)
if [ ! -f /run/.containerenv ] && [ ! -f /.dockerenv ]; then

	# --- Configuration Toggles ---
	[ -z "${BLUEFIN_SHELL_ENABLE_EZA:-}" ] && BLUEFIN_SHELL_ENABLE_EZA=1
	[ -z "${BLUEFIN_SHELL_ENABLE_UGREP:-}" ] && BLUEFIN_SHELL_ENABLE_UGREP=1
	[ -z "${BLUEFIN_SHELL_ENABLE_BAT:-}" ] && BLUEFIN_SHELL_ENABLE_BAT=1

	# --- Graphical Display & Session Auto-Heal (Wayland / X11 / D-Bus) ---
	if [ -n "${XDG_RUNTIME_DIR:-}" ]; then
		if [ -z "${WAYLAND_DISPLAY:-}" ]; then
			# Pick the most recent Wayland socket by mtime (command ls bypasses eza alias)
			_latest_sock=$(command ls -1t "${XDG_RUNTIME_DIR}"/wayland-* 2>/dev/null | grep -v '\.lock$' | head -n1 || true)
			if [ -n "$_latest_sock" ] && [ -S "$_latest_sock" ]; then
				export WAYLAND_DISPLAY="${_latest_sock##*/}"
				[ -z "${XDG_SESSION_TYPE:-}" ] && export XDG_SESSION_TYPE="wayland"
				[ -z "${XDG_CURRENT_DESKTOP:-}" ] && export XDG_CURRENT_DESKTOP="KDE"
			fi
			unset _latest_sock
		fi

		if [ -z "${DISPLAY:-}" ] && [ -S "/tmp/.X11-unix/X0" ]; then
			export DISPLAY=":0"
		fi

		if [ -z "${DBUS_SESSION_BUS_ADDRESS:-}" ] && [ -S "${XDG_RUNTIME_DIR}/bus" ]; then
			export DBUS_SESSION_BUS_ADDRESS="unix:path=${XDG_RUNTIME_DIR}/bus"
		fi
	fi

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
		# shellcheck disable=SC2262
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
			if cwd="$(command cat -- "$tmp")" && [ -n "$cwd" ] && [ "$cwd" != "$PWD" ]; then
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

fi
