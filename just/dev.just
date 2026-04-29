# ==============================================================================
# GROUP 5: Component Development (Hot-Swap)
# ==============================================================================

# Build AWCC RPM (Stable or Local Dev)
[group('Development')]
build-awcc source_path="":
    #!/usr/bin/env bash
    FEDORA_VERSION=$(yq '.labels."org.opencontainers.image.version"' recipes/recipe.yml | tr -d '"')
    export FEDORA_VERSION=${FEDORA_VERSION:-44}
    ./scripts/build-awcc.sh "{{ AWCC_SPEC }}" "{{ source_path }}"

# Install a local RPM package live to the system
[group('Development')]
install-awcc package="files/rpm-ostree/awcc-dev.rpm":
    #!/usr/bin/env bash
    set -e
    if [[ ! -f "./{{ package }}" ]]; then
      echo "Error: RPM package not found at ./{{ package }}"
      exit 1
    fi
    echo "Stopping AWCC services..."
    sudo systemctl stop awccd.service 2>/dev/null || true

    echo "Unlocking transient overlay..."
    sudo rpm-ostree usroverlay

    echo "Installing {{ package }} via RPM override..."
    sudo rpm -Uvh --force ./{{ package }}

    echo "Reloading systemd and udev rules..."
    sudo systemctl daemon-reload
    sudo udevadm control --reload-rules && sudo udevadm trigger

    echo "Starting AWCC services..."
    sudo systemctl enable --now awccd.service

    echo "--- Installation Summary ---"
    rpm -q awcc
    systemctl is-active awccd.service

# Hot-swap AWCC: Build from local source and apply live to the host
[group('Development')]
hot-swap-awcc source_path:
    #!/usr/bin/env bash
    set -e
    echo "Initiating Atomic Hot-swap for AWCC..."
    just build-awcc {{ source_path }}
    just install-awcc
    echo "Hot-swap complete! Changes are live (Transient)."

# Uninstall AWCC live from the host system
[group('Development')]
uninstall-awcc:
    #!/usr/bin/env bash
    echo "Resetting transient changes (reverts system to base image state)..."
    sudo rpm-ostree apply-live --reset

# Abre um shell interativo com o contexto de desenvolvimento (bash, zsh, fish)
[group('Development')]
dev-shell shell="bash":
    ./scripts/dev-shell.sh {{ shell }}
