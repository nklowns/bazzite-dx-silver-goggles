#!/usr/bin/env bash
set -euo pipefail

# --- Image Hygiene Policy ---

SanitizeBuildRepositories() {
	# Remove COPR and transient third-party repositories to ensure image purity
	local target_patterns=("_copr" "home:cloud-hypervisor" "vscode" "docker")

	for pattern in "${target_patterns[@]}"; do
		find /etc/yum.repos.d/ -maxdepth 1 -name "*.repo" -exec grep -l "$pattern" {} + -print0 2>/dev/null | xargs -0 -r rm || true
	done
}

PurgeTransientState() {
	# Clean build-time residuals from stateful directories
	rm -rf /var/cache/* /var/log/* 2>/dev/null || true
	rm -rf /var/roothome/.[!.]* /var/roothome/..?* 2>/dev/null || true
}

EnforceDirectorySkeleton() {
	# Ensure critical stateful mount points exist with canonical permissions
	local skeletal_paths=("/var/lib" "/var/log" "/var/cache" "/var/tmp" "/var/roothome" "/var/opt")

	for path in "${skeletal_paths[@]}"; do
		mkdir -p "$path"
	done
	chmod 1777 /var/tmp
}

# --- Principal Flow ---

echo "::group::[dx-hardening] Enforcing Hygiene Policy..."
SanitizeBuildRepositories
PurgeTransientState
EnforceDirectorySkeleton
echo "::endgroup::"
