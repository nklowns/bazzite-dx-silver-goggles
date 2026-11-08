#!/usr/bin/env bash

# Cockpit tweaks applied at image build time.
#
# The ctop extension is vendored under files/system/usr/share/cockpit/ctop/ and
# needs no network: the release asset returned 504 during a publish run and
# blocked the image. See that directory's VENDORED.md to update it.
set -euo pipefail

VerifyCtopPresent() {
	local manifest="/usr/share/cockpit/ctop/manifest.json"
	if [[ ! -f "$manifest" ]]; then
		echo "ERROR: vendored ctop extension missing ($manifest not found)." >&2
		exit 1
	fi
	echo "Cockpit Top (ctop) present from the image overlay."
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
echo "::group::🚀 [dx-cockpit] Cockpit extensions and channel hardening..."
VerifyCtopPresent
PatchPcpChannel
echo "::endgroup::"
