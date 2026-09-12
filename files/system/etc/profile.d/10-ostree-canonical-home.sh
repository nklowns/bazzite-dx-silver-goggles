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
