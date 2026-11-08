#!/usr/bin/env bash
# Verifies a built image contains what the repository declares.
# Usage: scripts/verify-image.sh <image-ref>
set -euo pipefail

img="${1:?usage: verify-image.sh <image-ref>}"
repo_root="$(cd -P -- "$(dirname -- "$0")/.." && pwd -P)"
rc=0

echo "::group::Packages declared in packages/*.txt"
# Query by capability as well as by name: Fedora ships some tools under a
# renamed package that Provides: the old name (iotop -> iotop-c), and `rpm -q`
# only matches the package name. The outer `|| true` keeps `set -e` from
# swallowing the list when the inner check exits non-zero.
missing_pkgs=$(podman run --rm -v "${repo_root}/packages:/packages:ro,Z" "$img" bash -c '
	missing=0
	while IFS= read -r pkg; do
		[[ -z "$pkg" ]] && continue
		if ! rpm -q "$pkg" >/dev/null 2>&1 && ! rpm -q --whatprovides "$pkg" >/dev/null 2>&1; then
			echo "$pkg"
			missing=1
		fi
	done < <(cat /packages/*.txt | grep -vE "^\s*(#|$)" | sort -u)
	exit "$missing"
' 2>&1) || true
if [[ -n "$missing_pkgs" ]]; then
	echo "MISSING PACKAGES:"
	echo "$missing_pkgs"
	rc=1
fi
echo "::endgroup::"

echo "::group::Overlay files"
missing_files=$(podman run --rm -v "${repo_root}:/src:ro,Z" "$img" bash -c '
	set -euo pipefail
	missing=0
	cd /src
	while IFS= read -r rel; do
		if [[ ! -e "/$rel" && ! -L "/$rel" ]]; then
			echo "/$rel"
			missing=1
		fi
	done < <(find files/system \( -type f -o -type l \) -printf "%P\n" | grep -v '^etc/yum.repos.d/' | sort)
	# /etc/yum.repos.d is excluded on purpose: those repo files are build-time
	# only and 99-cleanup.sh removes them before the image is published.
	exit "$missing"
' 2>&1) || true
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

	check "kargs.d present" "ls /usr/lib/bootc/kargs.d/*.toml >/dev/null 2>&1 && grep -q 'iommu=pt' /usr/lib/bootc/kargs.d/*.toml"
	check "os-release VARIANT_ID" "grep -q \"^VARIANT_ID=.silver-goggles\" /usr/lib/os-release"
	check "just imports installed" "grep -q silver-goggles.just /usr/share/ublue-os/just/60-custom.just"
	check "thermald masked" "test -L /etc/systemd/system/thermald.service"
	check "no build repos left" "! ls /etc/yum.repos.d/ | grep -qE \"_copr|vscode|docker|cloud-hypervisor\""
	check "ujust present" "test -x /usr/bin/ujust"

	# Alternatives are a feature, not debt: every engine must be present and
	# reachable, and none may shadow another (no podman-docker shim, so `docker`
	# is unambiguously the moby CLI and `podman` stays podman).
	check "docker CLI is moby, not a shim" "rpm -q docker-cli >/dev/null && ! rpm -q podman-docker >/dev/null"
	check "docker.socket enabled" "test -L /etc/systemd/system/sockets.target.wants/docker.socket"
	check "podman.socket enabled" "test -L /etc/systemd/system/sockets.target.wants/podman.socket"
	check "podman CLI present" "command -v podman >/dev/null"
	check "podman compose wrapper present" "command -v podman-compose >/dev/null"
	check "libvirt present" "command -v virsh >/dev/null"
	check "incus present" "command -v incus >/dev/null"
	check "lxc present" "command -v lxc-create >/dev/null"
	check "cloud-hypervisor present" "command -v cloud-hypervisor >/dev/null"
	check "looking-glass client present" "command -v looking-glass-client >/dev/null"
	exit "$fail"
' || rc=1
echo "::endgroup::"

echo "::group::Unit syntax"
# Verify only the units this image ships, not every base unit: in a build
# container many base units reference binaries or devices that do not exist,
# and that noise hides the units we actually own.
unit_fail=$(podman run --rm -v "${repo_root}:/src:ro,Z" "$img" bash -c '
	fail=0
	cd /src/files/system || exit 1
	while IFS= read -r unit; do
		out=$(systemd-analyze verify "/$unit" 2>&1 || true)
		# Two known noise sources: Homebrew is installed at runtime, and the
		# user-slice oomd swap drop-in makes verify report an ordering cycle
		# between app.slice and systemd-oomd that does not happen at boot.
		out=$(printf "%s\n" "$out" | grep -vE "/home/linuxbrew|Found ordering cycle|deleted to break ordering cycle" || true)
		if [[ -n "$out" ]]; then
			printf "%s:\n%s\n" "$unit" "$out"
			fail=1
		fi
	done < <(find usr/lib/systemd etc/systemd -type f \( -name "*.service" -o -name "*.socket" \) -printf "%p\n" 2>/dev/null | sort)
	exit "$fail"
' 2>&1) || true
if [[ -n "$unit_fail" ]]; then
	echo "$unit_fail"
	rc=1
fi
echo "::endgroup::"

exit "$rc"
