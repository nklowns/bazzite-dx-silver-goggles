#!/usr/bin/env bash

# Installs the CI-signed gpu_unlock.ko staged at /usr/share/silver-goggles/kmod-staging.
# Fail-soft: a missing or kernel-mismatched module is skipped with a warning, so the
# image still builds (without the unlock) instead of breaking updates.
set -euo pipefail

readonly STAGING="/usr/share/silver-goggles/kmod-staging"
readonly KO="$STAGING/gpu_unlock.ko"

echo "::group::🔓 [gpu-unlock] Installing signed kmod..."

KVER=$(rpm -q kernel-core --qf '%{VERSION}-%{RELEASE}.%{ARCH}\n' | sort -V | tail -1)

if [[ ! -f "$KO" ]]; then
	echo "::warning::gpu-unlock: no staged module; image built WITHOUT unlock"
	echo "::endgroup::"
	exit 0
fi

VERMAGIC=$(modinfo -F vermagic "$KO" | awk '{print $1}')
if [[ "$VERMAGIC" != "$KVER" ]]; then
	echo "::warning::gpu-unlock: vermagic '$VERMAGIC' != image kernel '$KVER'; image built WITHOUT unlock"
	rm -rf "$STAGING"
	echo "::endgroup::"
	exit 0
fi

if ! tail -c 28 "$KO" | grep -q '~Module signature appended~'; then
	echo "::warning::gpu-unlock: staged module is unsigned; image built WITHOUT unlock"
	rm -rf "$STAGING"
	echo "::endgroup::"
	exit 0
fi

install -Dm644 "$KO" "/usr/lib/modules/$KVER/extra/gpu_unlock.ko"
rm -rf "$STAGING"
depmod -a "$KVER"

# 05- sorts before Bazzite's 99-nvidia.conf: nvidia must not bind before gpu_unlock runs.
cat >/usr/lib/dracut/dracut.conf.d/05-gpu-unlock.conf <<'CONF'
force_drivers+=" gpu_unlock "
CONF

echo "gpu-unlock: installed for $KVER"
echo "::endgroup::"
