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
    DX_GROUPS_SYS=("dialout" "input" "video" "render" "plugdev")
    DX_GROUPS_DEV=("docker" "libvirt" "incus-admin" "adbusers")

    echo "--- System & Hardware ---"
    for grp in "${DX_GROUPS_SYS[@]}"; do
        if groups "$USER" | grep -q "\b$grp\b"; then
            echo "[ OK ] $grp"
        else
            [[ $(getent group "$grp") ]] && echo "[FAIL] $grp (Run: ujust dx-group sync)" || echo "[SKIP] $grp (Not in system)"
        fi
    done

    echo "--- Developer Tools ---"
    for grp in "${DX_GROUPS_DEV[@]}"; do
        if groups "$USER" | grep -q "\b$grp\b"; then
            echo "[ OK ] $grp"
        else
            [[ $(getent group "$grp") ]] && echo "[FAIL] $grp (Run: ujust dx-group sync)" || echo "[SKIP] $grp (Not in system)"
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
    DX_GROUPS=("docker" "libvirt" "incus-admin" "dialout" "input" "video" "render" "plugdev" "adbusers")
    CMD="{{ cmd }}"
    if [[ -z "$CMD" ]]; then
        CMD=$(gum choose "sync" "list-all" "list-active")
    fi

    case "$CMD" in
        sync)
            echo "Syncing $USER with Developer Experience groups..."
            for grp in "${DX_GROUPS[@]}"; do
                if getent group "$grp" >/dev/null; then
                    if ! grep -q "^$grp:" /etc/group; then
                        echo "Activating group: $grp (from system defaults)"
                        grep "^$grp:" /usr/lib/group | sudo tee -a /etc/group > /dev/null
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

    OVERALL_RC=0
    for FILE in "${FILES[@]}"; do
        case $ACTION in
            install)
                echo "🚀 Activating bundle: $(basename $FILE)..."
                # Trust taps declared in the Brewfile before bundle installation
                if command -v brew >/dev/null && [[ -f "$FILE" ]]; then
                    echo "🛡️ Trusting taps declared in $(basename $FILE)..."
                    while read -r tap; do
                        if [ -n "$tap" ]; then
                            brew trust "$tap" || true
                        fi
                    done < <(grep -E '^tap "' "$FILE" | sed -E 's/tap "([^"]+)".*/\1/')
                fi
                # brew bundle aborts the whole bundle if a single fetch fails
                # (e.g. upstream re-uploaded a cask artifact → checksum drift).
                # Fall back to per-entry installs so one broken package cannot
                # block the rest; report the casualties at the end.
                if ! brew bundle --file="$FILE"; then
                    echo "⚠️ Bundle aborted — retrying entries individually to isolate the breakage..."
                    FAILED=()
                    while read -r kind name; do
                        case $kind in
                            brew)
                                brew list --formula "${name##*/}" &>/dev/null ||
                                    brew install --formula "$name" ||
                                    FAILED+=("formula: $name")
                                ;;
                            cask)
                                brew list --cask "${name##*/}" &>/dev/null ||
                                    brew install --cask "$name" ||
                                    FAILED+=("cask: $name (may be macOS-only or upstream checksum drift)")
                                ;;
                            flatpak)
                                # No hardcoded remote: entries may live outside flathub
                                # (e.g. flatpakref-based remotes); let flatpak resolve.
                                flatpak info "$name" &>/dev/null ||
                                    flatpak install -y "$name" ||
                                    FAILED+=("flatpak: $name (remote may need setup — check Brewfile remote: option)")
                                ;;
                        esac
                    done < <(grep -E '^(brew|cask|flatpak) "' "$FILE" | sed -E 's/^(brew|cask|flatpak) "([^"]+)".*/\1 \2/')
                    if [ "${#FAILED[@]}" -gt 0 ]; then
                        echo "❌ Entries still failing in $(basename $FILE):"
                        printf '   %s\n' "${FAILED[@]}"
                        OVERALL_RC=1
                    else
                        echo "✅ All entries recovered individually."
                    fi
                fi
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

    if [ "$OVERALL_RC" -ne 0 ]; then
        echo "Done with failures — the $FLAVOR experience (action: $ACTION) is partially ready. See ❌ above."
        exit "$OVERALL_RC"
    fi
    echo "Done! The $FLAVOR experience (action: $ACTION) is ready."

# Monitor eBPF Performance (Requires sudo)
monitor-ebpf:
    #!/usr/bin/bash
    sudo bpftop
