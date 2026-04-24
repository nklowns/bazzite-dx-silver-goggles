#!/usr/bin/env sh

# Bazzite-DX Silver Goggles: Shell Excellence (Bling)
# Standardized Shell Experience for Bash.
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
[ -z "${BLUEFIN_SHELL_ENABLE_ATUIN:-}" ] && BLUEFIN_SHELL_ENABLE_ATUIN=1
[ -z "${BLUEFIN_SHELL_ENABLE_STARSHIP:-}" ] && BLUEFIN_SHELL_ENABLE_STARSHIP=1
[ -z "${BLUEFIN_SHELL_ENABLE_ZOXIDE:-}" ] && BLUEFIN_SHELL_ENABLE_ZOXIDE=1
[ -z "${BLUEFIN_SHELL_ENABLE_MISE:-}" ] && BLUEFIN_SHELL_ENABLE_MISE=1
[ -z "${BLUEFIN_SHELL_ENABLE_DIRENV:-}" ] && BLUEFIN_SHELL_ENABLE_DIRENV=1
[ -z "${BLUEFIN_SHELL_ENABLE_FZF:-}" ] && BLUEFIN_SHELL_ENABLE_FZF=1
[ -z "${BLUEFIN_SHELL_ENABLE_K8S:-}" ] && BLUEFIN_SHELL_ENABLE_K8S=1

# --- Load Common Aliases ---
if [ -f /usr/share/ublue-os/silver-goggles/common-aliases.sh ]; then
	# shellcheck source=/dev/null
	. /usr/share/ublue-os/silver-goggles/common-aliases.sh
fi

# --- Tool Activation (interactive shells only) ---
# Aliases above are always available. Evals (prompt, hooks, completions)
# only make sense for humans — skip in scripts and agent-driven subshells.
case $- in *i*)

	# Detect shell (macOS/Linux compatible)
	if [ -z "$BLING_SHELL" ]; then
		if [ -n "${BASH_VERSION:-}" ]; then
			BLING_SHELL="bash"
		else
			BLING_SHELL="$(ps -p $$ -o comm= 2>/dev/null | sed 's/^-//' | xargs basename 2>/dev/null)"
		fi
	fi

	# 1. direnv (before mise/starship to avoid hook ordering issues)
	if [ "${BLUEFIN_SHELL_ENABLE_DIRENV:-1}" = "1" ] && [ "$(command -v direnv)" ]; then
		eval "$(direnv hook "${BLING_SHELL}")"
	fi

	# 1.1 Homebrew Completions (if not already handled)
	if [ -n "${HOMEBREW_PREFIX:-}" ]; then
		if [ -f "${HOMEBREW_PREFIX}/etc/profile.d/bash_completion.sh" ]; then
			# shellcheck source=/dev/null
			. "${HOMEBREW_PREFIX}/etc/profile.d/bash_completion.sh"
		fi
	fi

	# 2. Mise Runtime Manager (Shims-first for performance)
	if [ "${BLUEFIN_SHELL_ENABLE_MISE:-1}" = "1" ] && [ "$(command -v mise)" ]; then
		# Use mise's own logic to find data dir if possible, otherwise default
		MISE_SHIMS_DIR="${MISE_DATA_DIR:-$HOME/.local/share/mise}/shims"
		[ -d "$MISE_SHIMS_DIR" ] && export PATH="$MISE_SHIMS_DIR:$PATH"
		case "${BLING_SHELL}" in
		bash) [ "${MISE_BASH_AUTO_ACTIVATE:-1}" != "0" ] && eval "$(mise activate bash)" ;;
		*) eval "$(mise activate "${BLING_SHELL}")" ;;
		esac
	fi

	# 3. Zoxide (Better 'cd') — before bash-preexec for array-ordering reason
	if [ "${BLUEFIN_SHELL_ENABLE_ZOXIDE:-1}" = "1" ] && [ "$(command -v zoxide)" ]; then
		eval "$(zoxide init "${BLING_SHELL}")"
	fi

	# 3.1 FZF (Fuzzy Finder)
	if [ "${BLUEFIN_SHELL_ENABLE_FZF:-1}" = "1" ] && [ "$(command -v fzf)" ]; then
		# Check if fzf supports the new flags, fallback to old source method if needed
		if fzf --bash >/dev/null 2>&1; then
			case "${BLING_SHELL}" in
			bash) eval "$(fzf --bash)" ;;
			esac
		else
			# shellcheck source=/dev/null
			[ -f "${HOMEBREW_PREFIX:-}/opt/fzf/shell/key-bindings.bash" ] && . "${HOMEBREW_PREFIX:-}/opt/fzf/shell/key-bindings.bash"
			# shellcheck source=/dev/null
			[ -f "${HOMEBREW_PREFIX:-}/opt/fzf/shell/completion.bash" ] && . "${HOMEBREW_PREFIX:-}/opt/fzf/shell/completion.bash"
		fi
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
	if [ "${BLUEFIN_SHELL_ENABLE_STARSHIP:-1}" = "1" ] && [ "$(command -v starship)" ]; then
		eval "$(starship init "${BLING_SHELL}")"
	fi

	# 6. Atuin History Integration (Deferred/Lazy Loading)
	if [ "${BLUEFIN_SHELL_ENABLE_ATUIN:-1}" = "1" ] && [ "$(command -v atuin)" ]; then
		if [ "${BLING_SHELL}" = "bash" ]; then
			_bling_lazy_atuin() {
				# Use a subshell to avoid polluting environment during initialization
				eval "$(atuin init bash${ATUIN_INIT_FLAGS:+ ${ATUIN_INIT_FLAGS}})"
				# Removal of self from PROMPT_COMMAND (safe for both string and array)
				if [ -n "${BASH_VERSION:-}" ]; then
					# Bash 4.4+ supports array PROMPT_COMMAND, but many systems still use strings
					case "${PROMPT_COMMAND-}" in
					*"_bling_lazy_atuin"*)
						PROMPT_COMMAND=$(printf '%s' "$PROMPT_COMMAND" | sed 's/_bling_lazy_atuin; //g; s/_bling_lazy_atuin//g')
						;;
					esac
				fi
				unset -f _bling_lazy_atuin
			}
			# Prepend to PROMPT_COMMAND
			if [ -z "${PROMPT_COMMAND-}" ]; then
				PROMPT_COMMAND="_bling_lazy_atuin"
			else
				PROMPT_COMMAND="_bling_lazy_atuin; $PROMPT_COMMAND"
			fi
		else
			eval "$(atuin init "${BLING_SHELL}"${ATUIN_INIT_FLAGS:+ ${ATUIN_INIT_FLAGS}})"
		fi
	fi

	unset BLING_SHELL
	;;
esac
