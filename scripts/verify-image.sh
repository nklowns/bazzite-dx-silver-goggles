#!/usr/bin/env bash
# Verifies a built image contains what the repository declares.
# Usage: scripts/verify-image.sh <image-ref>
set -euo pipefail

img="${1:?usage: verify-image.sh <image-ref>}"
repo_root="$(cd -P -- "$(dirname -- "$0")/.." && pwd -P)"
rc=0

echo "::group::Packages declared in packages/*.txt"
missing_pkgs=$(podman run --rm -v "${repo_root}/packages:/packages:ro" "$img" bash -c '
	set -euo pipefail
	missing=0
	while IFS= read -r pkg; do
		[[ -z "$pkg" ]] && continue
		if ! rpm -q "$pkg" >/dev/null 2>&1; then
			echo "$pkg"
			missing=1
		fi
	done < <(cat /packages/*.txt | grep -vE "^\s*(#|$)" | sort -u)
	exit "$missing"
')
if [[ -n "$missing_pkgs" ]]; then
	echo "MISSING PACKAGES:"
	echo "$missing_pkgs"
	rc=1
fi
echo "::endgroup::"

echo "::group::Overlay files"
missing_files=$(podman run --rm -v "${repo_root}:/src:ro" "$img" bash -c '
	set -euo pipefail
	missing=0
	cd /src
	while IFS= read -r rel; do
		if [[ ! -e "/$rel" && ! -L "/$rel" ]]; then
			echo "/$rel"
			missing=1
		fi
	done < <(find files/system \( -type f -o -type l \) -printf "%P\n" | sort)
	exit "$missing"
')
if [[ -n "$missing_files" ]]; then
	echo "MISSING FILES:"
	echo "$missing_files"
	rc=1
fi
echo "::endgroup::"

echo "::group::Image contract"
podman run --rm "$img" bash -c '
	set -uo pipefail
	fail=0
	check() { if eval "$2"; then echo "ok: $1"; else echo "FAIL: $1"; fail=1; fi; }

	check "kargs.d present" "test -f /usr/lib/bootc/kargs.d/10-silver-goggles.toml"
	check "os-release VARIANT_ID" "grep -q \"^VARIANT_ID=.silver-goggles\" /usr/lib/os-release"
	check "just imports installed" "grep -q silver-goggles.just /usr/share/ublue-os/just/60-custom.just"
	check "thermald masked" "test -L /etc/systemd/system/thermald.service"
	check "no build repos left" "! ls /etc/yum.repos.d/ | grep -qE \"_copr|vscode|docker|cloud-hypervisor\""
	check "ujust present" "test -x /usr/bin/ujust"
	exit "$fail"
' || rc=1
echo "::endgroup::"

echo "::group::Unit syntax"
unit_fail=$(podman run --rm "$img" bash -c '
	set -uo pipefail
	fail=0
	while IFS= read -r unit; do
		out=$(systemd-analyze verify "$unit" 2>&1 || true)
		out=$(printf "%s\n" "$out" | grep -v "/home/linuxbrew" || true)
		if [[ -n "$out" ]]; then
			printf "%s:\n%s\n" "$unit" "$out"
			fail=1
		fi
	done < <(find /usr/lib/systemd/system /usr/lib/systemd/user -maxdepth 1 \( -name "*.service" -o -name "*.socket" \) 2>/dev/null)
	exit "$fail"
')
if [[ -n "$unit_fail" ]]; then
	echo "$unit_fail"
	rc=1
fi
echo "::endgroup::"

exit "$rc"
