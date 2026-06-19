#!/usr/bin/env bash

# Silver Goggles Integrity Engine v3 (Enterprise Edition)
# Pattern: Registry-Driven Validation (Contract-over-Implementation)
set -euo pipefail

# --- Core Configuration ---
readonly CLR_PASS='\033[0;32m'
readonly CLR_FAIL='\033[0;31m'
readonly CLR_WARN='\033[0;33m'
readonly CLR_RESET='\033[0m'

# --- Registry: The Image Contract (1:1 Technical Parity) ---
# Structure: "Provider|AssetPath|Description|Severity(Error/Warn)"
readonly AUDIT_REGISTRY=(
	"group|docker|Security Group: Docker|Error"
	"group|libvirt|Security Group: Libvirt|Error"
	"group|incus-admin|Security Group: Incus|Error"
	"group|adbusers|Security Group: ADB|Error"
	"group|dialout|Security Group: Dialout|Error"
	"group|input|Security Group: Input|Error"
	"group|video|Security Group: Video|Error"
	"group|render|Security Group: Render|Error"
	"group|plugdev|Security Group: Plugdev|Error"

	"file|/usr/lib/udev/rules.d/51-android.rules|Asset: Android Rules|Error"
	"file|/usr/lib/udev/rules.d/99-g15-thermal.rules|Asset: G15 Thermal Rules|Error"
	"file|/usr/lib/systemd/system/g15-thermal.service|Asset: G15 Thermal Service|Error"
	"file|/usr/lib/systemd/system/awccd.service|Asset: AWCC Service|Error"
	"file|/usr/lib/modules-load.d/ip_tables.conf|Asset: IP Tables Config|Error"
	"file|/usr/libexec/bazzite-dx-groups|Asset: DX Groups Orchestrator|Error"
	"file|/usr/libexec/bazzite-dx-virt-lib|Asset: Virt Shared Library|Error"
	"file|/usr/lib/systemd/system/bazzite-dx-groups.service|Asset: DX Groups Service|Error"
	"file|/etc/profile.d/brew.sh|Shield: Brew Profile|Error"
	"file|/etc/profile.d/brew-bash-completion.sh|Shield: Brew Completion|Error"
	"file|/usr/share/fish/vendor_conf.d/ublue-brew.fish|Shield: Brew Fish Config|Error"
	"file|/etc/profile.d/zz-bazzite-dx-bling.sh|Shield: Bling Wrapper (sh)|Error"
	"file|/usr/share/fish/vendor_conf.d/zz-bazzite-dx-bling.fish|Shield: Bling Wrapper (fish)|Warn"
	"file|/usr/lib/environment.d/bazzite-dx.conf|Policy: DX Environment Defaults|Error"
	"file|/usr/lib/environment.d/homebrew.conf|Policy: Homebrew System Environment|Error"
	"file|/usr/share/ublue-os/user-setup.hooks.d/40-bazzite-dx-env.sh|UX: Mise Shims Env Hook|Error"

	"file|/usr/lib/systemd/system/docker.socket|Unit: Docker Socket|Error"
	"file|/usr/lib/systemd/system/podman.socket|Unit: Podman Socket|Error"
	"file|/usr/lib/systemd/system-preset/99-dx-flavor.preset|Unit: DX Flavor Preset|Error"

	"target|graphical.target|Policy: Default Graphical Target|Warn"

	"bin|docker|Tool: Docker|Error"
	"bin|podman|Tool: Podman|Error"
	"bin|kcli|Tool: KCLI|Error"
	"bin|bpftop|Tool: bpftop|Error"
	"bin|cloud-hypervisor|Tool: Cloud-Hypervisor|Error"
	"bin|looking-glass-client|Tool: Looking Glass Client|Error"
	"bin|g15-status|Tool: G15 Status|Error"
	"bin|bling-check|Tool: Bling Check|Error"

	"file|/usr/libexec/bazzite-dx-virt-setup|Asset: Virt Setup Script|Error"
	"file|/usr/libexec/bazzite-dx-manage-vfio|Asset: VFIO Manager|Error"
	"file|/usr/libexec/bazzite-dx-kvmfr-setup|Asset: KVMFR Setup|Error"
	"file|/usr/libexec/bazzite-dx-win-utils|Asset: Win Guest Utils|Error"
	"file|/usr/lib/udev/rules.d/99-kvmfr.rules|Asset: KVMFR Udev Rules|Error"
	"file|/usr/lib/modules-load.d/kvmfr.conf|Asset: KVMFR Module Config|Error"
	"file|/etc/udev/rules.d/99-kvmfr.rules|Mask: KVMFR Udev (opt-out default)|Error"
	"file|/etc/modules-load.d/kvmfr.conf|Mask: KVMFR Autoload (opt-out default)|Error"
	"file|/usr/share/selinux/packages/kvmfr.cil|Asset: SELinux KVMFR Policy|Error"
	"file|/usr/share/selinux/packages/pipewire.cil|Asset: SELinux PipeWire Policy|Error"

	"file|/usr/share/ublue-os/homebrew/cli.Brewfile|Brew: CLI Suite|Error"
	"file|/usr/share/ublue-os/homebrew/ai-tools.Brewfile|Brew: AI Suite|Error"
	"file|/usr/share/ublue-os/homebrew/cncf.Brewfile|Brew: CNCF Suite|Error"
	"file|/usr/share/ublue-os/homebrew/dx-build.Brewfile|Brew: DX Build Suite|Error"
	"file|/usr/share/ublue-os/homebrew/dx-fonts.Brewfile|Brew: DX Fonts Suite|Error"
	"file|/usr/share/ublue-os/homebrew/silver-goggles.Brewfile|Brew: Silver Goggles Suite|Error"

	"desktop|/usr/share/applications/input-remapper-gtk.desktop|UX: Input Remapper Visibility|Error"
)

# --- Providers ---

CheckGroup() {
	local target="$1"
	getent group "$target" >/dev/null || grep -rqE "^g $target\b" /usr/lib/sysusers.d/
}

CheckFile() { [[ -e "$1" ]] || [[ -L "$1" ]]; }  # -e follows symlinks; -L catches dangling ones
CheckBinary() { command -v "$1" >/dev/null; }
CheckTarget() { [[ -L "/etc/systemd/system/default.target" ]] && [[ $(readlink /etc/systemd/system/default.target) =~ $1 ]]; }

# Desktop provider is silent if file is missing (Parity with original behavior)
CheckDesktop() {
	if [[ ! -f "$1" ]]; then return 0; fi
	! grep -qi "NoDisplay=true" "$1"
}

# --- Engine ---

RunAudit() {
	local total_failed=0
	echo "::group::🚀 Executing Silver Goggles Integrity Engine"

	for entry in "${AUDIT_REGISTRY[@]}"; do
		IFS='|' read -r provider target description severity <<<"$entry"
		local success=0
		case "$provider" in
		group) success=$(CheckGroup "$target" && echo 1 || echo 0) ;;
		file) success=$(CheckFile "$target" && echo 1 || echo 0) ;;
		bin) success=$(CheckBinary "$target" && echo 1 || echo 0) ;;
		target) success=$(CheckTarget "$target" && echo 1 || echo 0) ;;
		desktop) success=$(CheckDesktop "$target" && echo 1 || echo 0) ;;
		esac

		if [[ "$success" -eq 1 ]]; then
			printf "[ %bPASS%b ] %s\n" "$CLR_PASS" "$CLR_RESET" "$description"
		else
			if [[ "$severity" == "Error" ]]; then
				printf "[ %bFAIL%b ] %s (Target: %s)\n" "$CLR_FAIL" "$CLR_RESET" "$description" "$target"
				total_failed=$((total_failed + 1))
			else
				printf "[ %bWARN%b ] %s (Target: %s)\n" "$CLR_WARN" "$CLR_RESET" "$description" "$target"
			fi
		fi
	done

	# Hygiene Gate (Informative only, matches original)
	local residuals
	residuals=$(find /etc/yum.repos.d/ -maxdepth 1 -name "*.repo" -exec grep -lE "_copr|vscode|docker|home:cloud-hypervisor" {} + || true)
	if [[ -z "$residuals" ]]; then
		printf "[ %bPASS%b ] Image Purity: Repository hygiene verified\n" "$CLR_PASS" "$CLR_RESET"
	else
		printf "[ %bWARN%b ] Image Purity: Residual repositories detected: %s\n" "$CLR_WARN" "$CLR_RESET" "$residuals"
	fi

	echo "::endgroup::"
	[[ "$total_failed" -gt 0 ]] && {
		echo "❌ Critical Failure: $total_failed integrity violations."
		exit 1
	}
	printf "\n%b✔ Integrity Audit: 100%% COMPLIANT.%b\n" "$CLR_PASS" "$CLR_RESET"
}

RunAudit
