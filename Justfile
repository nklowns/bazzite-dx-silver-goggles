export AWCC_SPEC := env("AWCC_SPEC", "awcc.spec")
export image_name := env("IMAGE_NAME", "bazzite-dx-silver-goggles")
export default_tag := env("DEFAULT_TAG", "latest")
export bib_image := env("BIB_IMAGE", "quay.io/centos-bootc/bootc-image-builder:latest")
export PODMAN := if path_exists("/usr/bin/podman") == "true" { env("PODMAN", "/usr/bin/podman") } else if path_exists("/usr/bin/docker") == "true" { env("PODMAN", "docker") } else { env("PODMAN", "exit 1 ; ") }
export PULL_POLICY := if PODMAN =~ "docker" { "missing" } else { "newer" }

alias build-vm := build-qcow2
alias rebuild-vm := rebuild-qcow2
alias run-vm := run-vm-qcow2

[private]
default:
    @just --list

# ==============================================================================
# GROUP 1: Utility (Maintenance & CI)
# ==============================================================================

# Check Just Syntax and BlueBuild Recipe
[group('Just')]
check:
    #!/usr/bin/env bash
    find . -type f -name "*.just" | while read -r file; do
    	echo "Checking syntax: $file"
    	just --unstable --fmt --check -f $file
    done
    echo "Checking syntax: Justfile"
    just --unstable --fmt --check -f Justfile
    if [ -f recipes/recipe.yml ]; then
      echo "Validating BlueBuild recipe..."
      bluebuild validate recipes/recipe.yml
    fi
    echo "Running ShellCheck on Bash scripts..."
    just lint

# Fix Just Syntax and Format scripts
[group('Just')]
fix:
    #!/usr/bin/env bash
    find . -type f -name "*.just" | while read -r file; do
    	echo "Fixing syntax: $file"
    	just --unstable --fmt -f $file
    done
    echo "Fixing syntax: Justfile"
    just --unstable --fmt -f Justfile
    echo "Formatting Bash scripts..."
    just format

# Runs shell check on all Bash scripts (uses Container if local not found)
[group('Utility')]
lint:
    #!/usr/bin/env bash
    set -eoux pipefail
    if ! command -v shellcheck &>/dev/null; then
        echo "shellcheck not found locally. Running via ${PODMAN}..."
        /usr/bin/find . -name "*.sh" -type f -not -path "./.bluebuild*" -exec ${PODMAN} run --rm -v "$PWD:/mnt:Z" docker.io/koalaman/shellcheck-alpine shellcheck /mnt/{} ';'
    else
        /usr/bin/find . -iname "*.sh" -type f -not -path "./.bluebuild*" -exec shellcheck "{}" ';'
    fi

# Runs shfmt on all Bash scripts (uses Container if local not found)
[group('Utility')]
format:
    #!/usr/bin/env bash
    set -eoux pipefail
    if ! command -v shfmt &>/dev/null; then
        echo "shfmt not found locally. Running via ${PODMAN}..."
        /usr/bin/find . -name "*.sh" -type f -not -path "./.bluebuild*" -exec ${PODMAN} run --rm -v "$PWD:/mnt:Z" --entrypoint shfmt docker.io/mvdan/shfmt:latest -w /mnt/{} ';'
    else
        /usr/bin/find . -iname "*.sh" -type f -not -path "./.bluebuild*" -exec shfmt --write "{}" ';'
    fi

# Clean Repo
[group('Utility')]
clean:
    #!/usr/bin/env bash
    set -euxo pipefail
    touch _build
    find *_build* -exec rm -rf {} \;
    rm -f previous.manifest.json
    rm -f changelog.md
    rm -f output.env
    rm -rf output/

# Sudo Clean Repo
[group('Utility')]
[private]
sudo-clean:
    just sudoif just clean

# sudoif bash function
[group('Utility')]
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
# GROUP 2: Image Builds (BlueBuild)
# ==============================================================================

# Build image using BlueBuild CLI (Surface Recipe)
[group('Build')]
build target_image="bazzite-nvidia" tag=default_tag: (build-recipe target_image tag)
    #!/usr/bin/env bash
    set -euo pipefail
    bluebuild build .bluebuild/build-recipe.yml

# Build image without using cache
[group('Build')]
build-nocache target_image="bazzite-nvidia" tag=default_tag: (build-recipe target_image tag)
    #!/usr/bin/env bash
    set -euo pipefail
    bluebuild build --no-cache .bluebuild/build-recipe.yml

# Generate build recipe with complete OCI metadata (Unified Logic)
[private]
build-recipe target_image tag:
    #!/usr/bin/env bash
    set -euo pipefail
    # Resolve and Patch
    export BASE_IMAGE=$(yq ".images[] | select(.name == \"{{ target_image }}\") | .image" image-versions.yaml)
    export BASE_TAG=$(yq ".images[] | select(.name == \"{{ target_image }}\") | .tag" image-versions.yaml)
    export BASE_DIGEST=$(yq ".images[] | select(.name == \"{{ target_image }}\") | .digest" image-versions.yaml)
    export IMAGE_NAME="bazzite-dx-silver-goggles"
    export IMAGE_DESC="Personal DX layer for Dell G15 5520. KDE/NVIDIA — Slim Edition."
    export ARTIFACTHUB_LOGO_URL="https://avatars.githubusercontent.com/u/187439889?s=200&v=4"
    export REPO_OWNER=$(git remote get-url origin | sed -E 's/.*[:\/](.*)\/(.*)\.git/\1/')
    export KERNEL_RELEASE=$(uname -r)
    export DATE_CREATED=$(date -u +'%Y-%m-%dT%H:%M:%SZ')
    export VERSION_FULL="${BASE_TAG}.$(date +%Y%m%d)"
    export REVISION=$(git rev-parse HEAD 2>/dev/null || echo 'local')

    if [[ -n "$BASE_DIGEST" && "$BASE_DIGEST" != "null" ]]; then
        export IMAGE_VERSION_VAL="${BASE_TAG}@${BASE_DIGEST}"
    else
        export IMAGE_VERSION_VAL="${BASE_TAG}"
    fi

    if [ -z "${BASE_IMAGE}" ] || [ "${BASE_IMAGE}" == "null" ]; then
        echo "Error: Image '{{ target_image }}' not found in image-versions.yaml"
        exit 1
    fi

    echo "Generating build recipe for {{ target_image }} (Base: ${BASE_IMAGE}:${IMAGE_VERSION_VAL})..."
    mkdir -p .bluebuild
    yq '
      .name = env(IMAGE_NAME) |
      .description = env(IMAGE_DESC) |
      .base-image = env(BASE_IMAGE) |
      .image-version = env(IMAGE_VERSION_VAL)
    ' recipes/recipe.yml > .bluebuild/build-recipe.yml

    yq -i '
      .alt-tags = (["latest", "stable", "{{ tag }}", env(BASE_TAG)] | unique) |
      .labels."io.artifacthub.package.logo-url" = env(ARTIFACTHUB_LOGO_URL) |
      .labels."io.artifacthub.package.readme-url" = "https://raw.githubusercontent.com/" + env(REPO_OWNER) + "/bazzite-dx-silver-goggles/main/README.md" |
      .labels."io.artifacthub.package.maintainers" = "[{\"name\": \"nklowns\", \"email\": \"nklowns@users.noreply.github.com\"}]" |
      .labels."io.artifacthub.package.keywords" = "bootc,bazzite,dx,silver-goggles,dell-g15,ublue,universal-blue,fedora,gaming,developer" |
      .labels."io.artifacthub.package.deprecated" = "false" |
      .labels."io.artifacthub.package.prerelease" = "false" |
      .labels."containers.bootc" = "1" |
      .labels."ostree.linux" = env(KERNEL_RELEASE) |
      .labels."org.opencontainers.image.vendor" = env(REPO_OWNER) |
      .labels."org.opencontainers.image.licenses" = "Apache-2.0" |
      .labels."org.opencontainers.image.source" = "https://github.com/" + env(REPO_OWNER) + "/bazzite-dx-silver-goggles" |
      .labels."org.opencontainers.image.url" = "https://github.com/" + env(REPO_OWNER) + "/bazzite-dx-silver-goggles" |
      .labels."org.opencontainers.image.documentation" = "https://raw.githubusercontent.com/" + env(REPO_OWNER) + "/bazzite-dx-silver-goggles/main/README.md" |
      .labels."org.opencontainers.image.version" = env(VERSION_FULL) |
      .labels."org.opencontainers.image.revision" = env(REVISION)
    ' .bluebuild/build-recipe.yml

# Build image pointing to a custom Bazzite-DX fork/branch (overrides base-image)
# Note: requires editing recipes/recipe.yml base-image field manually or

# using --build-arg if your blue-build version supports it.
[group('Build')]
build-fork user branch:
    #!/usr/bin/env bash
    echo "Override base-image in recipes/recipe.yml to ghcr.io/{{ user }}/bazzite-nvidia:{{ branch }}"
    echo "Then run: just build"

# Run GitHub Actions locally using act (uses BlueBuild job)
[group('Build')]
act:
    #!/usr/bin/env bash
    act -j bluebuild \
        -P ubuntu-24.04=catthehacker/ubuntu:full-24.04 \
        --privileged

# ==============================================================================
# GROUP 3: Virtual Machine & Bootable (Advanced)
# ==============================================================================

# Build a QCOW2 virtual machine image
[group('Image Builders (BIB)')]
build-qcow2 $target_image=image_name $tag=default_tag: && (_build-bib target_image tag "qcow2" "disk_config/devel.toml")

# Build a RAW virtual machine image
[group('Image Builders (BIB)')]
build-raw $target_image=image_name $tag=default_tag: && (_build-bib target_image tag "raw" "disk_config/devel.toml")

# Build an ISO virtual machine image
[group('Image Builders (BIB)')]
build-iso $target_image=image_name $tag=default_tag: && (_build-bib target_image tag "iso" "disk_config/iso.toml")

# Rebuild a QCOW2 virtual machine image
[group('Image Builders (BIB)')]
rebuild-qcow2 $target_image=image_name $tag=default_tag: && (_rebuild-bib target_image tag "qcow2" "disk_config/devel.toml")

# Rebuild a RAW virtual machine image
[group('Image Builders (BIB)')]
rebuild-raw $target_image=image_name $tag=default_tag: && (_rebuild-bib target_image tag "raw" "disk_config/devel.toml")

# Rebuild an ISO virtual machine image
[group('Image Builders (BIB)')]
rebuild-iso $target_image=image_name $tag=default_tag: && (_rebuild-bib target_image tag "iso" "disk_config/iso.toml")

# Run a virtual machine from a QCOW2 image
[group('VM Runners')]
run-vm-qcow2 $target_image=image_name $tag=default_tag: && (_run-vm target_image tag "qcow2" "disk_config/devel.toml")

# Run a virtual machine from a RAW image
[group('VM Runners')]
run-vm-raw $target_image=image_name $tag=default_tag: && (_run-vm target_image tag "raw" "disk_config/devel.toml")

# Run a virtual machine from an ISO
[group('VM Runners')]
run-vm-iso $target_image=image_name $tag=default_tag: && (_run-vm target_image tag "iso" "disk_config/iso.toml")

# Run a virtual machine using systemd-vmspawn
[group('VM Runners')]
spawn-vm rebuild="0" type="qcow2" ram="6G":
    #!/usr/bin/env bash
    set -euo pipefail
    [ "{{ rebuild }}" -eq 1 ] && echo "Rebuilding the image" && just build-{{ type }}
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
    mkdir -p "output"
    if [[ $type == iso ]]; then
        sudo rm -rf "output/bootiso" || true
    else
        sudo rm -rf "output/${type}" || true
    fi

    args="--type ${type}"
    args+=" --progress verbose"
    args+=" --use-librepo=True"
    args+=" --rootfs=btrfs"

    # Ensure localhost/ prefix for local images
    full_image="${target_image}:${tag}"
    if [[ "${full_image}" != */* ]]; then
      full_image="localhost/${full_image}"
    fi

    if [[ $full_image == localhost/* ]]; then
        args+=" --local"
    fi

    sudo {{ PODMAN }} run \
      --rm \
      -it \
      --privileged \
      --pull={{ PULL_POLICY }} \
      --net=host \
      --security-opt label=type:unconfined_t \
      -v $(pwd)/${config}:/config.toml:ro \
      -v $(pwd)/output:/output \
      -v /var/lib/containers/storage:/var/lib/containers/storage \
      "${bib_image}" \
      ${args} \
      "${full_image}"

    sudo chown -R $USER:$USER output/

[private]
_rebuild-bib $target_image $tag $type $config: build && (_build-bib target_image tag type config)

[private]
_rootful_load_image $target_image=image_name $tag=default_tag:
    #!/usr/bin/env bash
    set -euxo pipefail

    if [[ -n "${SUDO_USER:-}" || "${UID}" -eq "0" ]]; then
      echo "Already root or running under sudo, no need to load image from user ${PODMAN}."
      exit 0
    fi

    # Ensure localhost/ prefix for local images
    full_image="${target_image}:${tag}"
    if [[ "${full_image}" != */* ]]; then
      full_image="localhost/${full_image}"
    fi

    set +e
    resolved_tag=$(${PODMAN} inspect -t image "${full_image}" | jq -r '.[].RepoTags.[0]')
    return_code=$?
    set -e

    USER_IMG_ID=$(${PODMAN} images --filter reference="${full_image}" --format "'{{ '{{.ID}}' }}'")

    if [[ $return_code -eq 0 ]]; then
      # Load into Rootful ${PODMAN}
      ID=$(just sudoif ${PODMAN} images --filter reference="${full_image}" --format "'{{ '{{.ID}}' }}'")
      if [[ "$ID" != "$USER_IMG_ID" ]]; then
        COPYTMP=$(mktemp -p "${PWD}" -d -t _build_podman_scp.XXXXXXXXXX)
        just sudoif TMPDIR=${COPYTMP} ${PODMAN} image scp ${UID}@localhost::"${full_image}" root@localhost::"${full_image}"
        rm -rf "${COPYTMP}"
      fi
    else
      # Make sure the image is present and/or up to date
      just sudoif ${PODMAN} pull "${full_image}"
    fi

[private]
_run-vm $target_image $tag $type $config:
    #!/usr/bin/env bash
    set -euxo pipefail
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
    run_args+=(--pull={{ PULL_POLICY }})
    run_args+=(--publish "127.0.0.1:${port}:8006")
    run_args+=(--publish "127.0.0.1:2222:22")
    run_args+=(--env "CPU_CORES=4")
    run_args+=(--env "RAM_SIZE=8G")
    run_args+=(--env "DISK_SIZE=64G")
    run_args+=(--env "TPM=Y")
    run_args+=(--env "GPU=Y")
    run_args+=(--device=/dev/kvm)
    run_args+=(--volume "${PWD}/${image_file}":"/boot.${type}")
    run_args+=(docker.io/qemux/qemu)
    {{ PODMAN }} run "${run_args[@]}" &
    xdg-open http://localhost:${port}
    wait $!

# ==============================================================================
# GROUP 4: Apply & Safety (Lifecycle)
# ==============================================================================

# Apply the locally built image to the current system
[group('Lifecycle')]
rebase-local:
    rm -f /tmp/{{ image_name }}.tar || true
    {{ PODMAN }} save localhost/{{ image_name }}:latest --format oci-archive -o /tmp/{{ image_name }}.tar
    sudo rpm-ostree rebase ostree-unverified-image:oci-archive:/tmp/{{ image_name }}.tar
    rm -f /tmp/{{ image_name }}.tar
    echo "Rebase complete. Please reboot to apply changes."

# Rollback the last rpm-ostree transaction (Reverses rebase-local)
[group('Lifecycle')]
rollback-local:
    sudo rpm-ostree rollback
    echo "Rollback complete. Please reboot to return to the previous state."

# Rebase the system back to the official signed production image
[group('Lifecycle')]
rebase-official:
    # sudo rpm-ostree reset
    # sudo rpm-ostree override reset --all
    # sudo rpm-ostree uninstall --all
    sudo rpm-ostree rebase ostree-image-signed:docker://ghcr.io/nklowns/bazzite-dx-silver-goggles:latest
    echo "Rebase to official image initiated. Please reboot after completion."

# ==============================================================================
# GROUP 5: Component Development (Hot-Swap)
# ==============================================================================
# Build AWCC RPM (Stable or Local Dev)
# Usage (Stable):  just build-awcc
# Usage (Local):   just build-awcc /path/to/AWCC-source

# Output: awcc-dev.rpm in files/ (tracked by git, used by the image build)
[group('Development')]
build-awcc source_path="":
    #!/usr/bin/env bash
    set -euo pipefail

    if grep -q "dev" <<< "{{ AWCC_SPEC }}" || [ -n "{{ source_path }}" ]; then
        MODE="Development (Local Source)"
        [ -z "{{ source_path }}" ] && { echo "Error: source_path required for dev spec"; exit 1; }
    else
        MODE="Stable (Upstream Fetch)"
    fi

    echo "Building AWCC RPM: ${MODE}"
    [ -n "{{ source_path }}" ] && echo "Source: {{ source_path }}"

    SPEC_FILE="/build_files/{{ AWCC_SPEC }}"
    OUTPUT_DIR="$(pwd)/files/rpm-ostree"

    MOUNTS=("-v" "$(pwd)/build_files:/build_files:ro,z")
    MOUNTS+=("-v" "$(pwd)/files:/output:z")

    if [ -n "{{ source_path }}" ]; then
        MOUNTS+=("-v" "$(readlink -f {{ source_path }}):/tmp/AWCC_SRC:ro,z")
    fi

    ${PODMAN} run --rm "${MOUNTS[@]}" "fedora:43" bash -c '
            set -euo pipefail
            dnf5 install -y --setopt=install_weak_deps=False rpm-build rpmdevtools dnf5-plugins cmake ninja-build meson gcc-c++ git libX11-devel libxkbcommon-devel glfw-devel systemd-devel libudev-devel libglvnd-devel wayland-devel

            rpmdev-setuptree
            WORKDIR=$(mktemp -d)
            cd "${WORKDIR}"

            if [ -d "/tmp/AWCC_SRC" ]; then
                # Build from local source
                cp "/build_files/{{ AWCC_SPEC }}" ./awcc-local.spec
                sed -i "s/^Version:.*/Version: dev.local/" ./awcc-local.spec
                sed -i "s/^Release:.*/Release: $(date +%s)/" ./awcc-local.spec
                sed -i "s|^Source0:.*|Source0: awcc-dev.local.tar.gz|" ./awcc-local.spec
                sed -i "s|^%autosetup.*|%autosetup -n awcc-dev.local|" ./awcc-local.spec
                sed -i "/^%global commit/d" ./awcc-local.spec
                sed -i "/^%global shortcommit/d" ./awcc-local.spec

                mkdir -p "awcc-dev.local"
                cp -r /tmp/AWCC_SRC/. "awcc-dev.local/"
                tar -czf "awcc-dev.local.tar.gz" "awcc-dev.local/"
                cp "awcc-dev.local.tar.gz" ~/rpmbuild/SOURCES/

                rpmbuild -ba --define "_sourcedir ${WORKDIR}" ./awcc-local.spec
            else
                # Build stable release (fetch source defined in spec)
                cp "/build_files/{{ AWCC_SPEC }}" ./awcc-stable.spec
                # Handle potential dynamic sources/tarballs
                spectool -g -C ~/rpmbuild/SOURCES/ ./awcc-stable.spec
                rpmbuild -ba ./awcc-stable.spec
            fi

            # Copy output RPM (exclude debuginfo)
            find ~/rpmbuild/RPMS/x86_64/ -name "awcc-*.rpm" ! -name "*debug*" -exec cp {} /output/awcc-dev.rpm \;
        '
    echo "Build complete: files/awcc-dev.rpm"

# Install a local RPM package live to the system
[group('Development')]
install-awcc package="files/rpm-ostree/awcc-dev.rpm":
    #!/usr/bin/env bash
    set -e
    echo "Stopping AWCC services..."
    sudo systemctl stop awccd.service || true
    echo "Unlocking filesystem (transient)..."
    sudo rpm-ostree usroverlay || true
    echo "Installing {{ package }} directly via RPM..."
    sudo rpm -Uvh --force ./{{ package }}
    echo "Verifying installation..."
    rpm -q awcc
    echo "Starting AWCC services..."
    sudo systemctl enable --now awccd.service

# Hot-swap AWCC: Build from local source and apply live to the host
[group('Development')]
hot-swap-awcc source_path:
    just build-awcc {{ source_path }}
    just install-awcc files/awcc-dev.rpm

# Uninstall AWCC live from the host system
[group('Development')]
uninstall-awcc:
    #!/usr/bin/env bash
    echo "Resetting transient changes (reverts system to base image state)..."
    sudo rpm-ostree apply-live --reset

# ==============================================================================
# GROUP 6: Status
# ==============================================================================

# Check system and development environment status
[group('Just')]
status:
    @echo "=== Image Configuration ==="
    @echo "Project:  {{ image_name }}"
    @echo "Tag:      {{ default_tag }}"
    @echo "AWCC Spec: {{ AWCC_SPEC }}"
    @echo ""
    @echo "=== Local Images (localhost/) ==="
    @${PODMAN} images --filter "reference=localhost/{{ image_name }}*" --format "table {{ '{{.Repository}}' }}\t{{ '{{.Tag}}' }}\t{{ '{{.ID}}' }}\t{{ '{{.CreatedSince}}' }}"
    @echo ""
    @echo "=== Tooling Versions ==="
    @echo "Just:    $(just --version | head -n1)"
    @echo "Podman:  $(${PODMAN} --version)"
    @echo ""
    @echo "=== BIB Engine ==="
    @echo "Image:   {{ bib_image }}"
    @echo ""
    @echo "=== G15 Status ==="
    @just g15-status

# Check hardware and system health status
[group('Just')]
g15-status:
    /usr/bin/g15-status
