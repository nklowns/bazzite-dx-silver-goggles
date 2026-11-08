#!/usr/bin/env bash
# Identity and display-manager policy. The heavy lifting stays in the existing
# dx-flavor module so phase 1 does not change behaviour; phase 2 folds it in.
set -euo pipefail

bash "${CONTEXT_PATH}/modules/dx-flavor/dx-flavor.sh"

# os-release properties, previously declared inline in the recipe.
OS_RELEASE="/etc/os-release"
[[ -f "$OS_RELEASE" ]] || OS_RELEASE="/usr/lib/os-release"

set_key() {
	local key="$1" value="$2"
	if grep -q "^${key}=" "$OS_RELEASE"; then
		sed -i "s|^${key}=.*|${key}=\"${value}\"|" "$OS_RELEASE"
	else
		printf '%s="%s"\n' "$key" "$value" >>"$OS_RELEASE"
	fi
}

set_key NAME "Bazzite DX"
set_key PRETTY_NAME "Bazzite Developer Experience"
set_key DEFAULT_HOSTNAME "bazzite-dx"
set_key VARIANT_ID "silver-goggles"
set_key VARIANT "Silver Goggles (Dell G15 5520)"
set_key HOME_URL "https://bazzite.gg"
set_key DOCUMENTATION_URL "https://dev.bazzite.gg"
set_key SUPPORT_URL "https://github.com/ublue-os/bazzite/issues"
set_key BUG_REPORT_URL "https://github.com/ublue-os/bazzite/issues"
set_key CPE_NAME "cpe:/o:universal-blue:bazzite-dx"
