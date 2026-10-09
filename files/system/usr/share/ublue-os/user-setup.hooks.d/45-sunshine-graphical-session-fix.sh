#!/usr/bin/bash
set -ouex pipefail

# shellcheck source=/dev/null
source /usr/lib/ublue/setup-services/libsetup.sh

version-script sunshine-graphical-session-fix user 12 || exit 0

# Sunshine runs as the flatpak dev.lizardbyte.app.Sunshine under the canonical
# /usr/lib/systemd/user/sunshine.service (Homebrew build retired: it cannot load the host's Intel VAAPI
# driver, so it pinned NVENC on the dGPU). Clean up legacy unit files that shadow or alias it.
rm -f "${HOME}/.config/systemd/user/default.target.wants/homebrew.sunshine.service" \
	"${HOME}/.config/systemd/user/default.target.wants/sunshine.service" \
	"${HOME}/.config/systemd/user/homebrew.sunshine.service"
rm -rf "${HOME}/.config/systemd/user/homebrew.sunshine.service.d"
# A user-level copy of the old brew unit hides the image unit entirely.
if grep -qs 'linuxbrew' "${HOME}/.config/systemd/user/sunshine.service"; then
	rm -f "${HOME}/.config/systemd/user/sunshine.service"
fi
# The flatpak's own unit (from additional-install.sh) also claims Alias=sunshine.service.
if [ -f "${HOME}/.config/systemd/user/app-dev.lizardbyte.app.Sunshine.service" ]; then
	systemctl --user disable app-dev.lizardbyte.app.Sunshine.service || true
	rm -f "${HOME}/.config/systemd/user/app-dev.lizardbyte.app.Sunshine.service"
fi

OLD_DIR="${HOME}/.config/sunshine"
SUNSHINE_CONF_DIR="${HOME}/.var/app/dev.lizardbyte.app.Sunshine/config/sunshine"
SUNSHINE_CONF="${SUNSHINE_CONF_DIR}/sunshine.conf"

# Move the brew-era config (pairing credentials, apps, state) to the flatpak location ourselves, so paths
# inside sunshine.conf/apps.json are rewritten too (the flatpak's SUNSHINE_MIGRATE_CONFIG only moves files).
if [ -d "${OLD_DIR}" ] && [ ! -L "${OLD_DIR}" ] && [ ! -e "${SUNSHINE_CONF}" ]; then
	mkdir -p "$(dirname "${SUNSHINE_CONF_DIR}")"
	rm -rf "${SUNSHINE_CONF_DIR}"
	mv "${OLD_DIR}" "${SUNSHINE_CONF_DIR}"
	for f in sunshine.conf apps.json; do
		[ -f "${SUNSHINE_CONF_DIR}/${f}" ] && sed -i "s|${OLD_DIR}/|${SUNSHINE_CONF_DIR}/|g; s|/var${OLD_DIR}/|${SUNSHINE_CONF_DIR}/|g" "${SUNSHINE_CONF_DIR}/${f}"
	done
fi
mkdir -p "${SUNSHINE_CONF_DIR}"
touch "${SUNSHINE_CONF}"

set_sunshine_key() {
	local key="$1"
	local val="$2"
	if grep -q "^\s*${key}\s*=" "${SUNSHINE_CONF}"; then
		sed -i "s|^\s*${key}\s*=.*|${key} = ${val}|" "${SUNSHINE_CONF}"
	else
		echo "${key} = ${val}" >>"${SUNSHINE_CONF}"
	fi
}

set_sunshine_key "origin_web_ui_allowed" "pc"
set_sunshine_key "upnp" "disabled"
set_sunshine_key "color_range" "2"
# The flatpak cannot do KMS capture; KWin ScreenCast is the supported path on Plasma.
set_sunshine_key "capture" "kwin"
# NVENC fallback tuning (only used when no Intel iGPU is present).
set_sunshine_key "nv_preset" "p1"
set_sunshine_key "nv_tune" "ll"
set_sunshine_key "nv_rc" "vbr"

# Prefer NVENC on NVIDIA hosts (Dell G15 dGPU) for ultra-low latency game/desktop streaming.
# Only fall back to Intel VAAPI when no NVIDIA GPU is detected.
HAS_NVIDIA=0
for v in /sys/class/drm/card*/device/vendor; do
	if [ -f "$v" ] && [ "$(cat "$v" 2>/dev/null)" = "0x10de" ]; then
		HAS_NVIDIA=1
		break
	fi
done

if [ "$HAS_NVIDIA" -eq 1 ]; then
	# Remove any stale VAAPI overrides so Sunshine defaults to NVENC
	sed -i '/^\s*encoder\s*=/d' "${SUNSHINE_CONF}"
	sed -i '/^\s*adapter_name\s*=/d' "${SUNSHINE_CONF}"
else
	INTEL_RENDER=""
	for node in /sys/class/drm/renderD*; do
		if [ "$(cat "${node}/device/vendor" 2>/dev/null)" = "0x8086" ]; then
			INTEL_RENDER="/dev/dri/$(basename "${node}")"
			break
		fi
	done
	if [ -n "${INTEL_RENDER}" ]; then
		set_sunshine_key "encoder" "vaapi"
		set_sunshine_key "adapter_name" "${INTEL_RENDER}"
	fi
fi

# Wake the panel before each stream via declarative host script (/usr/bin/bazzite-dx-display-wake).
if ! grep -q '^\s*global_prep_cmd\s*=' "${SUNSHINE_CONF}"; then
	echo 'global_prep_cmd = [{"do":"flatpak-spawn --host /usr/bin/bazzite-dx-display-wake","undo":""}]' >>"${SUNSHINE_CONF}"
else
	# Upgrade legacy wake.sh path to declarative flatpak-spawn
	sed -i 's|.*wake\.sh.*|global_prep_cmd = [{"do":"flatpak-spawn --host /usr/bin/bazzite-dx-display-wake","undo":""}]|' "${SUNSHINE_CONF}"
fi

# KWin only exposes zkde_screencast_unstable_v1 to clients whose desktop file asks for it. Flatpak apps are
# matched by app id, and ~/.local/share/applications shadows the exported entry, so the grant stays scoped
# to Sunshine (instead of the global KWIN_WAYLAND_NO_PERMISSION_CHECKS=1 workaround).
mkdir -p "${HOME}/.local/share/applications"
cat >"${HOME}/.local/share/applications/dev.lizardbyte.app.Sunshine.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Sunshine
Comment=Self-hosted game stream host for Moonlight
Exec=/usr/bin/flatpak run --branch=stable --arch=x86_64 --command=sunshine.sh dev.lizardbyte.app.Sunshine
Icon=dev.lizardbyte.app.Sunshine
Categories=RemoteAccess;Network;
X-Flatpak=dev.lizardbyte.app.Sunshine
X-KDE-Wayland-Interfaces=zkde_screencast_unstable_v1
EOF
command -v kbuildsycoca6 >/dev/null && kbuildsycoca6 >/dev/null 2>&1 || true

# Provision multi-monitor display outputs in apps.json and the prep helpers (Notebook & AOC)
if [ -x /usr/libexec/bazzite-dx-sunshine-apps ]; then
	/usr/libexec/bazzite-dx-sunshine-apps || true
fi

systemctl --user daemon-reload || true
systemctl --user enable sunshine.service || true

if systemctl --user is-active --quiet graphical-session.target 2>/dev/null; then
	systemctl --user restart sunshine.service || true
fi
