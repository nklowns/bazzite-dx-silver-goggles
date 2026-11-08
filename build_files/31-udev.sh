#!/usr/bin/env bash
# Hardware provisioning: udev manifest integrity, adbusers group, and the Dell
# specific bits are all static files; this only guarantees they arrived.
set -euo pipefail

readonly RULES_MANIFEST="/usr/lib/udev/rules.d/51-android.rules"

if [[ ! -f "$RULES_MANIFEST" ]]; then
	echo "CRITICAL: udev manifest '$RULES_MANIFEST' missing from the overlay."
	exit 1
fi

bash "${CONTEXT_PATH}/modules/dx-udev/dx-udev.sh"
