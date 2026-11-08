#!/usr/bin/env bash
# Cockpit extensions and the PCP channel workaround live in the dx-cockpit module.
set -euo pipefail

bash "${CONTEXT_PATH}/modules/dx-cockpit/dx-cockpit.sh"
