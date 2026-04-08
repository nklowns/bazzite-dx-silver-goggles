#!/usr/bin/env bash

# dx-verify: High-Velocity Image Audit Module
# Purpose: Final hardening and integrity check for Bazzite-DX.

set -euo pipefail

# --- UI Helpers ---
# Use ANSI colors for clearer terminal output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() { echo -e "${BLUE}info:${NC} $1"; }
log_success() { echo -e "${GREEN}pass:${NC} $1"; }
log_error() {
	echo -e "${RED}error:${NC} $1"
	exit 1
}

# --- Audit Functions ---

audit_group() {
	local grp="$1"
	if getent group "$grp" >/dev/null; then
		log_success "Group '$grp' is correctly defined."
	else
		log_error "Group '$grp' is missing from the image!"
	fi
}

audit_file() {
	local file="$1"
	local label="${2:-File}"
	if [[ -f "$file" ]]; then
		log_success "$label '$file' found."
	else
		log_error "Critical $label '$file' is missing!"
	fi
}

audit_binary() {
	local bin="$1"
	if [[ -f "$bin" ]]; then
		log_success "Binary '$bin' is present."
	else
		log_error "Core developer tool '$bin' is missing!"
	fi
}

echo "::group::🚀 === Bazzite-DX Integrity Audit ==="

# 1. Security Groups (sysusers.d)
log_info "Verifying developer-essential groups..."
DX_GROUPS=("docker" "libvirt" "incus-admin" "dialout" "input" "video" "render" "plugdev" "adbusers")
for grp in "${DX_GROUPS[@]}"; do
	audit_group "$grp"
done

# 2. Hardware & System Configuration (udev/tmpfiles)
log_info "Auditing hardware rules and system integration..."
UDEV_FILES=(
	"/usr/lib/modules-load.d/ip_tables.conf"
	"/usr/lib/systemd/system/bazzite-dx-groups.service"
	"/usr/lib/sysusers.d/android-udev.conf"
	"/usr/lib/tmpfiles.d/opt-fix.conf"
	"/usr/lib/udev/rules.d/51-android.rules"
	"/usr/libexec/bazzite-dx-groups"
)
for file in "${UDEV_FILES[@]}"; do
	audit_file "$file" "Configuration file"
done

# 3. Systemd Units (Critical Sockets)
log_info "Auditing important systemd sockets..."
IMPORTANT_UNITS=(
	"/usr/lib/systemd/system/docker.socket"
	"/usr/lib/systemd/system/podman.socket"
)
for unit in "${IMPORTANT_UNITS[@]}"; do
	audit_file "$unit" "Systemd unit"
done

# 4. Core Developer Toolchain
log_info "Verifying core developer binaries..."
CORE_BINARIES=(
	"/usr/bin/docker"
	"/usr/bin/podman"
	"/usr/bin/kcli"
	"/usr/bin/bpftop"
	"/usr/bin/cloud-hypervisor"
)
for bin in "${CORE_BINARIES[@]}"; do
	audit_binary "$bin"
done

# 5. Workstation Flavors (Homebrew Bundles)
log_info "Auditing Workstation Brewfiles..."
BREWFILES=(
	"/usr/share/ublue-os/homebrew/ai-tools.Brewfile"
	"/usr/share/ublue-os/homebrew/cli.Brewfile"
	"/usr/share/ublue-os/homebrew/cncf.Brewfile"
	"/usr/share/ublue-os/homebrew/dx-build.Brewfile"
	"/usr/share/ublue-os/homebrew/dx-fonts.Brewfile"
	"/usr/share/ublue-os/homebrew/silver-goggles.Brewfile"
)
for file in "${BREWFILES[@]}"; do
	audit_file "$file" "Brewfile"
done

# 6. Repository Hygiene (Residual Check)
log_info "Verifying repository cleanliness..."
COPR_REPOS=$(find /etc/yum.repos.d/ -maxdepth 1 -name "*.repo" -printf "%f\n" | grep -E "copr|vscode|docker" || true)
if [[ -n "$COPR_REPOS" ]]; then
	echo -e "${RED}Warning:${NC} Residual repo files detected: $COPR_REPOS"
fi

echo -e "\n${GREEN}✔ Bazzite-DX Integrity: 100% VERIFIED.${NC}"
echo "::endgroup::"
