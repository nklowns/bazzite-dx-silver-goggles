#!/usr/bin/env bash
set -euo pipefail

# dx-verify: High-Velocity Image Integrity Auditor
# Reference: https://github.com/ublue-os/main/blob/main/modules/validate/
# WARNING: Failures here will terminate the build pipeline to prevent non-compliant image publishing.

# --- UI Helpers ---
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

LogInfo() { printf "%binfo:%b %s\n" "${BLUE}" "${NC}" "$1"; }
LogSuccess() { printf "%bpass:%b %s\n" "${GREEN}" "${NC}" "$1"; }
LogError() {
	printf "%berror:%b %s\n" "${RED}" "${NC}" "$1"
	exit 1
}

# --- Domain Auditors ---

AuditSecurityBaseline() {
	LogInfo "Domain: Security & Entitlements"
	local required_groups=("docker" "libvirt" "incus-admin" "adbusers" "dialout" "input" "video" "render" "plugdev")

	for group in "${required_groups[@]}"; do
		if getent group "$group" >/dev/null || grep -rqE "^g $group\b" /usr/lib/sysusers.d/; then
			LogSuccess "Security Group '$group' provisioned."
		else
			LogError "Critical Group '$group' missing."
		fi
	done
}

AuditSystemIntegration() {
	LogInfo "Domain: Hardware & System Integration"
	local assets=(
		"/usr/lib/udev/rules.d/51-android.rules"
		"/usr/lib/udev/rules.d/99-g15-thermal.rules"
		"/usr/lib/systemd/system/g15-thermal.service"
		"/usr/lib/modules-load.d/ip_tables.conf"
		"/usr/lib/modules-load.d/acpi_call.conf"
		"/usr/libexec/bazzite-dx-groups"
		"/usr/lib/systemd/system/bazzite-dx-groups.service"
	)

	for asset in "${assets[@]}"; do
		if [[ -f "$asset" ]]; then
			LogSuccess "Asset '$asset' verified."
		else
			LogError "Asset '$asset' missing."
		fi
	done
}

AuditPolicyCompliance() {
	LogInfo "Domain: Atomic Policy Compliance"

	# Audit critical systemd units
	local units=(
		"/usr/lib/systemd/system/docker.socket"
		"/usr/lib/systemd/system/podman.socket"
		"/usr/lib/systemd/system-preset/99-dx-flavor.preset"
	)
	for unit in "${units[@]}"; do
		if [[ -f "$unit" ]]; then
			LogSuccess "Unit '$unit' present."
		else
			LogError "Unit '$unit' missing."
		fi
	done

	# Ensure default target is graphical for OOTB UI experience
	if [[ -L "/etc/systemd/system/default.target" ]]; then
		local target
		target=$(readlink /etc/systemd/system/default.target)
		if [[ "$target" =~ graphical.target ]]; then
			LogSuccess "Default target: Graphical."
		else
			LogInfo "Default target: $target (Non-standard)."
		fi
	fi
}

AuditDeveloperToolchain() {
	LogInfo "Domain: Developer Experience Tooling"
	local tools=(
		"/usr/bin/docker"
		"/usr/bin/podman"
		"/usr/bin/kcli"
		"/usr/bin/bpftop"
		"/usr/bin/cloud-hypervisor"
	)
	for tool in "${tools[@]}"; do
		if [[ -f "$tool" ]]; then
			LogSuccess "Tool '$tool' verified."
		else
			LogError "Tool '$tool' missing."
		fi
	done
}

AuditWorkstationCustomizations() {
	LogInfo "Domain: Workstation Customizations"
	local brewfiles=(
		"cli.Brewfile"
		"ai-tools.Brewfile"
		"cncf.Brewfile"
		"dx-build.Brewfile"
		"dx-fonts.Brewfile"
		"silver-goggles.Brewfile"
	)
	for file in "${brewfiles[@]}"; do
		local path="/usr/share/ublue-os/homebrew/$file"
		if [[ -f "$path" ]]; then
			LogSuccess "Brewfile '$file' verified."
		else
			LogError "Brewfile '$file' missing."
		fi
	done
}

AuditApplicationVisibility() {
	LogInfo "Domain: User Experience Finalization"

	# Verify critical tools are unhidden
	local input_remapper="/usr/share/applications/input-remapper-gtk.desktop"
	if [[ -f "$input_remapper" ]]; then
		if ! grep -qi "NoDisplay=true" "$input_remapper"; then
			LogSuccess "Input Remapper visibility verified."
		else
			LogError "Input Remapper is still hidden (NoDisplay=true)."
		fi
	fi
}

AuditImagePurity() {
	LogInfo "Domain: Image Purity & Hygiene"
	local residuals
	residuals=$(find /etc/yum.repos.d/ -maxdepth 1 -name "*.repo" -exec grep -lE "_copr|vscode|docker|home:cloud-hypervisor" {} + || true)

	if [[ -z "$residuals" ]]; then
		LogSuccess "Repository hygiene verified."
	else
		LogInfo "Residual repositories detected: $residuals"
	fi
}

# --- Principal Audit Flow ---

echo "::group::🚀 === Bazzite-DX Integrity Audit ==="
AuditSecurityBaseline
AuditSystemIntegration
AuditPolicyCompliance
AuditDeveloperToolchain
AuditWorkstationCustomizations
AuditApplicationVisibility
AuditImagePurity
printf "\n%b✔ Bazzite-DX Integrity: 100%% COMPLIANT.%b\n" "${GREEN}" "${NC}"
echo "::endgroup::"
