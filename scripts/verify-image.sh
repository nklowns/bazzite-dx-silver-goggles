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
# The inner script always exits 0 and prints only the missing names, so a
# non-zero exit here means the container itself failed and must not be
# misreported as a missing package.
pkg_err="$(mktemp)"
if ! missing_pkgs=$(podman run --rm -v "${repo_root}/packages:/packages:ro,Z" "$img" bash -c '
	while IFS= read -r pkg; do
		[[ -z "$pkg" ]] && continue
		if ! rpm -q "$pkg" >/dev/null 2>&1 && ! rpm -q --whatprovides "$pkg" >/dev/null 2>&1; then
			echo "$pkg"
		fi
	done < <(sed -E "s/#.*//" /packages/*.txt | grep -vE "^\s*$" | sort -u)
' 2>"${pkg_err}"); then
	echo "FAIL: container run failed while checking packages"
	cat "${pkg_err}"
	rc=1
elif [[ -n "$missing_pkgs" ]]; then
	echo "MISSING PACKAGES:"
	echo "$missing_pkgs"
	rc=1
fi
echo "::endgroup::"

echo "::group::Overlay files"
file_err="$(mktemp)"
if ! missing_files=$(podman run --rm -v "${repo_root}:/src:ro,Z" "$img" bash -c '
	cd /src || exit 1
	# Build-time inputs are not expected to survive into the image:
	#   etc/yum.repos.d      -> repos removed by 99-cleanup.sh
	#   usr/share/silver-goggles/kmod-staging -> consumed by 70-gpu-unlock.sh
	while IFS= read -r rel; do
		if [[ ! -e "/$rel" && ! -L "/$rel" ]]; then
			echo "/$rel"
		fi
	done < <(find files/system \( -type f -o -type l \) -printf "%P\n" \
		| grep -vE "^(etc/yum.repos.d/|usr/share/silver-goggles/kmod-staging/)" | sort)
' 2>"${file_err}"); then
	echo "FAIL: container run failed while checking overlay files"
	cat "${file_err}"
	rc=1
elif [[ -n "$missing_files" ]]; then
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

	# The image must be able to verify its own updates: key, transport entry and
	# policy all ship inside it, otherwise the signed ostree ref is unusable.
	check "signing key shipped" "test -f /etc/pki/containers/bazzite-dx-silver-goggles.pub"
	check "sigstore transport enabled" "grep -q use-sigstore-attachments /etc/containers/registries.d/nklowns-bazzite-dx-silver-goggles.yaml"

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

if [[ "${EXPECT_GPU_UNLOCK:-0}" == "1" ]]; then
	echo "::group::GPU unlock module"
	if unlock_out=$(podman run --rm "$img" bash -c '
		set -euo pipefail
		shopt -s nullglob
		found=0
		for f in /usr/lib/modules/*/extra/gpu_unlock.ko; do
			found=1
			printf "%s %s\n" "$f" "$(modinfo -F signer "$f")"
		done
		[ "$found" -eq 1 ]
	' 2>/dev/null); then
		echo "ok: gpu_unlock installed"
		echo "$unlock_out"
	else
		echo "FAIL: gpu_unlock.ko missing or unsigned in the image"
		rc=1
	fi
	echo "::endgroup::"
fi

echo "::group::Signature policy"
if podman run --rm "$img" jq -e --arg k 'ghcr.io/nklowns/bazzite-dx-silver-goggles' \
	'.transports.docker[$k][0].type == "sigstoreSigned"' /etc/containers/policy.json >/dev/null 2>&1; then
	echo "ok: policy entry present"
else
	echo "FAIL: policy entry missing from /etc/containers/policy.json"
	rc=1
fi
echo "::endgroup::"

echo "::group::Image labels"
labels=$(podman inspect "$img" --format '{{json .Labels}}')
if jq -e 'has("org.opencontainers.image.version") and has("org.opencontainers.image.revision")' >/dev/null <<<"$labels"; then
	echo "ok: OCI labels present ($(jq -r '."org.opencontainers.image.version"' <<<"$labels"))"
else
	echo "FAIL: OCI labels missing"
	echo "$labels"
	rc=1
fi
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

rm -f "${pkg_err}" "${file_err}"
exit "$rc"
