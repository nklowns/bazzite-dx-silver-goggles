#!/usr/bin/env bash
# scripts/build-awcc.sh
# Build AWCC RPM inside a Fedora container.

set -euo pipefail

AWCC_SPEC="${1:-awcc.spec}"
SOURCE_PATH="${2:-}"
OUTPUT_DIR="${3:-files/rpm-ostree}"

if grep -q "dev" <<<"${AWCC_SPEC}" || [ -n "${SOURCE_PATH}" ]; then
	MODE="Development (Local Source)"
	[ -z "${SOURCE_PATH}" ] && {
		echo "Error: SOURCE_PATH required for dev spec"
		exit 1
	}
else
	MODE="Stable (Upstream Fetch)"
fi

echo "Building AWCC RPM: ${MODE}"
[ -n "${SOURCE_PATH}" ] && echo "Source: ${SOURCE_PATH}"

mkdir -p "${OUTPUT_DIR}"

MOUNTS=("-v" "$(pwd)/build_files:/build_files:ro,z")
MOUNTS+=("-v" "$(pwd)/${OUTPUT_DIR}:/output:z")

if [ -n "${SOURCE_PATH}" ]; then
	MOUNTS+=("-v" "$(readlink -f "${SOURCE_PATH}"):/tmp/AWCC_SRC:ro,z")
fi

# Run the build container
# PODMAN variable should be passed or we use podman by default
PODMAN="${PODMAN:-podman}"

"${PODMAN}" run --rm "${MOUNTS[@]}" "fedora:43" bash -c "
    set -euo pipefail
    dnf5 install -y --setopt=install_weak_deps=False rpm-build rpmdevtools dnf5-plugins cmake ninja-build meson gcc-c++ git libX11-devel libxkbcommon-devel glfw-devel systemd-devel libudev-devel libglvnd-devel wayland-devel

    rpmdev-setuptree
    WORKDIR=\$(mktemp -d)
    cd \"\${WORKDIR}\"

    if [ -d \"/tmp/AWCC_SRC\" ]; then
        # Build from local source
        cp \"/build_files/${AWCC_SPEC}\" ./awcc-local.spec
        sed -i \"s/^Version:.*/Version: dev.local/\" ./awcc-local.spec
        sed -i \"s/^Release:.*/Release: \$(date +%s)/\" ./awcc-local.spec
        sed -i \"s|^Source0:.*|Source0: awcc-dev.local.tar.gz|\" ./awcc-local.spec
        sed -i \"s|^%autosetup.*|%autosetup -n awcc-dev.local|\" ./awcc-local.spec
        sed -i \"/^%global commit/d\" ./awcc-local.spec
        sed -i \"/^%global shortcommit/d\" ./awcc-local.spec

        mkdir -p \"awcc-dev.local\"
        cp -r /tmp/AWCC_SRC/. \"awcc-dev.local/\"
        tar -czf \"awcc-dev.local.tar.gz\" \"awcc-dev.local/\"
        cp \"awcc-dev.local.tar.gz\" ~/rpmbuild/SOURCES/

        rpmbuild -ba --define \"_sourcedir \${WORKDIR}\" ./awcc-local.spec
    else
        # Build stable release (fetch source defined in spec)
        cp \"/build_files/${AWCC_SPEC}\" ./awcc-stable.spec
        spectool -g -C ~/rpmbuild/SOURCES/ ./awcc-stable.spec
        rpmbuild -ba ./awcc-stable.spec
    fi

    # Copy output RPM (exclude debuginfo)
    find ~/rpmbuild/RPMS/x86_64/ -name \"awcc-*.rpm\" ! -name \"*debug*\" -exec cp {} /output/awcc-dev.rpm \;
"
echo "Build complete: ${OUTPUT_DIR}/awcc-dev.rpm"
