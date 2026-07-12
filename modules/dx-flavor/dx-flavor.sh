#!/usr/bin/env bash

# Orchestrates visual identity, display manager policy, and UX optimizations.
set -euo pipefail

# --- Constants & Paths ---
readonly IDENTITY_MANIFEST="/usr/share/ublue-os/image-info.json"
readonly KDE_BRANDING_PATH="/etc/xdg/kcm-about-distrorc"
readonly KDE_GLOBALS_PATH="/etc/xdg/kdeglobals"
readonly SYSTEM_PRESET_DIR="/usr/lib/systemd/system-preset"
readonly PRESET_POLICY_PATH="$SYSTEM_PRESET_DIR/99-dx-flavor.preset"
readonly BAZAAR_MAIN_CONFIG="/usr/share/ublue-os/bazaar/main.yaml"
readonly DX_BLOCKLIST_PATH="/usr/share/ublue-os/bazaar/blocklist-dx.yaml"

PublishSystemMetadata() {
	local name="${IMAGE_NAME:-bazzite-dx}"
	local vendor="${IMAGE_VENDOR:-nklowns}"
	local ref="ostree-image-signed:docker://ghcr.io/$vendor/$name"
	local fedora_version
	fedora_version=$(awk -F= '/VERSION_ID/ {print $2}' /etc/os-release | tr -d '"')

	# Atomic write to prevent partial configuration during build interruptions.
	local temp_info
	temp_info=$(mktemp -p "$(dirname "$IDENTITY_MANIFEST")")
	chmod 644 "$temp_info"

	cat >"$temp_info" <<EOF
{
  "image-name": "$name",
  "image-vendor": "$vendor",
  "image-ref": "$ref",
  "image-tag": "latest",
  "fedora-version": "$fedora_version"
}
EOF
	mv "$temp_info" "$IDENTITY_MANIFEST"
}

ApplyKdeBranding() {
	if [[ "$IMAGE_NAME" =~ "gnome" ]] || [[ ! -f "$KDE_BRANDING_PATH" ]]; then
		return 0
	fi

	sed -i "s|^Website=.*|Website=https://dev.bazzite.gg|" "$KDE_BRANDING_PATH"
	# IMAGE_NAME (bazzite-dx-silver-goggles) carries no flavor hint; the base image does.
	if [[ "$IMAGE_NAME" =~ "nvidia" ]] || [[ "${BASE_IMAGE:-}" =~ "nvidia" ]]; then
		sed -i "s/^Variant=.*/Variant=DX (NVIDIA)/" "$KDE_BRANDING_PATH"
	else
		sed -i "s/^Variant=.*/Variant=DX/" "$KDE_BRANDING_PATH"
	fi
}

EnforceDisplayManagerPolicy() {
	mkdir -p "$SYSTEM_PRESET_DIR"

	if [[ "$IMAGE_NAME" =~ "gnome" ]]; then
		echo "enable gdm.service" >"$PRESET_POLICY_PATH"
		echo "disable sddm.service" >>"$PRESET_POLICY_PATH"
		rm -rf /etc/sddm.conf.d/
	else
		echo "enable sddm.service" >"$PRESET_POLICY_PATH"
		echo "disable gdm.service" >>"$PRESET_POLICY_PATH"
	fi
}

ApplyWorkstationLifecyclePolicy() {
	# Purge handheld-specific artifacts on desktop-oriented flavors.
	rm -f /etc/sddm.conf.d/steamos.conf \
		/etc/sddm.conf.d/virtualkbd.conf \
		/etc/sddm.conf.d/zz-steamos-autologin.conf

	if [[ "$IMAGE_NAME" =~ "deck" ]]; then
		echo "enable bazzite-autologin.service" >>"$PRESET_POLICY_PATH"
	else
		echo "disable bazzite-autologin.service" >>"$PRESET_POLICY_PATH"
	fi
}

SanitizeKdeInteractiveConfig() {
	[[ -f "$KDE_GLOBALS_PATH" ]] || return 0

	sed -i -E \
		-e 's/^(action\/switch_user)=false/\1=true/' \
		-e 's/^(action\/start_new_session)=false/\1=true/' \
		-e 's/^(action\/lock_screen)=false/\1=true/' \
		"$KDE_GLOBALS_PATH"
}

OptimizeApplicationVisibility() {
	local desktop_entry="/usr/share/applications/input-remapper-gtk.desktop"
	[[ -f "$desktop_entry" ]] && sed -i 's|^NoDisplay=.*|NoDisplay=false|' "$desktop_entry" || true
}

RegisterBazaarBlocklist() {
	[[ -f "$BAZAAR_MAIN_CONFIG" ]] && [[ -f "$DX_BLOCKLIST_PATH" ]] || return 0

	# The sed below anchors on this upstream key; if bazzite renames it the
	# substitution becomes a silent no-op. Fail the build instead.
	if ! grep -q "override-eol-markings" "$BAZAAR_MAIN_CONFIG"; then
		echo "CRITICAL: anchor 'override-eol-markings' missing from $BAZAAR_MAIN_CONFIG — blocklist injection would silently no-op."
		exit 1
	fi

	sed -i 's@override-eol-markings@  - /usr/share/ublue-os/bazaar/blocklist-dx.yaml\noverride-eol-markings@g' "$BAZAAR_MAIN_CONFIG"

	if ! grep -q "$DX_BLOCKLIST_PATH" "$BAZAAR_MAIN_CONFIG"; then
		echo "CRITICAL: blocklist registration failed — $DX_BLOCKLIST_PATH not present in $BAZAAR_MAIN_CONFIG after injection."
		exit 1
	fi
}

# --- Execution ---
echo "::group::🚀 [dx-flavor] Orchestrating Image Identity..."
PublishSystemMetadata
ApplyKdeBranding
EnforceDisplayManagerPolicy
ApplyWorkstationLifecyclePolicy
SanitizeKdeInteractiveConfig
OptimizeApplicationVisibility
RegisterBazaarBlocklist
echo "::endgroup::"
