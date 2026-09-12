#!/bin/sh
# Normalizes HOME to /var/home/$USER for OSTree deployments.
# This ensures graphical applications, IDEs, and user services
# inherit the canonical physical path, preventing split paths,
# duplicate editor tabs, and redundant workspace trust prompts.

case "${HOME-}" in
/home/*)
	if [ -d "/var${HOME}" ]; then
		echo "HOME=/var${HOME}"
	fi
	;;
esac
