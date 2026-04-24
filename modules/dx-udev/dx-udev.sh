#!/usr/bin/env bash
set -euo pipefail

# dx-udev: Hardware Provisioning Logic
# dx-udev: Hardware Provisioning Module
# Purpose: Manages local hardware access rules and declarative system group requirements.

readonly RULES_SOURCE="/usr/lib/udev/rules.d/51-android.rules"
readonly SYSUSERS_CONFIG="/usr/lib/sysusers.d/android-udev.conf"

verify_udev_rule_integrity() {
	# Reference: Local udev rules are provisioned via files/system to ensure offline build reproducibility.
	if [[ ! -f "$RULES_SOURCE" ]]; then
		echo "CRITICAL: Hardware rules missing from image overlay."
		exit 1
	fi
}

provision_system_groups() {
	# Purpose: Create 'adbusers' for rootless hardware access.
	# Policy: Declarative group management via sysusers.d.
	cat <<EOF >"$SYSUSERS_CONFIG"
g adbusers - -
EOF
}

# Execution Flow
verify_udev_rule_integrity
provision_system_groups

echo "OK: Hardware provisioning finalized."
