#!/usr/bin/bash
set -ouex pipefail

# shellcheck source=/dev/null
source /usr/lib/ublue/setup-services/libsetup.sh

version-script sunshine-graphical-session-fix user 3 || exit 0

# Homebrew's generated sunshine.service is WantedBy=default.target, which can
# start before the Wayland session is up. graphical-session.target alone is
# not a reliable gate: on NVIDIA/prime setups plasma-kwin_wayland.service
# itself can take 20-30s to come up AFTER the target is already marked
# active. If sunshine (or anything else) D-Bus-activates
# plasma-xdg-desktop-portal-kde.service before kwin_wayland exists, the
# portal's Qt backend has no display to connect to and coredumps outright —
# and since it's Type=dbus with Restart=no, it never comes back on its own.
# Sunshine then starts with a dead portal, every capture/encoder attempt
# fails (including software), and streaming stays broken until the service
# is manually restarted once kwin is actually up. Ordering after kwin_wayland
# itself (not just the portal) closes the real race.
OVERRIDE_DIR="${HOME}/.config/systemd/user/homebrew.sunshine.service.d"
OVERRIDE_FILE="${OVERRIDE_DIR}/10-graphical-session-fix.conf"

mkdir -p "${OVERRIDE_DIR}"

cat >"${OVERRIDE_FILE}" <<'EOF'
[Unit]
After=graphical-session.target plasma-kwin_wayland.service plasma-xdg-desktop-portal-kde.service
Wants=graphical-session.target plasma-kwin_wayland.service plasma-xdg-desktop-portal-kde.service
EOF

systemctl --user daemon-reload || true

if systemctl --user is-active --quiet homebrew.sunshine.service; then
  systemctl --user restart homebrew.sunshine.service || true
fi
