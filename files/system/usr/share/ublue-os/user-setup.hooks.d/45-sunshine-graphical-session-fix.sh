#!/usr/bin/bash
set -ouex pipefail

# shellcheck source=/dev/null
source /usr/lib/ublue/setup-services/libsetup.sh

version-script sunshine-graphical-session-fix user 7 || exit 0

# Homebrew's generated sunshine.service is WantedBy=default.target, which can
# start before the Wayland session is up. graphical-session.target alone is
# not a reliable gate: on NVIDIA/prime setups plasma-kwin_wayland.service
# itself can take 20-30s to come up AFTER the target is already marked
# active. Ordering after kwin_wayland (in addition to the portal) narrows
# the race but doesn't close it: the kwin_wayland unit is reported active
# as soon as the process starts, well before the compositor registers its
# RemoteAccess/screencast D-Bus interface. Sunshine's kwin capture method
# needs that interface, not just the process — so it can still fail
# "Unable to initialize capture method" / "Platform failed to initialize"
# right at unit start, and since that failure happens inside sunshine's
# main loop rather than a process crash, systemd never sees a failure to
# restart on. The fix is to actively poll for the interface instead of
# assuming unit-active implies backend-ready.
#
# Wants= on graphical-session.target/kwin_wayland is a trap: homebrew's
# sunshine.service is WantedBy=default.target, and with user lingering
# enabled (e.g. for remote dev tunnels) default.target starts at boot with
# no real login. Wants= there would pull up a whole standalone Plasma
# compositor to satisfy the dependency, grabbing the DRM device before the
# real login session's compositor can - causing the greeter/login session
# to fail to acquire the GPU. Requisite= only checks the target is already
# active (from a real login), never starts it. Likewise, polling via
# `busctl get-property` on a well-known bus name triggers D-Bus service
# activation as a side effect, which resurrects the portal (and therefore
# kwin) even with Wants= removed - `busctl list` only enumerates names
# already on the bus and never activates anything.
OVERRIDE_DIR="${HOME}/.config/systemd/user/homebrew.sunshine.service.d"
OVERRIDE_FILE="${OVERRIDE_DIR}/10-graphical-session-fix.conf"

mkdir -p "${OVERRIDE_DIR}"

cat >"${OVERRIDE_FILE}" <<'EOF'
[Unit]
After=graphical-session.target plasma-kwin_wayland.service plasma-xdg-desktop-portal-kde.service
Requisite=graphical-session.target

[Service]
ExecStartPre=/bin/bash -c 'for i in $(seq 1 30); do busctl --user list 2>/dev/null | grep -q org.freedesktop.portal.Desktop && exit 0; sleep 1; done; echo "screencast portal interface not ready after 30s" >&2; exit 1'
TimeoutStartSec=45
EOF

# Homebrew's [Install] WantedBy=default.target is itself the root design
# flaw, not just a race: default.target starts at boot under user lingering
# with no real login (see Wants= trap note above). Requisite= stops that unit
# from ever hijacking the GPU, but default.target still fires the unit attempt
# at every boot before a real session exists, so it just fails fast and never
# gets retried once the real graphical-session.target comes up later. Retarget
# enablement from default.target to graphical-session.target so it only ever
# starts as a consequence of a genuine login, and does so reliably then.
systemctl --user disable homebrew.sunshine.service 2>/dev/null || true
systemctl --user add-wants graphical-session.target homebrew.sunshine.service || true

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

systemctl --user daemon-reload || true

if systemctl --user is-active --quiet homebrew.sunshine.service; then
	systemctl --user restart homebrew.sunshine.service || true
else
	systemctl --user start homebrew.sunshine.service || true
fi
