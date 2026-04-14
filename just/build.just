# ==============================================================================
# GROUP 2: Image Builds (BlueBuild)
# ==============================================================================

# Build image using BlueBuild CLI (Surface Recipe)
[group('Build')]
build target_image="bazzite-nvidia" tag=default_tag: (generate-recipe target_image tag)
    #!/usr/bin/env bash
    set -euo pipefail
    bluebuild build recipes/build-recipe.yml

# Build image without using cache
[group('Build')]
build-nocache target_image="bazzite-nvidia" tag=default_tag: (generate-recipe target_image tag)
    #!/usr/bin/env bash
    set -euo pipefail
    bluebuild build --no-cache recipes/build-recipe.yml

# Generate build recipe with complete OCI metadata (Unified Logic)
generate-recipe target_image tag:
    ./scripts/generate-recipe.sh "{{ target_image }}" "{{ tag }}"

# Build image pointing to a custom Bazzite-DX fork/branch (overrides base-image)
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
    ./scripts/load-image.sh "{{ target_image }}" "{{ tag }}"

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
    sudo rpm-ostree rebase ostree-image-signed:docker://ghcr.io/nklowns/bazzite-dx-silver-goggles:latest
    echo "Rebase to official image initiated. Please reboot after completion."
