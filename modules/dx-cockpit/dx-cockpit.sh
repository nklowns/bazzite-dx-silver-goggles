#!/usr/bin/env bash

# Declarative Cockpit Extension Manager
# Installs and updates official third-party Cockpit extensions at image build time.
set -euo pipefail

# --- Pinned Extension Releases ---
readonly CTOP_VERSION="1.1.6"

InstallCtop() {
	echo "Installing Cockpit Top (ctop v${CTOP_VERSION}) extension..."
	local target_dir="/usr/share/cockpit/ctop"
	local temp_zip
	temp_zip=$(mktemp --suffix=.zip)
	local download_url="https://github.com/ismetozalp/ctop/releases/download/v${CTOP_VERSION}/ctop-${CTOP_VERSION}.zip"

	curl --retry 5 --retry-delay 3 --retry-all-errors --connect-timeout 15 --max-time 120 -fsSL "$download_url" -o "$temp_zip"

	local temp_extract
	temp_extract=$(mktemp -d)
	unzip -q "$temp_zip" -d "$temp_extract"

	mkdir -p "$target_dir"
	cp -r "$temp_extract/ctop/"* "$target_dir/"

	rm -rf "$temp_zip" "$temp_extract"

	if [[ ! -f "$target_dir/manifest.json" ]]; then
		echo "ERROR: ctop installation failed - manifest.json missing from $target_dir"
		exit 1
	fi
	echo "Cockpit Top (ctop v${CTOP_VERSION}) installed successfully."
}

PatchPcpChannel() {
	echo "Hardening Cockpit PCP channel against transient instance crashes (PM_ERR_INST_LOG)..."
	local pcp_files
	pcp_files=$(find /usr/lib* -type f -path '*/cockpit/channels/pcp.py' 2>/dev/null || true)

	if [[ -z "$pcp_files" ]]; then
		echo "NOTE: cockpit/channels/pcp.py not found, skipping PCP channel hardening."
		return 0
	fi

	for pcp_file in $pcp_files; do
		if grep -q "except pmapi.pmErr:" "$pcp_file"; then
			echo "PCP channel in $pcp_file already patched."
			continue
		fi

		echo "Patching $pcp_file..."
		python3 - "$pcp_file" <<'EOF'
import sys

filepath = sys.argv[1]
with open(filepath, "r", encoding="utf-8") as f:
    content = f.read()

target = "                        instance_desc = context.pmNameInDom(metric_desc.desc, value.inst)"
replacement = """                        try:
                            instance_desc = context.pmNameInDom(metric_desc.desc, value.inst)
                        except pmapi.pmErr:
                            instance_desc = f"[{value.inst}]\""""

if target in content:
    new_content = content.replace(target, replacement, 1)
    with open(filepath, "w", encoding="utf-8") as f:
        f.write(new_content)
    print(f"Successfully patched {filepath}")
else:
    print(f"WARNING: Target pattern not found in {filepath}")
EOF
	done
}

# --- Execution ---
echo "::group::🚀 [dx-cockpit] Provisioning Declarative Cockpit Extensions..."
InstallCtop
PatchPcpChannel
echo "::endgroup::"

