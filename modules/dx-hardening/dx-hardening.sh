#!/usr/bin/env bash

# Implements build-time hygiene and state pruning.
# Ensures the image is "cold" and free of transient data before publication.
set -euo pipefail

SanitizeBuildRepositories() {
	# We remove ALL transient repositories, including cloud-hypervisor,
	# to prevent metadata drift on the atomic host.
	local target_patterns=("_copr" "vscode" "docker" "home:cloud-hypervisor")

	for pattern in "${target_patterns[@]}"; do
		find /etc/yum.repos.d/ -maxdepth 1 -name "*.repo" \
			-exec grep -l "$pattern" {} + \
			-print0 2>/dev/null | xargs -0 -r rm || true
	done
}

PurgeTransientState() {
	rm -rf /var/cache/* /var/log/* 2>/dev/null || true
	rm -rf /var/roothome/.[!.]* /var/roothome/..?* 2>/dev/null || true
}

EnforceDirectorySkeleton() {
	local skeletal_paths=("/var/lib" "/var/log" "/var/cache" "/var/tmp" "/var/roothome" "/var/opt")

	for path in "${skeletal_paths[@]}"; do
		mkdir -p "$path"
	done

	chmod 1777 /var/tmp
}

# --- Execution ---
echo "::group::🛡️ [dx-hardening] Enforcing Build-Time Hygiene..."
SanitizeBuildRepositories
PurgeTransientState
EnforceDirectorySkeleton
echo "::endgroup::"
