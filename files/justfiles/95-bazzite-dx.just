# vim: set ft=make :
# --- Bazzite-DX: The Transformation Interface ---

# Audit the current Bazzite-DX workstation state
[group('System')]
dx-doctor:
    #!/usr/bin/bash
    echo "=== Bazzite-DX: Medical Report ==="
    echo "1. Core Kernel Matrix:"
    cat /proc/cmdline | grep -iE --color "iommu|kvm|preempt" || echo "Warning: Specialized kargs not detected!"

    echo -e "\n2. Architecture & Image:"
    [[ -f /usr/share/ublue-os/image-info.json ]] && jq -C . /usr/share/ublue-os/image-info.json

    echo -e "\n3. Developer Group Sync:"
    DX_GROUPS=("docker" "incus-admin" "libvirt" "dialout" "input" "video" "render" "plugdev")
    for grp in "${DX_GROUPS[@]}"; do
        if groups "$USER" | grep -q "\b$grp\b"; then
            echo "[ OK ] $grp"
        else
            echo "[FAIL] $grp (Run: ujust dx-group)"
        fi
    done

    echo -e "\n4. Experience Layer (Bbrew Check):"
    if command -v bbrew >/dev/null; then
        echo "[ OK ] Bbrew is present."
    else
        echo "[WARN] Bbrew not found. Some uBlue workflows might be slower."
    fi

# Provision the current user for DX groups (Idempotent)
[group('System')]
dx-group:
    #!/usr/bin/bash
    set -euo pipefail
    DX_GROUPS=("docker" "incus-admin" "libvirt" "dialout" "input" "video" "render" "plugdev")
    echo "Syncing $USER with Developer Experience groups..."
    for grp in "${DX_GROUPS[@]}"; do
        if getent group "$grp" >/dev/null; then
            if groups "$USER" | grep -q "\b$grp\b"; then
                echo "Already sync'd: $grp"
            else
                sudo usermod -aG "$grp" "$USER"
                echo "Sync'd: $grp"
            fi
        fi
    done
    echo "Done! Changes require a new session to take effect."

# Configure Bazzite-DX Curated Workstation Flavors
[group('Setup')]
setup-default-brew flavor="":
    #!/usr/bin/env bash
    set -e
    FLAVOR="{{ flavor }}"
    if [[ -z "$FLAVOR" ]]; then
        echo "Choose a Bazzite-DX Workstation Flavor to activate (High-Fidelity):"
        FLAVOR=$(gum choose "cli" "ai" "cncf" "all")
    fi
    case $FLAVOR in
        cli)
            echo "Aactivating: Terminal Excellence Bundle..."
            brew bundle --file=/usr/share/ublue-os/homebrew/cli.Brewfile
            ;;
        ai)
            echo "Activating: Agentic Excellence Bundle (Goose/Antigravity)..."
            brew bundle --file=/usr/share/ublue-os/homebrew/ai-tools.Brewfile
            ;;
        cncf)
            echo "Activating: Cloud-Native Standard (Kubernetes/Helm)..."
            brew bundle --file=/usr/share/ublue-os/homebrew/cncf.Brewfile
            ;;
        all)
            echo "Activating: Full uBlue Transformation..."
            brew bundle --file=/usr/share/ublue-os/homebrew/cli.Brewfile
            brew bundle --file=/usr/share/ublue-os/homebrew/ai-tools.Brewfile
            brew bundle --file=/usr/share/ublue-os/homebrew/cncf.Brewfile
            ;;
        *)
            echo "Unknown flavor: $FLAVOR"
            exit 1
            ;;
    esac
    echo "Successfully enabled the $FLAVOR developer experience!"

# Monitor eBPF Performance (Requires sudo)
monitor-ebpf:
    #!/usr/bin/bash
    sudo bpftop
