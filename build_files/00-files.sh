#!/usr/bin/env bash
# Install the image overlay first: everything after this may modify what it drops.
set -euo pipefail

echo "Copying system_files overlay onto /"
cp -a "${CONTEXT_PATH}/files/system/." /
