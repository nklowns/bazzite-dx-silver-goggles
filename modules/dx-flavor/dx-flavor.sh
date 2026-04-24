#!/usr/bin/env bash
set -euo pipefail

readonly IMAGE_INFO_PATH="/usr/share/ublue-os/image-info.json"
readonly OS_RELEASE_PATH="/usr/lib/os-release"
readonly PRESET_POLICY_PATH="/usr/lib/systemd/system-preset/99-dx-flavor.preset"

# --- Policy Dispatcher ---

PublishImageMetadata() {
	local vendor="${IMAGE_VENDOR:-ublue-os}"
	local name="${IMAGE_NAME:-bazzite-dx}"
	local ref="ostree-image-signed:docker://ghcr.io/$vendor/$name"
	local fedora_version
	fedora_version=$(awk -F= '/VERSION_ID/ {print $2}' /etc/os-release | tr -d '"')

	# Atomic write to prevent partial configuration during build interruptions
	local temp_info
	temp_info=$(mktemp -p "$(dirname "$IMAGE_INFO_PATH")")

	cat >"$temp_info" <<EOF
{
  "image-name": "$name",
  "image-vendor": "$vendor",
  "image-ref": "$ref",
  "image-tag": "latest",
  "fedora-version": "$fedora_version"
}
EOF
	mv "$temp_info" "$IMAGE_INFO_PATH"
}

ApplyKdeBranding() {
	local kde_config="/etc/xdg/kcm-about-distrorc"

	if [[ "$IMAGE_NAME" =~ "gnome" ]] || [[ ! -f "$kde_config" ]]; then
		return 0
	fi

	sed -i "s|^Website=.*|Website=https://dev.bazzite.gg|" "$kde_config"
	if [[ "$IMAGE_NAME" =~ "nvidia" ]]; then
		sed -i "s/^Variant=.*/Variant=DX (NVIDIA)/" "$kde_config"
	else
		sed -i "s/^Variant=.*/Variant=DX/" "$kde_config"
	fi
}

EnforceDisplayManagerPolicy() {
	mkdir -p "$(dirname "$PRESET_POLICY_PATH")"

	# Strategy: Declarative enablement via presets.
	# We avoid 'systemctl enable' to prevent /etc state drift in the OCI layer.
	if [[ "$IMAGE_NAME" =~ "gnome" ]]; then
		echo "enable gdm.service" >"$PRESET_POLICY_PATH"
		echo "disable sddm.service" >>"$PRESET_POLICY_PATH"
		rm -rf /etc/sddm.conf.d/
	else
		echo "enable sddm.service" >"$PRESET_POLICY_PATH"
		echo "disable gdm.service" >>"$PRESET_POLICY_PATH"
	fi
}

SanitizeKdeInteractiveConfig() {
	local config="/etc/xdg/kdeglobals"
	[[ -f "$config" ]] || return 0

	sed -i -E \
		-e 's/^(action\/switch_user)=false/\1=true/' \
		-e 's/^(action\/start_new_session)=false/\1=true/' \
		-e 's/^(action\/lock_screen)=false/\1=true/' \
		"$config"
}

ApplyWorkstationLifecyclePolicy() {
	# Purge handheld-specific artifacts on desktop-oriented flavors
	rm -f /etc/sddm.conf.d/steamos.conf \
		/etc/sddm.conf.d/virtualkbd.conf \
		/etc/sddm.conf.d/zz-steamos-autologin.conf

	if [[ "$IMAGE_NAME" =~ "deck" ]]; then
		echo "enable bazzite-autologin.service" >>"$PRESET_POLICY_PATH"
	else
		echo "disable bazzite-autologin.service" >>"$PRESET_POLICY_PATH"
	fi
}

OptimizeApplicationVisibility() {
	# Show critical interactive tools hidden by upstream policy
	local desktop_entry="/usr/share/applications/input-remapper-gtk.desktop"
	[[ -f "$desktop_entry" ]] && sed -i 's|^NoDisplay=.*|NoDisplay=false|' "$desktop_entry" || true
}

RegisterBazaarBlocklist() {
	local bazaar_main="/usr/share/ublue-os/bazaar/main.yaml"
	local dx_blocklist="/usr/share/ublue-os/bazaar/blocklist-dx.yaml"

	[[ -f "$bazaar_main" ]] && [[ -f "$dx_blocklist" ]] || return 0

	# Inject DX blocklist into the Bazaar main orchestration file
	sed -i 's@override-eol-markings@  - /usr/share/ublue-os/bazaar/blocklist-dx.yaml\noverride-eol-markings@g' "$bazaar_main"
}

# --- Execution Matrix ---

# Domain: Identity & Metadata
PublishImageMetadata
ApplyKdeBranding

# Domain: System & Service Policy
RegisterBazaarBlocklist
EnforceDisplayManagerPolicy
ApplyWorkstationLifecyclePolicy

# Domain: User Experience Optimization
SanitizeKdeInteractiveConfig
OptimizeApplicationVisibility
