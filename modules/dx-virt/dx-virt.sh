#!/usr/bin/env bash
set -euo pipefail

# This script runs during the image build process.
# It compiles and prepares the KVMFR SELinux policy.

CompileSeLinuxPolicy() {
	echo "Compiling KVMFR SELinux policy..."
	local policy_dir="/tmp/kvmfr-selinux"
	mkdir -p "$policy_dir"

	cat <<EOF >"$policy_dir/kvmfr.te"
module kvmfr 1.0;
require {
    type device_t;
    type svirt_t;
    class chr_file { open read write map };
}
#============= svirt_t ==============
allow svirt_t device_t:chr_file { open read write map };
EOF

	# checkmodule and semodule_package are required.
	# They should be part of the build environment's base or added via rpm-ostree in the recipe.
	if command -v checkmodule >/dev/null; then
		checkmodule -M -m -o "$policy_dir/kvmfr.mod" "$policy_dir/kvmfr.te"
		mkdir -p "/usr/share/selinux/packages"
		semodule_package -o "/usr/share/selinux/packages/kvmfr.pp" -m "$policy_dir/kvmfr.mod"
		echo "Policy compiled and placed in /usr/share/selinux/packages/kvmfr.pp"
	else
		echo "WARNING: checkmodule not found. Skipping SELinux policy compilation."
		echo "This policy will need to be applied manually or checkpolicy added to build dependencies."
	fi
}

# --- Execution ---
echo "::group::🛡️ [dx-virt] Hardening Virtualization & SELinux..."
CompileSeLinuxPolicy
echo "::endgroup::"
