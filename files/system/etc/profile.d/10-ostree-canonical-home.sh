#!/bin/sh
# Normalizes HOME to /var/home/$USER for OSTree deployments across all login/SSH/TTY shells.
# Ensures path parity with systemd user session and GUI applications.

case "${HOME-}" in
/home/*)
	if [ -d "/var${HOME}" ]; then
		export HOME="/var${HOME}"
	fi
	;;
esac

case "${PWD-}" in
/home/*)
	if [ -d "/var${PWD}" ]; then
		__saved_old="${OLDPWD-}"
		cd "/var${PWD}" 2>/dev/null || true
		[ -n "$__saved_old" ] && OLDPWD="$__saved_old"
		unset __saved_old
	fi
	;;
esac
