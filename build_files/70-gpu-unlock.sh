#!/usr/bin/env bash
# Installs the CI-signed gpu_unlock.ko if its vermagic matches this image's kernel.
# Staged through the overlay (system_files/usr/share/silver-goggles/kmod-staging).
# Must run before the initramfs step so dracut can force-load it.
set -euo pipefail

bash "${CONTEXT_PATH}/modules/gpu-unlock/gpu-unlock.sh"
