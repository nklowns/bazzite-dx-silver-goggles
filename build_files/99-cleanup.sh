#!/usr/bin/env bash
# Build hygiene: remove transient repositories, caches and root home contents so
# the published image is cold. Same behaviour as the dx-hardening module.
set -euo pipefail

bash "${CONTEXT_PATH}/modules/dx-hardening/dx-hardening.sh"
