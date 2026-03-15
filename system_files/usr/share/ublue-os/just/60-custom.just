# vim: set ft=make :

# Check hardware and system health status
status:
    /usr/bin/g15-status

# Setup User Apps (Flatpak & Brew)
setup-apps:
    #!/usr/bin/env bash
    set -eoux pipefail
    echo "Installing Flatpaks..."
    flatpak install -y flathub \
        dev.vencord.Vesktop com.spotify.Client org.qbittorrent.qBittorrent \
        io.podman_desktop.PodmanDesktop \
        com.obsproject.Studio com.google.Chrome \
        md.obsidian.Obsidian us.zoom.Zoom \
        com.rustdesk.RustDesk dev.deedles.Trayscale \
        net.retrodeck.retrodeck com.heroicgameslauncher.hgl \
        io.github.Faugus.faugus-launcher io.github.unknownskl.greenlight \
        io.github.elyprismlauncher.ElyPrismLauncher

    echo "Installing Brew Packages..."
    brew tap ublue-os/experimental-tap
    brew tap ublue-os/tap
    brew install act cosign mise opentofu gh libpq gcloud-cli chezmoi \
        ublue-os/tap/antigravity-linux ublue-os/tap/visual-studio-code-linux

# Setup kernel arguments to match current system configuration
setup-kargs:
    rpm-ostree kargs --append-if-missing="vconsole.keymap=br" \
                     --append-if-missing="bluetooth.disable_ertm=1" \
                     --append-if-missing="kvm.ignore_msrs=1" \
                     --append-if-missing="kvm.report_ignored_msrs=0" \
                     --append-if-missing="intel_iommu=on" \
                     --append-if-missing="iommu=pt" \
                     --append-if-missing="rd.driver.pre=vfio-pci" \
                     --append-if-missing="vfio_pci.disable_vga=1"

# Check current kernel arguments
check-kargs:
    rpm-ostree kargs
