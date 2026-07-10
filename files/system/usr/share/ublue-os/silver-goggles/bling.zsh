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
	# --- VS Code / VS Code Insiders / Cursor / Antigravity IDE Integration ---
	_setup_vscode_editor() {
		# Do not run inside containers to avoid IPC and process tree issues
		if [ -f /run/.containerenv ] || [ -f /.dockerenv ]; then
			return 0
		fi

		# Only override if EDITOR is empty, or set to standard defaults (nano/vi/vim)
		case "${EDITOR:-}" in
			""|*nano*|*vi|*vim) ;;
			*) return 0 ;;
		esac

		local _detected_editor=""
		local _var
		for _var in "$VSCODE_GIT_ASKPASS_NODE" "$GIT_ASKPASS" "$TERM_PROGRAM_VERSION"; do
			case "$_var" in
				*code-insiders*) _detected_editor="code-insiders"; break ;;
				*cursor*) _detected_editor="cursor"; break ;;
				*antigravity-ide*) _detected_editor="antigravity-ide"; break ;;
				*code*) _detected_editor="code"; break ;;
			esac
		done

		if [ -z "$_detected_editor" ]; then
			local _pid=$$
			local _cmd
			while [ "$_pid" -gt 1 ]; do
				_cmd=$(ps -p "$_pid" -o comm= 2>/dev/null || true)
				case "$_cmd" in
					*code-insiders*) _detected_editor="code-insiders"; break ;;
					*cursor*) _detected_editor="cursor"; break ;;
					*antigravity-ide*) _detected_editor="antigravity-ide"; break ;;
					*code*) _detected_editor="code"; break ;;
				esac
				_pid=$(ps -p "$_pid" -o ppid= 2>/dev/null | tr -d ' ' || true)
				[ -z "$_pid" ] && break
			done
		fi

		if [ -n "$_detected_editor" ] && command -v "$_detected_editor" >/dev/null 2>&1; then
			export EDITOR="$_detected_editor --wait"
			export VISUAL="$_detected_editor --wait"
		fi
	}
	if [ "${TERM_PROGRAM:-}" = "vscode" ] || [ -n "${VSCODE_GIT_ASKPASS_NODE:-}" ]; then
		_setup_vscode_editor
	fi
	unset -f _setup_vscode_editor

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
