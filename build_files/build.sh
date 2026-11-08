#!/usr/bin/env bash
# Orchestrates the image build. Order matters:
#   overlay -> packages -> services -> kargs -> branding -> justfiles
#   -> gpu-unlock -> initramfs -> verify -> cleanup
set -euo pipefail

CONTEXT_PATH="$(realpath "$(dirname "$0")/..")"
BUILD_SCRIPTS_PATH="$(realpath "$(dirname "$0")")"
export CONTEXT_PATH BUILD_SCRIPTS_PATH

run_scripts() {
	local script
	find "${BUILD_SCRIPTS_PATH}" -maxdepth 1 -iname "[0-9][0-9]-*.sh" -type f -print0 |
		sort --zero-terminated |
		while IFS= read -r -d '' script; do
			printf '::group::=== %s ===\n' "$(basename "$script")"
			bash "$script"
			printf '::endgroup::\n'
		done
}

run_scripts
