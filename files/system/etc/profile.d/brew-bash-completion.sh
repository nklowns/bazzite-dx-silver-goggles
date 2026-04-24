#!/usr/bin/env sh
# Bazzite-DX: Homebrew Bash Completion Shield
# Prevents execution of brew binaries during shell initialization in sandboxes.

# Interactive guard (matching brew.sh shield)
case $- in
*i*)
	if [ -d /home/linuxbrew/.linuxbrew ] && [ -z "${BREW_BASH_COMPLETION-}" ]; then
		# Check for recent enough version of bash.
		if [ -n "${BASH_VERSION-}" ]; then
			# Only load if the directory exists, avoid calling 'brew completions link'
			# as it triggers bwrap failures in isolated environments.
			if [ -d /home/linuxbrew/.linuxbrew/etc/bash_completion.d ]; then
				for _rc in /home/linuxbrew/.linuxbrew/etc/bash_completion.d/*; do
					# shellcheck source=/dev/null
					[ -r "$_rc" ] && . "$_rc"
				done
				unset _rc
			fi
			BREW_BASH_COMPLETION=1
			export BREW_BASH_COMPLETION
		fi
	fi
	;;
esac
