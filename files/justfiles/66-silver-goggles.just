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

# Install recommended Flatpaks and Brew packages (Personal Suite)
[group('Setup')]
setup-default-apps:
    #!/usr/bin/env bash
    set -eoux pipefail
    echo "🚀 Installing Flatpaks..."
    flatpak install -y flathub \
        dev.vencord.Vesktop com.spotify.Client org.qbittorrent.qBittorrent \
        io.podman_desktop.PodmanDesktop \
        com.obsproject.Studio com.google.Chrome \
        md.obsidian.Obsidian us.zoom.Zoom \
        com.rustdesk.RustDesk \
        net.retrodeck.retrodeck com.heroicgameslauncher.hgl \
        io.github.Faugus.faugus-launcher io.github.unknownskl.greenlight

    flatpak install -y \
        https://elyprismlauncher.github.io/flatpak/elyprismlauncher.flatpakref

    echo "🍺 Installing Brew Packages..."
    brew tap ublue-os/experimental-tap
    brew tap ublue-os/tap
    brew install act cosign mise opentofu gh libpq gcloud-cli chezmoi \
        ublue-os/tap/antigravity-linux ublue-os/tap/visual-studio-code-linux
