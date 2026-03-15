export IMAGE_NAME := env("IMAGE_NAME", "bazzite-dx-silver-goggles")
export DEFAULT_TAG := env("DEFAULT_TAG", "latest")
export BIB_IMAGE := env("BIB_IMAGE", "quay.io/centos-bootc/bootc-image-builder:latest")
export AWCC_SPEC := env("AWCC_SPEC", "awcc.spec")

alias build-vm := build-qcow2
alias rebuild-vm := rebuild-qcow2
alias run-vm := run-vm-qcow2

[private]
default:
    @just --list

# ==============================================================================
# GROUP 1: Management (Maintenance & CI)
# ==============================================================================

# Check Just Syntax
[group('Management')]
check:
    #!/usr/bin/bash
    find . -maxdepth 1 -type f -name "*.just" | while read -r file; do
    	echo "Checking syntax: $file"
    	just --unstable --fmt --check -f $file
    done
    echo "Checking syntax: system_files Justfile"
    just --unstable --fmt --check -f system_files/usr/share/ublue-os/just/60-custom.just
    echo "Checking syntax: Justfile"
    just --unstable --fmt --check -f Justfile

# Fix Just Syntax
[group('Management')]
fix:
    #!/usr/bin/bash
    find . -maxdepth 1 -type f -name "*.just" | while read -r file; do
    	echo "Checking syntax: $file"
    	just --unstable --fmt -f $file
    done
    echo "Fixing syntax: system_files Justfile"
    just --unstable --fmt -f system_files/usr/share/ublue-os/just/60-custom.just
    echo "Checking syntax: Justfile"
    just --unstable --fmt -f Justfile || { exit 1; }

# Runs shell check on all Bash scripts
[group('Management')]
lint:
    #!/usr/bin/env bash
    set -eoux pipefail
    if ! command -v shellcheck &> /dev/null; then
        echo "shellcheck not found locally. Running via podman..."
        /usr/bin/find . -name "*.sh" -type f -exec podman run --rm -v "$PWD:/mnt:Z" docker.io/koalaman/shellcheck-alpine shellcheck /mnt/{} ';'
    else
        /usr/bin/find . -iname "*.sh" -type f -exec shellcheck "{}" ';'
    fi

# Runs shfmt on all Bash scripts
[group('Management')]
format:
    #!/usr/bin/env bash
    set -eoux pipefail
    if ! command -v shfmt &> /dev/null; then
        echo "shfmt not found locally. Running via podman..."
        /usr/bin/find . -name "*.sh" -type f -exec podman run --rm -v "$PWD:/mnt:Z" --entrypoint shfmt docker.io/mvdan/shfmt:latest -w /mnt/{} ';'
    else
        /usr/bin/find . -iname "*.sh" -type f -exec shfmt --write "{}" ';'
    fi

# Run GitHub Actions locally using act
[group('Management')]
act:
    #!/usr/bin/bash
    act -j build_push \
        -P ubuntu-24.04=catthehacker/ubuntu:full-24.04 \
        --privileged

# Clean Repo
[group('Management')]
clean:
    #!/usr/bin/bash
    set -eoux pipefail
    touch _build
    find *_build* -exec rm -rf {} \;
    rm -f previous.manifest.json
    rm -f changelog.md
    rm -f output.env
    rm -f output/

# Sudo Clean Repo
[group('Management')]
[private]
sudo-clean:
    just sudoif just clean

# sudoif bash function
[group('Management')]
[private]
sudoif command *args:
    #!/usr/bin/bash
    function sudoif(){
        if [[ "${UID}" -eq 0 ]]; then
            "$@"
        elif [[ "$(command -v sudo)" && -n "${SSH_ASKPASS:-}" ]] && [[ -n "${DISPLAY:-}" || -n "${WAYLAND_DISPLAY:-}" ]]; then
            /usr/bin/sudo --askpass "$@" || exit 1
        elif [[ "$(command -v sudo)" ]]; then
            /usr/bin/sudo "$@" || exit 1
        else
            exit 1
        fi
    }
    sudoif {{ command }} {{ args }}

# ==============================================================================
# GROUP 2: Image Builds
# ==============================================================================

# Build the image using the specified parameters
[group('Build')]
build $target_image=IMAGE_NAME $tag=DEFAULT_TAG:
    #!/usr/bin/env bash
    BUILD_ARGS=()
    if [[ -n "{{ AWCC_SPEC }}" ]]; then
        BUILD_ARGS+=("--build-arg" "AWCC_SPEC={{ AWCC_SPEC }}")
    fi
    if [[ -z "$(git status -s)" ]]; then
        BUILD_ARGS+=("--build-arg" "SHA_HEAD_SHORT=$(git rev-parse --short HEAD)")
    fi
    podman build \
        "${BUILD_ARGS[@]}" \
        --pull=newer \
        --tag "{{ target_image }}:{{ tag }}" \
        .

# Build the image forcing a clean cache (no-cache)
[group('Build')]
build-nocache $target_image=IMAGE_NAME $tag=DEFAULT_TAG:
    #!/usr/bin/env bash
    podman build --no-cache --pull=newer --tag "{{ target_image }}:{{ tag }}" .

# Build the image pointing to a custom Bazzite-DX fork/branch
[group('Build')]
build-fork user branch:
    #!/usr/bin/bash
    BASE_IMAGE="ghcr.io/{{ user }}/bazzite-dx-nvidia:{{ branch }}" just build

# Build the image in dev mode (Forked Base + Custom AWCC Spec)
[group('Build')]
build-dev user branch spec="awcc.dev.spec":
    #!/usr/bin/bash
    BASE_IMAGE="ghcr.io/{{ user }}/bazzite-dx-nvidia:{{ branch }}" AWCC_SPEC="{{ spec }}" just build

# ==============================================================================
# GROUP 3: Apply & Safety (Lifecycle)
# ==============================================================================

# Apply the locally built image to the current system
[group('Lifecycle')]
rebase-local:
    rm -f /tmp/{{ IMAGE_NAME }}.tar || true
    podman save localhost/{{ IMAGE_NAME }}:latest --format oci-archive -o /tmp/{{ IMAGE_NAME }}.tar
    sudo rpm-ostree rebase ostree-unverified-image:oci-archive:/tmp/{{ IMAGE_NAME }}.tar
    rm -f /tmp/{{ IMAGE_NAME }}.tar
    echo "Rebase complete. Please reboot to apply changes."

# Rollback the last rpm-ostree transaction (Reverses rebase-local)
[group('Lifecycle')]
rollback-local:
    sudo rpm-ostree rollback
    echo "Rollback complete. Please reboot to return to the previous state."

# Rebase the system back to the official signed production image
[group('Lifecycle')]
rebase-official:
    sudo rpm-ostree rebase ostree-image-signed:docker://ghcr.io/nklowns/bazzite-dx-silver-goggles:latest
    echo "Rebase to official image initiated. Please reboot after completion."

# ==============================================================================
# GROUP 4: Component Development (Hot-Swap)
# ==============================================================================

# Build AWCC RPM from LOCAL source code (bind-mount)
[group('Development')]
dev-awcc-rpm source_path:
    #!/usr/bin/bash
    set -e
    echo "Building AWCC RPM from local source: {{ source_path }}"
    podman build --target builder --build-arg AWCC_SPEC={{ AWCC_SPEC }} -t awcc-dev-builder .
    podman run --rm -v {{ source_path }}:/tmp/AWCC_SRC:Z -v .:/output:Z awcc-dev-builder bash -c ' \
        set -e
        # Prepare an isolated build environment
        mkdir -p /tmp/build_env && cd /tmp/build_env && \

        # Define spec file path
        SPEC_FILE="/tmp/rpmbuild/{{ AWCC_SPEC }}"

        # Nuclear SED: Force the spec file to conform to our dev environment
        # 1. Update Version and Release
        sed -i "s/^Version:.*/Version: dev.swap/" $SPEC_FILE
        sed -i "s/^Release:.*/Release: $(date +%s)/" $SPEC_FILE

        # 2. Force Source0 and %autosetup to use fixed names
        sed -i "s|^Source0:.*|Source0: dev.swap.tar.gz|" $SPEC_FILE
        sed -i "s|^%autosetup.*|%autosetup -n AWCC-dev.swap|" $SPEC_FILE

        # 3. Clean up potentially conflicting globals
        sed -i "/^%global commit/d" $SPEC_FILE
        sed -i "/^%global shortcommit/d" $SPEC_FILE

        # Package the source into the expected directory and tarball name
        mkdir -p AWCC-dev.swap
        cp -r /tmp/AWCC_SRC/* AWCC-dev.swap/
        tar -czf dev.swap.tar.gz AWCC-dev.swap/

        # Run rpmbuild pointing to our isolated source directory
        rpmbuild -bb \
            --define "_sourcedir $PWD" \
            --define "_builddir $PWD" \
            $SPEC_FILE && \

        # Select the main RPM and copy it to output
        find /root/rpmbuild/RPMS/x86_64/ -name "awcc-*.rpm" ! -name "*-debug*" -exec cp {} /output/awcc-dev.rpm \;
    '
    echo "Done. awcc-dev.rpm is ready."

# Install a local RPM package live to the system
[group('Development')]
install-awcc package="awcc-dev.rpm":
    #!/usr/bin/bash
    set -e
    echo "Stopping AWCC services..."
    sudo systemctl stop awccd.service || true
    echo "Staging {{ package }} via rpm-ostree override replace..."
    sudo rpm-ostree override replace ./{{ package }}
    echo "Applying changes live..."
    sudo rpm-ostree apply-live --allow-replacement
    echo "Starting AWCC services..."
    sudo systemctl enable --now awccd.service

# Hot-swap AWCC: Build from local source and apply live to the host
[group('Development')]
hot-swap-awcc source_path:
    just dev-awcc-rpm {{ source_path }}
    just install-awcc awcc-dev.rpm

# Uninstall AWCC live from the host system
[group('Development')]
uninstall-awcc:
    #!/usr/bin/bash
    sudo rpm-ostree uninstall awcc --apply-live

# ==============================================================================
# GROUP 5: Virtual Machine & Bootable (Advanced)
# ==============================================================================

# Build a QCOW2 virtual machine image
[group('Virtual Machine')]
build-qcow2 $target_image=("localhost/" + IMAGE_NAME) $tag=DEFAULT_TAG: && (_build-bib target_image tag "qcow2" "disk_config/disk.toml")

# Build a RAW virtual machine image
[group('Virtual Machine')]
build-raw $target_image=("localhost/" + IMAGE_NAME) $tag=DEFAULT_TAG: && (_build-bib target_image tag "raw" "disk_config/disk.toml")

# Build an ISO virtual machine image
[group('Virtual Machine')]
build-iso $target_image=("localhost/" + IMAGE_NAME) $tag=DEFAULT_TAG: && (_build-bib target_image tag "iso" "disk_config/iso.toml")

# Rebuild a QCOW2 virtual machine image
[group('Virtual Machine')]
rebuild-qcow2 $target_image=("localhost/" + IMAGE_NAME) $tag=DEFAULT_TAG: && (_rebuild-bib target_image tag "qcow2" "disk_config/disk.toml")

# Rebuild a RAW virtual machine image
[group('Virtual Machine')]
rebuild-raw $target_image=("localhost/" + IMAGE_NAME) $tag=DEFAULT_TAG: && (_rebuild-bib target_image tag "raw" "disk_config/disk.toml")

# Rebuild an ISO virtual machine image
[group('Virtual Machine')]
rebuild-iso $target_image=("localhost/" + IMAGE_NAME) $tag=DEFAULT_TAG: && (_rebuild-bib target_image tag "iso" "disk_config/iso.toml")

# Run a virtual machine from a QCOW2 image
[group('Virtual Machine')]
run-vm-qcow2 $target_image=("localhost/" + IMAGE_NAME) $tag=DEFAULT_TAG: && (_run-vm target_image tag "qcow2" "disk_config/disk.toml")

# Run a virtual machine from a RAW image
[group('Virtual Machine')]
run-vm-raw $target_image=("localhost/" + IMAGE_NAME) $tag=DEFAULT_TAG: && (_run-vm target_image tag "raw" "disk_config/disk.toml")

# Run a virtual machine from an ISO
[group('Virtual Machine')]
run-vm-iso $target_image=("localhost/" + IMAGE_NAME) $tag=DEFAULT_TAG: && (_run-vm target_image tag "iso" "disk_config/iso.toml")

# Run a virtual machine using systemd-vmspawn
[group('Virtual Machine')]
spawn-vm rebuild="0" type="qcow2" ram="6G":
    #!/usr/bin/env bash
    set -euo pipefail
    [ "{{ rebuild }}" -eq 1 ] && echo "Rebuilding the ISO" && just build-vm {{ rebuild }} {{ type }}
    systemd-vmspawn \
      -M "bootc-image" \
      --console=gui \
      --cpus=2 \
      --ram=$(echo {{ ram }}| /usr/bin/numfmt --from=iec) \
      --network-user-mode \
      --vsock=false --pass-ssh-key=false \
      -i ./output/**/*.{{ type }}

[private]
_build-bib $target_image $tag $type $config: (_rootful_load_image target_image tag)
    #!/usr/bin/env bash
    set -euo pipefail
    args="--type ${type} "
    args+="--use-librepo=True "
    args+="--rootfs=btrfs"
    BUILDTMP=$(mktemp -p "${PWD}" -d -t _build-bib.XXXXXXXXXX)
    sudo podman run \
      --rm \
      -it \
      --privileged \
      --pull=newer \
      --net=host \
      --security-opt label=type:unconfined_t \
      -v $(pwd)/${config}:/config.toml:ro \
      -v $BUILDTMP:/output \
      -v /var/lib/containers/storage:/var/lib/containers/storage \
      "${bib_image}" \
      ${args} \
      "${target_image}:${tag}"
    mkdir -p output
    sudo mv -f $BUILDTMP/* output/
    sudo rmdir $BUILDTMP
    sudo chown -R $USER:$USER output/

[private]
_rebuild-bib $target_image $tag $type $config: (build target_image tag) && (_build-bib target_image tag type config)

[private]
_rootful_load_image $target_image=IMAGE_NAME $tag=DEFAULT_TAG:
    #!/usr/bin/bash
    set -eoux pipefail
    if [[ -n "${SUDO_USER:-}" || "${UID}" -eq "0" ]]; then
        echo "Already root or running under sudo, no need to load image from user podman."
        exit 0
    fi
    set +e
    resolved_tag=$(podman inspect -t image "${target_image}:${tag}" | jq -r '.[].RepoTags.[0]')
    return_code=$?
    set -e
    USER_IMG_ID=$(podman images --filter reference="${target_image}:${tag}" --format "'{{ '{{.ID}}' }}'")
    if [[ $return_code -eq 0 ]]; then
        ID=$(just sudoif podman images --filter reference="${target_image}:${tag}" --format "'{{ '{{.ID}}' }}'")
        if [[ "$ID" != "$USER_IMG_ID" ]]; then
            COPYTMP=$(mktemp -p "${PWD}" -d -t _build_podman_scp.XXXXXXXXXX)
            just sudoif TMPDIR=${COPYTMP} podman image scp ${UID}@localhost::"${target_image}:${tag}" root@localhost::"${target_image}:${tag}"
            rm -rf "${COPYTMP}"
        fi
    else
        just sudoif podman pull "${target_image}:${tag}"
    fi

[private]
_run-vm $target_image $tag $type $config:
    #!/usr/bin/bash
    set -eoux pipefail
    image_file="output/${type}/disk.${type}"
    if [[ $type == iso ]]; then
        image_file="output/bootiso/install.iso"
    fi
    if [[ ! -f "${image_file}" ]]; then
        just "build-${type}" "$target_image" "$tag"
    fi
    port=8006
    while grep -q :${port} <<< $(ss -tunalp); do
        port=$(( port + 1 ))
    done
    echo "Using Port: ${port}"
    echo "Connect to http://localhost:${port}"
    run_args=()
    run_args+=(--rm --privileged)
    run_args+=(--pull=newer)
    run_args+=(--publish "127.0.0.1:${port}:8006")
    run_args+=(--env "CPU_CORES=4")
    run_args+=(--env "RAM_SIZE=8G")
    run_args+=(--env "DISK_SIZE=64G")
    run_args+=(--env "TPM=Y")
    run_args+=(--env "GPU=Y")
    run_args+=(--device=/dev/kvm)
    run_args+=(--volume "${PWD}/${image_file}":"/boot.${type}")
    run_args+=(docker.io/qemux/qemu)
    (sleep 30 && xdg-open http://localhost:"$port") &
    podman run "${run_args[@]}"

# ==============================================================================
# GROUP 6: Status
# ==============================================================================

# Check hardware and system health status
[group('Status')]
status:
    /usr/bin/g15-status
