#!/usr/bin/bash
set -ouex pipefail

# shellcheck source=/dev/null
source /usr/lib/ublue/setup-services/libsetup.sh

version-script sunshine-graphical-session-fix user 1 || exit 0

# Homebrew's generated sunshine.service is WantedBy=default.target, which can
# start before the Wayland session is up. After= alone does not force
# graphical-session.target into the same transaction, so Sunshine sometimes
# starts before WAYLAND_DISPLAY exists, fails every encoder, and streaming
# never works until the service is manually restarted.
OVERRIDE_DIR="${HOME}/.config/systemd/user/homebrew.sunshine.service.d"
OVERRIDE_FILE="${OVERRIDE_DIR}/10-graphical-session-fix.conf"

mkdir -p "${OVERRIDE_DIR}"

cat >"${OVERRIDE_FILE}" <<'EOF'
[Unit]
After=graphical-session.target
Wants=graphical-session.target
EOF

systemctl --user daemon-reload || true

if systemctl --user is-active --quiet homebrew.sunshine.service; then
  systemctl --user restart homebrew.sunshine.service || true
fi
