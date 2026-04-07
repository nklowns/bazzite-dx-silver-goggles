# vim: set ft=make :
# ==============================================================================
# GROUP 1: Status & Health
# ==============================================================================

# Check hardware and system health status (G15 specific)
[group('Status')]
status:
    /usr/bin/g15-status

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
            echo "🚀 Activating: Silver-Goggles Personal Suite..."
            # Ensure ElyPrism remote is present (it's not on Flathub)
            flatpak remote-add --user --if-not-exists elyprismlauncher https://elyprismlauncher.github.io/flatpak/elyprismlauncher.flatpakref || true
            brew bundle --file=/usr/share/ublue-os/homebrew/silver-goggles.Brewfile
            ;;
        check)
            echo "🔍 Checking status of Personal Suite..."
            brew bundle check --file=/usr/share/ublue-os/homebrew/silver-goggles.Brewfile
            ;;
        cleanup)
            echo "🧹 Cleaning up unused packages..."
            brew bundle cleanup --file=/usr/share/ublue-os/homebrew/silver-goggles.Brewfile
            ;;
        *)
            echo "Unknown action: $ACTION"
            exit 1
            ;;
    esac
    echo "Done! The Silver-Goggles experience is ready."
