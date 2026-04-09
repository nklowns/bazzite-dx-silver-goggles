#!/usr/bin/bash
set -ouex pipefail

# shellcheck disable=SC1091
source /usr/lib/ublue/setup-services/libsetup.sh

version-script krdp-vaapi-fix user 1 || exit 0

# Workaround for KRDP blank screen caused by buggy VAAPI drivers
# https://discuss.kde.org/t/krdp-help-blank-screen-on-connect/41952/5
OVERRIDE_DIR="${HOME}/.config/systemd/user/app-org.kde.krdpserver.service.d"
OVERRIDE_FILE="${OVERRIDE_DIR}/override.conf"

mkdir -p "${OVERRIDE_DIR}"

cat > "${OVERRIDE_FILE}" << 'EOF'
[Service]
# Workaround for KRDP blank screen caused by buggy VAAPI drivers
# https://discuss.kde.org/t/krdp-help-blank-screen-on-connect/41952/5
Environment=KPIPEWIRE_FORCE_ENCODER=libx264
Environment=LIBVA_DRIVERS_PATH=/nonexistent
Environment=LIBVA_DRIVER_NAME=dummy
EOF

systemctl --user daemon-reload || true
