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

	curl -fsSL "$download_url" -o "$temp_zip"

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

# --- Execution ---
echo "::group::🚀 [dx-cockpit] Provisioning Declarative Cockpit Extensions..."
InstallCtop
echo "::endgroup::"
