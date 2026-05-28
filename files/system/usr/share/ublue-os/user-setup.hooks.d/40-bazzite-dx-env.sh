#!/usr/bin/bash
# Bazzite-DX: Write mise shims path to user environment.d for GUI app compatibility.
# Brew paths and HOMEBREW_* vars are system-wide via /usr/lib/environment.d/homebrew.conf
# Runs once per user (version-script guard). Bump version to force re-run on image update.

set -ouex pipefail

# shellcheck source=/dev/null
source /usr/lib/ublue/setup-services/libsetup.sh

version-script bazzite-dx-env user 1 || exit 0

ENV_FILE="$HOME/.config/environment.d/95-bazzite-dx-env.conf"
mkdir -p "$(dirname "$ENV_FILE")"

# Mise shims — always written, even if mise isn't installed yet.
# Path is inert until mise is installed via Brewfile; no conditional needed.
# Prepended so mise-managed runtimes shadow system tools (correct for a version manager).
cat >"$ENV_FILE" <<'EOF'
# Managed by Bazzite-DX (bazzite-dx-env v1)
# Brew paths: /usr/lib/environment.d/homebrew.conf

# Mise shims — prepended for correct version manager priority
PATH=${HOME}/.local/share/mise/shims:${PATH}
EOF
