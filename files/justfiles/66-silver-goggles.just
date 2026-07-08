# vim: set ft=make :
# ==============================================================================
# GROUP 1: Status & Health
# ==============================================================================

# Check hardware and system health status (G15 specific)
[group('Status')]
status:
    /usr/bin/g15-status

# Audit the Silver Goggles shell experience (bling infrastructure + tools)
[group('Status')]
bling-check:
    /usr/bin/bling-check

# ==============================================================================
# GROUP 2: Network & Privacy (Tailscale)
# ==============================================================================

# 🛡️ Initialize native Tailscale Tray with Systemd user integration
[group('Network')]
init-tailscale-systray:
    tailscale configure systray --enable-startup=systemd
    systemctl --user daemon-reload
    systemctl --user enable --now tailscale-systray

# ==============================================================================
# GROUP 3: Setup & Packages
# ==============================================================================

# Configure Silver-Goggles Personal Suite (Flatpaks & Brew)
[group('Setup')]
setup-personal-suite action="":
    #!/usr/bin/env bash
    set -e
    ACTION="{{ action }}"
    if [[ -z "$ACTION" ]]; then
        echo "Choose action for Silver-Goggles Suite (Personal/Gaming):"
        ACTION=$(gum choose "install" "check" "cleanup")
    fi
    case $ACTION in
        install)
            echo "🚀 Provisioning: Silver-Goggles Personal Suite..."
            # Ensure ElyPrism remote is present (it's not on Flathub)
            flatpak remote-add --user --if-not-exists elyprismlauncher https://elyprismlauncher.github.io/flatpak/elyprismlauncher.flatpakref || true
            # Trust taps declared in the Brewfile before bundle installation
            if command -v brew >/dev/null; then
                echo "🛡️ Trusting taps declared in silver-goggles.Brewfile..."
                while read -r tap; do
                    if [ -n "$tap" ]; then
                        brew trust "$tap" || true
                    fi
                done < <(grep -E '^tap "' "/usr/share/ublue-os/homebrew/silver-goggles.Brewfile" | sed -E 's/tap "([^"]+)".*/\1/')
            fi
            brew bundle --file=/usr/share/ublue-os/homebrew/silver-goggles.Brewfile
            ;;
        check)
            echo "🔍 Auditing Personal Suite status..."
            brew bundle check --file=/usr/share/ublue-os/homebrew/silver-goggles.Brewfile
            ;;
        cleanup)
            echo "🧹 Purging unused packages..."
            brew bundle cleanup --file=/usr/share/ublue-os/homebrew/silver-goggles.Brewfile
            ;;
        *)
            echo "Unknown action: $ACTION"
            exit 1
            ;;
    esac
    echo "Done! The Silver-Goggles experience is ready."

# 🛡️ Trust all currently configured and third-party Homebrew taps (Resolves trust warnings)
[group('Setup')]
brew-trust-taps:
    #!/usr/bin/env bash
    set -e
    if ! command -v brew >/dev/null; then
        echo "Homebrew is not installed or not in PATH."
        exit 1
    fi
    echo "🛡️ Trusting all third-party Homebrew taps..."
    brew tap | grep -vE '^(homebrew/)' | while read -r tap; do
        if [[ -n "$tap" ]]; then
            echo "Trusting tap: $tap"
            brew trust "$tap" || true
        fi
    done
    echo "Done! Homebrew taps trusted successfully."

# ==============================================================================
# GROUP 4: Hardware & Input
# ==============================================================================

# Toggle laptop's built-in keyboard (enable/disable/toggle/status)
[group('Hardware')]
toggle-keyboard state="toggle":
    #!/usr/bin/env bash
    CMD="/usr/bin/udev-keyboard-handler"
    if [[ ! -x "$CMD" && -x "/usr/local/bin/udev-keyboard-handler" ]]; then
        CMD="/usr/local/bin/udev-keyboard-handler"
    fi

    if [[ ! -x "$CMD" ]]; then
        echo "Error: Keyboard handler script not found in /usr/bin or /usr/local/bin."
        exit 1
    fi

    "$CMD" "{{ state }}"
