#!/usr/bin/env bash

# Manages hardware provisioning and declarative group requirements.
set -euo pipefail

readonly RULES_MANIFEST="/usr/lib/udev/rules.d/51-android.rules"
readonly SYSUSERS_DIR="/usr/lib/sysusers.d"

VerifyUdevRuleIntegrity() {
	if [[ ! -f "$RULES_MANIFEST" ]]; then
		echo "CRITICAL: Hardware manifest '$RULES_MANIFEST' missing."
		exit 1
	fi
}

ProvisionHardwareGroups() {
	local config="$SYSUSERS_DIR/android-udev.conf"
	mkdir -p "$SYSUSERS_DIR"

	cat <<EOF >"$config"
g adbusers - -
EOF
}

# --- Execution ---
echo "::group::🔌 [dx-udev] Provisioning Hardware & Groups..."
VerifyUdevRuleIntegrity
ProvisionHardwareGroups
echo "::endgroup::"
