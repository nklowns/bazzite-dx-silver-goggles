#!/usr/bin/bash
set -ouex pipefail

# shellcheck source=/dev/null
source /usr/lib/ublue/setup-services/libsetup.sh

version-script sunshine-graphical-session-fix user 2 || exit 0

# Homebrew's generated sunshine.service is WantedBy=default.target, which can
# start before the Wayland session is up. After=graphical-session.target alone
# is not enough: plasma-xdg-desktop-portal-kde.service is Type=dbus with no
# WantedBy (D-Bus activated on demand), so it can come up 10-15s AFTER
# graphical-session.target is already active. Sunshine's kwin capture backend
# needs that portal for the PipeWire screencast handshake — if it starts
# before the portal claims its bus name, capture init fails, every encoder
# (including software) fails in turn, and streaming never works until the
# service is manually restarted. Ordering after the portal unit itself closes
# that race.
OVERRIDE_DIR="${HOME}/.config/systemd/user/homebrew.sunshine.service.d"
OVERRIDE_FILE="${OVERRIDE_DIR}/10-graphical-session-fix.conf"

mkdir -p "${OVERRIDE_DIR}"

cat >"${OVERRIDE_FILE}" <<'EOF'
[Unit]
After=graphical-session.target plasma-xdg-desktop-portal-kde.service
Wants=graphical-session.target plasma-xdg-desktop-portal-kde.service
EOF

systemctl --user daemon-reload || true

if systemctl --user is-active --quiet homebrew.sunshine.service; then
  systemctl --user restart homebrew.sunshine.service || true
fi
