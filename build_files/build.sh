#!/bin/bash

set -ouex pipefail

CONTEXT_PATH="/ctx"
BUILD_SCRIPTS_PATH="${CONTEXT_PATH}/build_files"

echo "=== Starting Vespera Build ==="

# Run all numbered scripts in order
for script in ${BUILD_SCRIPTS_PATH}/*-*.sh; do
    if [[ -f "$script" ]]; then
        echo "=== Running $(basename $script) ==="
        bash "$script"
    fi
done

echo "=== Build Complete ==="