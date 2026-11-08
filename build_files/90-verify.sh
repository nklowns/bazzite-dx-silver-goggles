#!/usr/bin/env bash
# Image contract checks. Phase 3 replaces the growing registry with bootc lint
# plus a real VM boot (bcvk); phase 1 keeps the existing engine untouched.
set -euo pipefail

bash "${CONTEXT_PATH}/modules/dx-verify/dx-verify.sh"
