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
BLING_ZSH_SOURCED=1
# Ensure it's not exported to child shells
unset -v BLING_ZSH_SOURCED 2>/dev/null
BLING_ZSH_SOURCED=1

# --- Configuration Toggles ---
# Set these in your private configs before this is sourced to override
[ -z "${BLUEFIN_SHELL_ENABLE_ATUIN:-}" ] && BLUEFIN_SHELL_ENABLE_ATUIN=1
[ -z "${BLUEFIN_SHELL_ENABLE_STARSHIP:-}" ] && BLUEFIN_SHELL_ENABLE_STARSHIP=1
[ -z "${BLUEFIN_SHELL_ENABLE_ZOXIDE:-}" ] && BLUEFIN_SHELL_ENABLE_ZOXIDE=1
[ -z "${BLUEFIN_SHELL_ENABLE_MISE:-}" ] && BLUEFIN_SHELL_ENABLE_MISE=1
[ -z "${BLUEFIN_SHELL_ENABLE_DIRENV:-}" ] && BLUEFIN_SHELL_ENABLE_DIRENV=1
[ -z "${BLUEFIN_SHELL_ENABLE_FZF:-}" ] && BLUEFIN_SHELL_ENABLE_FZF=1
[ -z "${BLUEFIN_SHELL_ENABLE_K8S:-}" ] && BLUEFIN_SHELL_ENABLE_K8S=1

# --- Load Common Aliases ---
if [ -f "/usr/share/ublue-os/silver-goggles/common-aliases.sh" ]; then
	# shellcheck source=./common-aliases.sh
	. "/usr/share/ublue-os/silver-goggles/common-aliases.sh"
fi

# --- Mise PATH Setup (Non-interactive safe) ---
# Ensure Mise shims are in PATH even in non-interactive shells (like SSH commands or IDE tasks).
# We prepend them to follow the "Inverted PATH Priority" (User-first) standard.
if [ "${BLUEFIN_SHELL_ENABLE_MISE:-1}" = "1" ]; then
	MISE_SHIMS_DIR="${MISE_DATA_DIR:-$HOME/.local/share/mise}/shims"
	if [ -d "$MISE_SHIMS_DIR" ]; then
		case ":${PATH}:" in
		*:"$MISE_SHIMS_DIR":*) ;;
		*) export PATH="$MISE_SHIMS_DIR:$PATH" ;;
		esac
	fi
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

	# 2. Mise Runtime Activation (Hooks/Interactive extras)
	if [ "${BLUEFIN_SHELL_ENABLE_MISE:-1}" = "1" ] && command -v mise >/dev/null; then
		if [ "${MISE_ZSH_AUTO_ACTIVATE:-1}" != "0" ]; then
			eval "$(mise activate zsh)"
		fi
	fi
	# 3. Zoxide (Better 'cd')
	if [ "${BLUEFIN_SHELL_ENABLE_ZOXIDE:-1}" = "1" ] && command -v zoxide >/dev/null; then
		eval "$(zoxide init zsh)"
	fi

	# 3.1 FZF
	if [ "${BLUEFIN_SHELL_ENABLE_FZF:-1}" = "1" ] && command -v fzf >/dev/null; then
		if fzf --zsh >/dev/null 2>&1; then
			eval "$(fzf --zsh)"
		else
			# Fallback for older fzf versions
			[ -f "${HOMEBREW_PREFIX:-}/opt/fzf/shell/key-bindings.zsh" ] && . "${HOMEBREW_PREFIX:-}/opt/fzf/shell/key-bindings.zsh"
			[ -f "${HOMEBREW_PREFIX:-}/opt/fzf/shell/completion.zsh" ] && . "${HOMEBREW_PREFIX:-}/opt/fzf/shell/completion.zsh"
		fi
	fi

	# 4. Starship Prompt
	if [ "${BLUEFIN_SHELL_ENABLE_STARSHIP:-1}" = "1" ] && command -v starship >/dev/null; then
		eval "$(starship init zsh)"
	fi

	# 5. Atuin History Integration (Deferred/Lazy Loading)
	if [ "${BLUEFIN_SHELL_ENABLE_ATUIN:-1}" = "1" ] && command -v atuin >/dev/null; then
		# We lazy-load atuin by overriding the first call to history-related widgets
		# or by initializing it on the first prompt (precmd).
		_bling_lazy_atuin() {
			eval "$(atuin init zsh${ATUIN_INIT_FLAGS:+ ${ATUIN_INIT_FLAGS}})"
			add-zsh-hook -d precmd _bling_lazy_atuin
		}
		add-zsh-hook precmd _bling_lazy_atuin
	fi
	;;
esac
