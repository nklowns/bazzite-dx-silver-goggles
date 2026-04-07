#!/usr/bin/env sh

# Bazzite-DX: Shell Excellence (Bling)
# Standardized Shell Experience for the uBlue Ecosystem.
# Supports both Bash and ZSH.

# Check if shell has already been sourced so that we dont break atuin. https://github.com/atuinsh/atuin/issues/380#issuecomment-1594014644
# Prevent recursive sourcing
[ "${BLING_SOURCED:-0}" -eq 1 ] && return
BLING_SOURCED=1

# Default to enabled if variable is not set (backwards compatibility)
: "${BLUEFIN_SHELL_ENABLE_EZA:=1}"
: "${BLUEFIN_SHELL_ENABLE_UGREP:=1}"
: "${BLUEFIN_SHELL_ENABLE_BAT:=1}"
: "${BLUEFIN_SHELL_ENABLE_ATUIN:=1}"
: "${BLUEFIN_SHELL_ENABLE_STARSHIP:=1}"
: "${BLUEFIN_SHELL_ENABLE_ZOXIDE:=1}"
: "${BLUEFIN_SHELL_ENABLE_MISE:=1}"
: "${BLUEFIN_SHELL_ENABLE_DIRENV:=1}"

# eza
# ls aliases
if [ "$BLUEFIN_SHELL_ENABLE_EZA" -eq 1 ] && [ "$(command -v eza)" ]; then
	alias ll='eza -l --icons=auto --group-directories-first'
	alias l.='eza -d .*'
	alias ls='eza'
	alias l1='eza -1'
fi

# ugrep
# for grep
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

# 1. Atuin History Integration (Optional Sync)
# set ATUIN_INIT_FLAGS in your ~/.bashrc before ublue-bling is sourced.
# Atuin allows these flags: "--disable-up-arrow" and/or "--disable-ctrl-r"
ATUIN_INIT_FLAGS=${ATUIN_INIT_FLAGS:-""}

# To enable cloud-native command history, run: atuin register
[ "$BLUEFIN_SHELL_ENABLE_ATUIN" -eq 1 ] && [ "$(command -v atuin)" ] && eval "$(atuin init "${BLING_SHELL}" "${ATUIN_INIT_FLAGS}")"

# 2. Starship
[ "$BLUEFIN_SHELL_ENABLE_STARSHIP" -eq 1 ] && [ "$(command -v starship)" ] && eval "$(starship init "${BLING_SHELL}")"

# 3. Mise
[ "$BLUEFIN_SHELL_ENABLE_MISE" -eq 1 ] && [ "$(command -v mise)" ] && eval "$(mise activate "${BLING_SHELL}")"

# 4. Direnv
[ "$BLUEFIN_SHELL_ENABLE_DIRENV" -eq 1 ] && [ "$(command -v direnv)" ] && eval "$(direnv hook "${BLING_SHELL}")"

# 5. Zoxide Activation (Better 'cd')
[ "$BLUEFIN_SHELL_ENABLE_ZOXIDE" -eq 1 ] && [ "$(command -v zoxide)" ] && eval "$(zoxide init "${BLING_SHELL}")"

# --- Power-User Extras ---
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'
alias mkdir='mkdir -p'
alias g='git'
alias d='docker'
alias k='kubectl'
