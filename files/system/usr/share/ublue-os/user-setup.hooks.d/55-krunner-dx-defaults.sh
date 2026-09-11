#!/usr/bin/env bash
# ==============================================================================
# Declarative KRunner Favorites Configuration for DX Layer
# Automatically ensures 'dx-workspaces' is active in KRunner favorites for users.
# ==============================================================================
set -euo pipefail

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
