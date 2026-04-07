# vim: set ft=make :
# --- Bazzite-DX: The Transformation Interface ---

# Audit the current Bazzite-DX workstation state
[group('System')]
dx-doctor:
    #!/usr/bin/bash
    echo "=== Bazzite-DX: Medical Report ==="
    echo "1. Core Kernel Matrix:"
    cat /proc/cmdline | grep -iE --color "iommu|kvm|vfio" || echo "Warning: Specialized kargs not detected!"

    echo -e "\n2. Architecture & Image:"
    [[ -f /usr/share/ublue-os/image-info.json ]] && jq -C . /usr/share/ublue-os/image-info.json

    echo -e "\n3. Developer Group Sync:"
    DX_GROUPS=("docker" "incus-admin" "libvirt" "dialout" "input" "video" "render" "plugdev")
    for grp in "${DX_GROUPS[@]}"; do
        if groups "$USER" | grep -q "\b$grp\b"; then
            echo "[ OK ] $grp"
        else
            if getent group "$grp" >/dev/null; then
                echo "[FAIL] $grp (Run: ujust dx-group sync)"
            else
                echo "[SKIP] $grp (Not found in system)"
            fi
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
dx-group cmd="":
    #!/usr/bin/bash
    set -euo pipefail
    DX_GROUPS=("docker" "incus-admin" "libvirt" "dialout" "input" "video" "render" "plugdev")
    CMD="{{ cmd }}"
    if [[ -z "$CMD" ]]; then
        CMD=$(gum choose "sync" "list-all" "list-active")
    fi

    case "$CMD" in
        sync)
            echo "Syncing $USER with Developer Experience groups..."
            for grp in "${DX_GROUPS[@]}"; do
                if getent group "$grp" >/dev/null; then
                    if ! grep -q "^$grp" /etc/group; then
                        echo "Activating group: $grp (from system defaults)"
                        grep "^$grp" /usr/lib/group | sudo tee -a /etc/group > /dev/null
                    fi
                    if groups "$USER" | grep -q "\b$grp\b"; then
                        echo "Already sync'd: $grp"
                    else
                        sudo usermod -a -G "$grp" "$USER"
                        echo "Sync'd: $grp"
                    fi
                fi
            done
            echo "Done! Changes require a new session to take effect."
            ;;
        list-all)
            echo "=== System Groups ==="
            getent group | cut -d: -f1 | sort
            ;;
        list-active)
            echo "=== $USER's Active Groups ==="
            id -Gn | tr ' ' '\n' | sort
            ;;
        *)
            echo "Unknown command: $CMD"
            exit 1
            ;;
    esac

# Configure Bazzite-DX Curated Workstation Flavors
[group('Setup')]
setup-default-brew flavor="" action="":
    #!/usr/bin/env bash
    set -e
    FLAVOR="{{ flavor }}"
    ACTION="{{ action }}"

    # Step 1: Choose Flavor
    if [[ -z "$FLAVOR" ]]; then
        echo "Choose a Bazzite-DX Workstation Flavor (High-Fidelity):"
        FLAVOR=$(gum choose "cli" "ai" "cncf" "all")
    fi

    # Step 2: Choose Action
    if [[ -z "$ACTION" ]]; then
        echo "Choose action for $FLAVOR bundle:"
        ACTION=$(gum choose "install" "check" "cleanup")
    fi

    FILES=()
    case $FLAVOR in
        cli)   FILES=("/usr/share/ublue-os/homebrew/cli.Brewfile") ;;
        ai)    FILES=("/usr/share/ublue-os/homebrew/ai-tools.Brewfile") ;;
        cncf)  FILES=("/usr/share/ublue-os/homebrew/cncf.Brewfile") ;;
        all)   FILES=("/usr/share/ublue-os/homebrew/cli.Brewfile" "/usr/share/ublue-os/homebrew/ai-tools.Brewfile" "/usr/share/ublue-os/homebrew/cncf.Brewfile" "/usr/share/ublue-os/homebrew/dx-build.Brewfile" "/usr/share/ublue-os/homebrew/dx-fonts.Brewfile") ;;
        *)     echo "Unknown flavor: $FLAVOR"; exit 1 ;;
    esac

    for FILE in "${FILES[@]}"; do
        case $ACTION in
            install)
                echo "🚀 Activating bundle: $(basename $FILE)..."
                brew bundle --file="$FILE"
                ;;
            check)
                echo "🔍 Checking status: $(basename $FILE)..."
                brew bundle check --file="$FILE"
                ;;
            cleanup)
                echo "🧹 Cleaning up unused: $(basename $FILE)..."
                brew bundle cleanup --file="$FILE"
                ;;
        esac
    done

    echo "Done! The $FLAVOR experience (action: $ACTION) is ready."

# Monitor eBPF Performance (Requires sudo)
monitor-ebpf:
    #!/usr/bin/bash
    sudo bpftop
