#!/usr/bin/env bash
# ==============================================================================
# Declarative KRunner Favorites Configuration for DX Layer
# Automatically ensures 'dx-workspaces' is active in KRunner favorites for users.
# ==============================================================================
set -euo pipefail

# shellcheck source=/dev/null
source /usr/lib/ublue/setup-services/libsetup.sh

version-script krunner-dx-defaults user 1 || exit 0

if [ -f /run/.containerenv ] || [ -f /.dockerenv ]; then
	exit 0
fi

if command -v kwriteconfig6 >/dev/null 2>&1; then
	CURRENT_FAVS=$(kreadconfig6 --file krunnerrc --group Plugins --group Favorites --key plugins 2>/dev/null || true)
	if [[ "$CURRENT_FAVS" != *"dx-workspaces"* ]]; then
		if [[ -z "$CURRENT_FAVS" ]]; then
			NEW_FAVS="krunner_sessions,krunner_powerdevil,krunner_services,krunner_systemsettings,dx-workspaces"
		else
			NEW_FAVS="${CURRENT_FAVS},dx-workspaces"
		fi
		kwriteconfig6 --file krunnerrc --group Plugins --group Favorites --key plugins "$NEW_FAVS"
	fi
fi
