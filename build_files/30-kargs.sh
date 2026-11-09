#!/usr/bin/env bash
# Kernel arguments travel with the image through bootc's kargs.d, the same
# mechanism the BlueBuild kargs module used.
#
# Only bootc reads this file. `bootc install` seeds the new deployment from it
# and `bootc upgrade` applies the diff between the previous image's kargs.d and
# the new one. An `rpm-ostree upgrade`/`rebase` does neither: libostree copies
# the `options` line from the merge deployment and inherits it verbatim, and
# neither rpm-ostree 2026.3 nor libostree 2026.4 contains the path at all
# (measured: strings on both binaries, zero hits, while bootc 1.17.1 has it).
#
# So this is the declarative source of truth for bootc-installed systems, and
# `ujust dx-kargs` is the idempotent way to converge an rpm-ostree host onto it.
set -euo pipefail

readonly KARGS_DIR="/usr/lib/bootc/kargs.d"
mkdir -p "$KARGS_DIR"

cat >"${KARGS_DIR}/10-silver-goggles.toml" <<'EOF'
# Managed by bazzite-dx-silver-goggles. See AGENTS.md for why each argument exists.
kargs = [
  "vconsole.keymap=br",
  "kvm_intel.nested=1",
  "kvm.ignore_msrs=1",
  "kvm.report_ignored_msrs=0",
  "intel_iommu=on",
  # "iommu=pt" is deliberately absent: EAC Linux v2 requires IOMMU with
  # passthrough *disabled* (ujust check-anticheat), and strict mode still
  # supports VFIO. Add it per host with `rpm-ostree kargs --append=iommu=pt`
  # if the identity-map performance matters more than the readiness check.
  "nvidia-drm.modeset=1",
]
EOF

echo "Wrote $(wc -l <"${KARGS_DIR}/10-silver-goggles.toml") lines of kernel arguments"
