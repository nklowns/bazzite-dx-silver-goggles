#!/bin/bash
# files/scripts/00-install-awcc.sh
# Installs the Alienware Command Center Companion (AWCC) RPM.
# The RPM is pre-compiled and committed to files/awcc-dev.rpm,
# eliminating the need for a multi-stage builder in the CI pipeline.
set -ouex pipefail

AWCC_RPM="${CONFIG_DIRECTORY}/awcc-dev.rpm"

if [[ ! -f "${AWCC_RPM}" ]]; then
	echo "::error::AWCC RPM not found at ${AWCC_RPM}" >&2
	exit 1
fi

echo "Installing AWCC from bundled RPM: ${AWCC_RPM}"
rpm-ostree install "${AWCC_RPM}"

# Ensure the g15-status helper is executable (deployed via files module)
if [[ -f /usr/bin/g15-status ]]; then
	chmod +x /usr/bin/g15-status
fi

echo "AWCC installation complete."
