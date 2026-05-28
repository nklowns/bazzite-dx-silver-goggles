#!/usr/bin/env sh

# Bazzite-DX Silver Goggles: Shell Excellence (Bling)
# Standardized Shell Experience for Bash.
# Located in: /usr/share/ublue-os/silver-goggles/bling.sh

# Check if shell has already been sourced to prevent recursion
# (Allow re-sourcing in interactive shells to ensure hooks are loaded)
if [ "${BLING_SH_SOURCED:-0}" = "1" ]; then
	case $- in
	*i*) ;;
	*) return ;;
	esac
fi
BLING_SH_SOURCED=1
# Ensure it's not exported to child shells (like fish)
unset -v BLING_SH_SOURCED 2>/dev/null
BLING_SH_SOURCED=1

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

# --- Cleanup Ghost References ---
# If PROMPT_COMMAND was inherited but the function is missing, clean it up to avoid errors.
if [ -n "${BASH_VERSION:-}" ]; then
	case "${PROMPT_COMMAND-}" in
	*"_bling_lazy_atuin"*)
		if ! command -v _bling_lazy_atuin >/dev/null 2>&1; then
			PROMPT_COMMAND=$(printf '%s' "${PROMPT_COMMAND}" | sed 's/_bling_lazy_atuin; //g; s/_bling_lazy_atuin//g')
		fi
		;;
	esac
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

	# 2. Mise Runtime Activation (Hooks/Interactive extras)
	if [ "${BLUEFIN_SHELL_ENABLE_MISE:-1}" = "1" ] && [ "$(command -v mise)" ]; then
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
	if [ "${BLUEFIN_SHELL_ENABLE_ATUIN:-1}" = "1" ]; then
		if [ "${BLING_SHELL}" = "bash" ]; then
			_bling_lazy_atuin() {
				# Use a global guard to ensure it only runs once per shell
				[ "${_BLING_ATUIN_INITIALIZED:-0}" = "1" ] && return
				_BLING_ATUIN_INITIALIZED=1

				# Only initialize if atuin is actually available
				if command -v atuin >/dev/null 2>&1; then
					eval "$(atuin init bash${ATUIN_INIT_FLAGS:+ ${ATUIN_INIT_FLAGS}})"
				fi

				# Remove self from PROMPT_COMMAND (safe string substitution)
				PROMPT_COMMAND=$(printf '%s' "${PROMPT_COMMAND}" | sed 's/_bling_lazy_atuin; //g; s/_bling_lazy_atuin//g')

				# Cleanup if it was the only thing in PROMPT_COMMAND
				[ "$PROMPT_COMMAND" = "; " ] && PROMPT_COMMAND=""

				unset -f _bling_lazy_atuin
			}
			# Prepend to PROMPT_COMMAND only if not already present
			case "${PROMPT_COMMAND-}" in
			*"_bling_lazy_atuin"*) ;;
			*)
				if [ -z "${PROMPT_COMMAND-}" ]; then
					PROMPT_COMMAND="_bling_lazy_atuin"
				else
					PROMPT_COMMAND="_bling_lazy_atuin; $PROMPT_COMMAND"
				fi
				;;
			esac
		else
			if command -v atuin >/dev/null 2>&1; then
				eval "$(atuin init "${BLING_SHELL}"${ATUIN_INIT_FLAGS:+ ${ATUIN_INIT_FLAGS}})"
			fi
		fi
	fi

	unset BLING_SHELL
	;;
esac
