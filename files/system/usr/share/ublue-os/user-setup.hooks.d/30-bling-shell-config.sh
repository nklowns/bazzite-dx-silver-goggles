#!/usr/bin/bash
# Silver Goggles: Deploy default shell configs to $HOME on first login.
# Deploys: starship.toml, atuin/config.toml
# Runs once per user (version-script guard). Will not override existing configs.

set -ouex pipefail

# shellcheck disable=SC1091
source /usr/lib/ublue/setup-services/libsetup.sh

version-script bling-shell-config user 1 || exit 0

SILVER_GOGGLES_DIR="/usr/share/ublue-os/silver-goggles"
CONFIG_DIR="${HOME}/.config"

# Deploy starship prompt config
if [[ ! -f "${CONFIG_DIR}/starship.toml" ]]; then
	install -Dm644 "${SILVER_GOGGLES_DIR}/starship.toml" \
		"${CONFIG_DIR}/starship.toml"
	echo "silver-goggles: deployed default starship.toml"
fi

# Deploy atuin history config
if [[ ! -f "${CONFIG_DIR}/atuin/config.toml" ]]; then
	install -Dm644 "${SILVER_GOGGLES_DIR}/atuin/config.toml" \
		"${CONFIG_DIR}/atuin/config.toml"
	echo "silver-goggles: deployed default atuin/config.toml"
fi
