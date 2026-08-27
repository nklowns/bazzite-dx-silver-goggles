#!/usr/bin/bash
set -ouex pipefail

# shellcheck source=/dev/null
source /usr/lib/ublue/setup-services/libsetup.sh

version-script sunshine-graphical-session-fix user 9 || exit 0

# Sunshine is natively packaged and managed via canonical /usr/lib/systemd/user/sunshine.service.
# Clean up legacy Homebrew unit files and obsolete drop-ins that targeted default.target.
rm -f "${HOME}/.config/systemd/user/default.target.wants/homebrew.sunshine.service" \
	"${HOME}/.config/systemd/user/default.target.wants/sunshine.service" \
	"${HOME}/.config/systemd/user/homebrew.sunshine.service"

rm -rf "${HOME}/.config/systemd/user/homebrew.sunshine.service.d"

# Ensure Sunshine settings (Web UI localhost security + low-latency NVENC parameters) are declaratively set.
SUNSHINE_CONF_DIR="${HOME}/.config/sunshine"
SUNSHINE_CONF="${SUNSHINE_CONF_DIR}/sunshine.conf"
mkdir -p "${SUNSHINE_CONF_DIR}"
touch "${SUNSHINE_CONF}"

set_sunshine_key() {
	local key="$1"
	local val="$2"
	if grep -q "^\s*${key}\s*=" "${SUNSHINE_CONF}"; then
		sed -i "s/^\s*${key}\s*=.*/${key} = ${val}/" "${SUNSHINE_CONF}"
	else
		echo "${key} = ${val}" >>"${SUNSHINE_CONF}"
	fi
}

set_sunshine_key "origin_web_ui_allowed" "pc"
set_sunshine_key "nv_preset" "p1"
set_sunshine_key "nv_tune" "ll"
set_sunshine_key "nv_rc" "vbr"
set_sunshine_key "color_range" "2"

# Provision multi-monitor display outputs in apps.json (Notebook & AOC, Dual Canvas removed)
if [ -x /usr/libexec/bazzite-dx-sunshine-apps ]; then
	/usr/libexec/bazzite-dx-sunshine-apps || true
fi

systemctl --user daemon-reload || true
systemctl --user enable sunshine.service || true

if systemctl --user is-active --quiet graphical-session.target 2>/dev/null; then
	systemctl --user restart sunshine.service || true
fi
