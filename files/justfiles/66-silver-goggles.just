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

# 🔓 Ligar autologin + bloqueio imediato, para o Sunshine sobreviver a um reboot remoto
[group('Network')]
autologin-setup:
    #!/usr/bin/env bash
    set -euo pipefail
    # The two halves are enabled together and only together. Autologin alone leaves a desktop
    # open to anyone who walks up; the lock alone does nothing. Splitting them into separate
    # recipes would make the dangerous combination reachable by typing one of two commands.
    #
    # Autologin itself is NOT set here, and not by the image either. It belongs to
    # System Settings → Login Screen, which writes /etc/plasmalogin.conf. A boot service that
    # rewrote that would silently undo whatever was chosen in the UI, and the KDE UI also knows
    # details a shell script would get wrong — it writes `Session=plasma.desktop`, and the
    # suffix is load-bearing. What the image does is clear the obstacles: end the first-run
    # wizard that rewrites autologin on every boot, and delete its stale drop-in
    # (ClearAutologinObstacles in /usr/libexec/bazzite-dx-groups).
    AUTOLOGIN_USER=$(grep -oP '^\s*User=\K.*' /etc/plasmalogin.conf 2>/dev/null | tail -1)
    if [[ -z "${AUTOLOGIN_USER:-}" ]]; then
        echo "❌ Autologin não está configurado."
        echo "   Configure em: System Settings → Login Screen → Autologin (usuário e sessão)."
        echo "   Volte aqui depois para ligar o bloqueio — autologin sem bloqueio deixa a"
        echo "   máquina aberta para quem chegar nela, que é pior que a tela de login."
        exit 1
    fi
    if ! id "$AUTOLOGIN_USER" >/dev/null 2>&1; then
        echo "❌ Autologin aponta para '$AUTOLOGIN_USER', que não existe neste sistema."
        echo "   A máquina vai parar na tela de login — corrija em System Settings."
        exit 1
    fi
    echo "Autologin configurado para: $AUTOLOGIN_USER"
    # Enabled, not started: this one has to fire at every login, which is exactly what the
    # Boot Impact Policy tells recipes not to do. The exception is deliberate and narrow — it is
    # a oneshot that locks the screen and exits, so it competes for nothing, and leaving it
    # disabled would leave autologin unguarded. Documented alongside the rule in AGENTS.md.
    systemctl --user enable --now lock-on-session-start.service
    echo "✅ Autologin + bloqueio ativos."
    echo "   No próximo boot a sessão abre sozinha e trava — o Sunshine passa a estar de pé"
    echo "   sem ninguém ir até a máquina, e você destrava pelo Moonlight."

# 🔒 Desligar o bloqueio automático da sessão
[group('Network')]
autologin-teardown:
    #!/usr/bin/env bash
    set -uo pipefail
    # Only the lock is undone here. Autologin lives in System Settings and is not this recipe's
    # to remove — silently deleting a setting the user made in the UI is the same disrespect,
    # in the opposite direction, that keeping it out of the boot service avoids.
    systemctl --user disable --now lock-on-session-start.service 2>/dev/null || true
    echo "🔓 Bloqueio automático desligado."
    AUTOLOGIN_USER=$(grep -oP '^\s*User=\K.*' /etc/plasmalogin.conf 2>/dev/null | tail -1)
    if [[ -n "${AUTOLOGIN_USER:-}" ]]; then
        echo "⚠️  Autologin SEGUE ATIVO para '$AUTOLOGIN_USER' — a sessão vai abrir sozinha e"
        echo "   agora sem travar. Para desligá-lo: System Settings → Login Screen."
    fi

# 🌐 Iniciar o Cockpit (Painel de Administração Web :61390) sob demanda
[group('Network')]
cockpit-up:
    #!/usr/bin/env bash
    set -euo pipefail
    sudo systemctl start cockpit.socket
    /usr/libexec/bazzite-dx-serve ensure 61390 || true
    DNS_NAME=$(tailscale status --self --json | jq -r '.Self.DNSName' | sed 's/\.$//')
    echo "✅ Cockpit ativo em: https://$DNS_NAME:61390 (local: https://localhost:61390)"

# 🛑 Parar o Cockpit
[group('Network')]
cockpit-down:
    #!/usr/bin/env bash
    set -uo pipefail
    sudo systemctl stop cockpit.socket cockpit.service 2>/dev/null || true
    echo "🛑 Cockpit desativado."

# 📊 Diagnóstico do Cockpit
[group('Network')]
cockpit-status:
    #!/usr/bin/env bash
    set -uo pipefail
    SOCKET_STATE=$(systemctl is-active cockpit.socket 2>/dev/null || true)
    SOCKET_ENABLED=$(systemctl is-enabled cockpit.socket 2>/dev/null || true)
    printf "%-16s %s (boot: %s)\n" "cockpit.socket:" "${SOCKET_STATE:-inactive}" "${SOCKET_ENABLED:-disabled}"
    if [[ "$SOCKET_STATE" == "active" ]]; then
        DNS_NAME=$(tailscale status --self --json 2>/dev/null | jq -r '.Self.DNSName' | sed 's/\.$//' || true)
        echo "   Painel Web: https://${DNS_NAME:-localhost}:61390"
    fi

# ⚡ Habilitar Cockpit no boot do sistema (Ative e esqueça)
[group('Network')]
cockpit-enable-boot:
    #!/usr/bin/env bash
    set -euo pipefail
    just cockpit-up
    sudo systemctl enable cockpit.socket
    echo "⚡ Cockpit habilitado para iniciar automaticamente no boot do sistema!"

# 🔌 Desabilitar Cockpit do boot do sistema
[group('Network')]
cockpit-disable-boot:
    #!/usr/bin/env bash
    set -uo pipefail
    sudo systemctl disable cockpit.socket
    echo "🔌 Cockpit removido do boot automático. Use 'ujust cockpit-up' quando precisar."

# 🔒 Expose Sunshine Web UI (:61395) privately via tailscale serve and provision multi-monitor apps
[group('Network')]
remote-sunshine-setup:
    #!/usr/bin/env bash
    set -euo pipefail
    if ! ss -tln 2>/dev/null | grep -q ':47990 '; then
        echo "❌ Nada escutando em 47990. O Sunshine Web UI está ativo?"
        echo "   Se necessário, inicie o serviço com: ujust sunshine-up"
        exit 1
    fi
    CONF_FILE="$HOME/.config/sunshine/sunshine.conf"
    if [ -f "$CONF_FILE" ] && ! grep -q 'origin_web_ui_allowed = pc' "$CONF_FILE"; then
        echo "origin_web_ui_allowed = pc" >> "$CONF_FILE"
        systemctl --user restart sunshine.service 2>/dev/null || true
    fi
    /usr/libexec/bazzite-dx-sunshine-apps
    /usr/libexec/bazzite-dx-serve ensure 61395 47990 https+insecure
    DNS_NAME=$(tailscale status --self --json | jq -r '.Self.DNSName' | sed 's/\.$//')
    echo "Sunshine Web UI ready at: https://$DNS_NAME:61395"

# 🎮 Provision multi-monitor display shortcuts (Tela 1 Notebook, Tela 2 AOC) in Sunshine apps.json
[group('Network')]
remote-sunshine-multimon-setup:
    #!/usr/bin/env bash
    set -euo pipefail
    /usr/libexec/bazzite-dx-sunshine-apps
    systemctl --user try-restart sunshine.service || true
    echo "✅ Sunshine multi-monitor apps ready. Connect via Moonlight to select Tela 1 (Notebook) or Tela 2 (AOC)!"

# ⚡ Check Wake-on-LAN (WoL) and background idle inhibitor status
[group('Network')]
wol-status:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "== Wake-on-LAN (WoL) Configuration =="
    nmcli c show "Wired connection 1" 2>/dev/null | grep -i wake-on-lan || echo "Wired connection 1 not configured"
    nmcli c show "PRX-SEM.NUVEM-5G" 2>/dev/null | grep -i wake-on-wlan || echo "Wi-Fi WoL default"
    echo ""
    echo "== Background Idle Inhibitor Status =="
    if [ -x /usr/bin/smart-idle-checker ]; then
        /usr/bin/smart-idle-checker || true
    elif [ -x /usr/local/bin/smart-idle-checker ]; then
        /usr/local/bin/smart-idle-checker || true
    elif [ -x ./files/system/usr/bin/smart-idle-checker ]; then
        ./files/system/usr/bin/smart-idle-checker || true
    fi

# 🎥 Configure virtual webcam receiver (/dev/video10) from Windows GUEST RTSP stream
[group('Network')]
remote-webcam-setup win_ip="100.108.150.113":
    #!/usr/bin/env bash
    set -euo pipefail
    WIN_IP="{{ win_ip }}"
    if [ -x /usr/bin/webcam-receiver ]; then
        /usr/bin/webcam-receiver "$WIN_IP"
    elif [ -x ./files/system/usr/bin/webcam-receiver ]; then
        ./files/system/usr/bin/webcam-receiver "$WIN_IP"
    else
        echo "❌ /usr/bin/webcam-receiver not found"
        exit 1
    fi

# 🎮 Iniciar o Sunshine Game Streaming sob demanda
[group('Network')]
sunshine-up:
    #!/usr/bin/env bash
    set -euo pipefail
    systemctl --user daemon-reload
    systemctl --user start sunshine.service
    /usr/libexec/bazzite-dx-sunshine-apps || true
    echo "✅ Sunshine Game Streaming ativo."
    echo "   Para parear clientes ou configurar: Moonlight / https://localhost:47990"

# 🛑 Parar o Sunshine Game Streaming
[group('Network')]
sunshine-down:
    #!/usr/bin/env bash
    set -uo pipefail
    systemctl --user stop sunshine.service
    echo "🛑 Sunshine Game Streaming desativado."

# 📊 Diagnóstico do Sunshine Game Streaming
[group('Network')]
sunshine-status:
    #!/usr/bin/env bash
    set -uo pipefail
    STATE=$(systemctl --user is-active sunshine.service 2>/dev/null || true)
    ENABLED=$(systemctl --user is-enabled sunshine.service 2>/dev/null || true)
    printf "%-12s %s (boot: %s)\n" "sunshine:" "${STATE:-inactive}" "${ENABLED:-disabled}"
    if ss -tln 2>/dev/null | grep -q ':47990 '; then
        echo "   Web UI: http://localhost:47990"
    fi

# ⚡ Habilitar Sunshine no boot da sessão (Ative e esqueça)
[group('Network')]
sunshine-enable-boot:
    #!/usr/bin/env bash
    set -euo pipefail
    systemctl --user daemon-reload
    systemctl --user enable sunshine.service
    just sunshine-up
    echo "⚡ Sunshine habilitado para iniciar automaticamente no login!"

# 🔌 Desabilitar Sunshine do boot
[group('Network')]
sunshine-disable-boot:
    #!/usr/bin/env bash
    set -uo pipefail
    systemctl --user disable sunshine.service
    echo "🔌 Sunshine removido do boot automático. Use 'ujust sunshine-up' quando precisar."

# 🦀 Iniciar o RustDesk (Acesso Remoto Seguro) sob demanda
[group('Network')]
rustdesk-up:
    #!/usr/bin/env bash
    set -euo pipefail
    if ! flatpak info com.rustdesk.RustDesk >/dev/null 2>&1; then
        echo "Instalando com.rustdesk.RustDesk..."
        flatpak install -y com.rustdesk.RustDesk 2>/dev/null || flatpak install --user -y com.rustdesk.RustDesk 2>/dev/null || true
    fi
    mkdir -p "$HOME/.config/autostart"
    ln -sf /dev/null "$HOME/.config/autostart/com.rustdesk.RustDesk.desktop" 2>/dev/null || true
    flatpak override --user --talk-name=org.kde.StatusNotifierWatcher --talk-name=org.freedesktop.StatusNotifierWatcher --talk-name=org.freedesktop.Notifications com.rustdesk.RustDesk 2>/dev/null || true
    CONF="$HOME/.var/app/com.rustdesk.RustDesk/config/rustdesk/RustDesk2.toml"
    mkdir -p "$(dirname "$CONF")"
    if [ -f /usr/share/ublue-os/rustdesk/RustDesk2.toml.template ] && [ ! -s "$CONF" ]; then
        cp /usr/share/ublue-os/rustdesk/RustDesk2.toml.template "$CONF"
    fi
    systemctl --user daemon-reload
    systemctl --user start rustdesk.service
    echo "✅ RustDesk ativo."
    if command -v tailscale >/dev/null && tailscale status >/dev/null 2>&1; then
        DNS_NAME=$(tailscale status --self --json | jq -r '.Self.DNSName' | sed 's/\.$//')
        TS_IP=$(tailscale ip -4 2>/dev/null | head -1)
        echo "🔒 Tailnet: $DNS_NAME ($TS_IP)"
        echo "💡 Direct IP Connection: No cliente RustDesk no Windows, use Direct IP -> '$TS_IP:21118'."
    fi

# 🛑 Parar o RustDesk
[group('Network')]
rustdesk-down:
    #!/usr/bin/env bash
    set -uo pipefail
    systemctl --user stop rustdesk.service
    echo "🛑 RustDesk desativado."

# 📊 Diagnóstico do RustDesk
[group('Network')]
rustdesk-status:
    #!/usr/bin/env bash
    set -uo pipefail
    STATE=$(systemctl --user is-active rustdesk.service 2>/dev/null || true)
    ENABLED=$(systemctl --user is-enabled rustdesk.service 2>/dev/null || true)
    printf "%-12s %s (boot: %s)\n" "rustdesk:" "${STATE:-inactive}" "${ENABLED:-disabled}"

# ⚡ Habilitar RustDesk no boot / login (Ative e esqueça)
[group('Network')]
rustdesk-enable-boot:
    #!/usr/bin/env bash
    set -euo pipefail
    just rustdesk-up
    systemctl --user enable rustdesk.service
    echo "⚡ RustDesk habilitado para iniciar automaticamente no login!"

# 🔌 Desabilitar RustDesk do boot / login
[group('Network')]
rustdesk-disable-boot:
    #!/usr/bin/env bash
    set -uo pipefail
    systemctl --user disable rustdesk.service
    echo "🔌 RustDesk removido do boot automático. Use 'ujust rustdesk-up' quando precisar."

# 🔒 Iniciar o Apache Guacamole (:61392) sob demanda
[group('Network')]
guacamole-up:
    #!/usr/bin/env bash
    set -euo pipefail
    if ! ss -tln 2>/dev/null | grep -q ':61392 '; then
        podman run -d --name guacamole-desktop \
            --restart=unless-stopped \
            -p 127.0.0.1:61392:8080 \
            -e OPT_MYSQL=false \
            docker.io/jwetzell/guacamole:latest 2>/dev/null || podman start guacamole-desktop 2>/dev/null || true
    fi
    /usr/libexec/bazzite-dx-serve ensure 61392 61392 http || true
    DNS_NAME=$(tailscale status --self --json | jq -r '.Self.DNSName' | sed 's/\.$//')
    echo "✅ Guacamole pronto em: https://$DNS_NAME:61392 (login: guacadmin / guacadmin)"

# 🛑 Parar o Apache Guacamole
[group('Network')]
guacamole-down:
    #!/usr/bin/env bash
    set -uo pipefail
    podman stop guacamole-desktop 2>/dev/null || true
    echo "🛑 Guacamole desativado."

# 📊 Diagnóstico do Apache Guacamole
[group('Network')]
guacamole-status:
    #!/usr/bin/env bash
    set -uo pipefail
    podman ps --filter name=guacamole-desktop --format 'table {{{{.Names}}\t{{{{.Status}}\t{{{{.Ports}}' 2>/dev/null || true

# 🌐 Expor o Cockpit Web Admin (:61390) via Tailscale
[group('Network')]
remote-cockpit-setup:
    #!/usr/bin/env bash
    set -euo pipefail
    /usr/libexec/bazzite-dx-serve ensure 61390 61390 http || true
    DNS_NAME=$(tailscale status --self --json 2>/dev/null | jq -r '.Self.DNSName' | sed 's/\.$//' || echo "localhost")
    echo "✅ Cockpit Web Admin pronto em: https://$DNS_NAME:61390"

# 🛑 Desativar a exposição do Cockpit Web Admin no Tailscale
[group('Network')]
remote-cockpit-teardown:
    #!/usr/bin/env bash
    set -euo pipefail
    /usr/libexec/bazzite-dx-serve off 61390 || true
    echo "🛑 Cockpit removido do Tailscale serve."

# 📊 Diagnóstico do Cockpit Web Admin
[group('Network')]
remote-cockpit-status:
    #!/usr/bin/env bash
    set -uo pipefail
    SOCKET_STATE=$(systemctl is-active cockpit.socket 2>/dev/null || true)
    SOCKET_ENABLED=$(systemctl is-enabled cockpit.socket 2>/dev/null || true)
    printf "%-16s %s (socket: %s)\n" "cockpit.socket:" "${SOCKET_STATE:-inactive}" "${SOCKET_ENABLED:-disabled}"
    SERVE_STATE=$(/usr/libexec/bazzite-dx-serve status 61390 61390 http 2>/dev/null || echo "absent")
    printf "%-16s %s\n" "tailscale serve:" "$SERVE_STATE"
    if [[ "$SOCKET_STATE" == "active" ]]; then
        DNS_NAME=$(tailscale status --self --json 2>/dev/null | jq -r '.Self.DNSName' | sed 's/\.$//' || true)
        echo "   URL: https://${DNS_NAME:-localhost}:61390"
    fi

# ⌨️ Setup Deskflow (Software KVM for sharing mouse & keyboard across PCs over Tailscale)
[group('Network')]
remote-deskflow-setup:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "⌨️ Installing Deskflow (KVM Mouse/Keyboard Share over Tailscale)..."
    flatpak install --user -y flathub com.deskflow.deskflow || true
    echo "✅ Deskflow installed."
    if command -v tailscale >/dev/null && tailscale status >/dev/null 2>&1; then
        DNS_NAME=$(tailscale status --self --json | jq -r '.Self.DNSName' | sed 's/\.$//')
        TS_IP=$(tailscale ip -4 2>/dev/null | head -1)
        echo "🔒 Tailnet Server Address: $DNS_NAME:24800 (IP: $TS_IP:24800)"
        echo "💡 In Deskflow client on Guest, point server IP to '$TS_IP' to control Host screens with zero video overhead."
    fi

# 🛡️ Master Status & Manager for Remote Access Suite (Sunshine, KasmVNC, Webcam, Mic, Taildrop)
[group('Network')]
remote-suite action="status":
    #!/usr/bin/env bash
    set -euo pipefail
    ACTION="{{ action }}"
    if [ -x /usr/bin/remote-suite ]; then
        /usr/bin/remote-suite "$ACTION"
    elif [ -x ./files/system/usr/bin/remote-suite ]; then
        ./files/system/usr/bin/remote-suite "$ACTION"
    else
        echo "❌ /usr/bin/remote-suite script not found"
        exit 1
    fi

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

# Show or switch the chassis power profile (fan behaviour follows it) — no root needed
[group('Hardware')]
g15-profile profile="":
    #!/usr/bin/env bash
    set -uo pipefail
    PROV=/sys/class/platform-profile/platform-profile-0
    PPD=(--system net.hadess.PowerProfiles /net/hadess/PowerProfiles net.hadess.PowerProfiles ActiveProfile)
    HW=$(for d in /sys/class/hwmon/hwmon*; do [[ "$(cat "$d/name" 2>/dev/null)" == alienware_wmi ]] && echo "$d"; done)

    if [[ ! -d "$PROV" ]]; then
        echo "No platform-profile provider at $PROV — is this the Dell G15 with alienware-wmi loaded?"
        exit 1
    fi

    # Go through PowerProfiles, not sysfs. tuned-ppd owns platform_profile and KDE powerdevil is
    # a client; writing the sysfs node directly means two writers and, as this repo learned the
    # hard way, the daemon wins on the next event. polkit lets the active session set this, so
    # no root is involved.
    if [[ -z "{{ profile }}" ]]; then
        printf "%-14s %s\n" "active:" "$(busctl get-property "${PPD[@]}" 2>/dev/null | sed 's/^s "//; s/"$//')"
        printf "%-14s %s\n" "sysfs:" "$(cat "$PROV/profile")"
        printf "%-14s %s\n" "choices:" "$(cat "$PROV/choices")"
        if [[ -n "$HW" ]]; then
            printf "%-14s %s/%s (fans %s/%s rpm, max %s)\n" "fan boost:" \
                "$(cat "$HW/fan1_boost")" "$(cat "$HW/fan2_boost")" \
                "$(cat "$HW/fan1_input")" "$(cat "$HW/fan2_input")" "$(cat "$HW/fan1_max")"
        fi
        echo ""
        echo "Usage: ujust g15-profile <balanced|performance|...>"
        echo "  Measured here: on a GPU-bound load 'performance' is worth ~+105MHz sustained and"
        echo "  +20W of board power at 80s; on a CPU-bound load it is worth ~0MHz. Prefer"
        echo "  'g15-boost <command>' (or the Steam launch option 'g15-boost %command%') so the"
        echo "  fans only spin up while something is actually running."
        exit 0
    fi

    if ! grep -qw -- "{{ profile }}" "$PROV/choices"; then
        echo "Unknown profile '{{ profile }}'. This provider accepts: $(cat "$PROV/choices")"
        exit 1
    fi

    if ! busctl set-property "${PPD[@]}" s "{{ profile }}"; then
        echo "PowerProfiles refused the change. Is tuned-ppd running?"
        exit 1
    fi
    sleep 2
    printf "profile=%s" "$(cat "$PROV/profile")"
    [[ -n "$HW" ]] && printf "  fan boost=%s/%s" "$(cat "$HW/fan1_boost")" "$(cat "$HW/fan2_boost")"
    echo ""
    echo "Note: KDE re-asserts its own choice per AC/battery state at login. To make this the"
    echo "default, set it in System Settings > Power Management, not here."

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

# ==============================================================================
# GROUP 5: Remote IDE Access (code-server + VS Code family Remote Tunnels)
#
# The stack follows the same on-demand up / down / status philosophy:
# - `ujust code-server-up` / `ujust code-server-down`: Start/stop code-server on demand.
# - `ujust ide-tunnel-up <name>` / `ujust ide-tunnel-down <name>`: Start/stop tunnels on demand.
# - `ujust code-server-enable-boot` / `ujust code-server-disable-boot`: Opt-in to start automatically on boot.
# - Password and endpoints are managed cleanly via `ujust code-server-password` / `ujust remote-ide-status`.
# ==============================================================================

# 🌐 Iniciar o code-server (:61337) sob demanda e expor no Tailscale
[group('Remote IDE')]
code-up:
    #!/usr/bin/env bash
    set -euo pipefail
    REF_DIR="/usr/share/ublue-os/remote-ide"
    CONF_DIR="$HOME/.config/code-server"

    if ! command -v code-server >/dev/null 2>&1; then
        echo "❌ code-server não encontrado. Rode 'ujust setup-personal-suite install' primeiro."
        exit 1
    fi

    mkdir -p "$CONF_DIR"
    umask 077
    if [[ ! -f "$CONF_DIR/config.yaml" ]]; then
        PASS=$(openssl rand -base64 18)
        sed "s|__GENERATE__|$PASS|" "$REF_DIR/code-server-config.yaml.tmpl" >"$CONF_DIR/config.yaml"
        chmod 600 "$CONF_DIR/config.yaml"
        echo "🔑 Senha gerada para o code-server: $PASS"
    fi

    systemctl --user daemon-reload
    systemctl --user start code-server.service

    if /usr/libexec/bazzite-dx-serve ensure 61337; then
        DNS_NAME=$(tailscale status --self --json 2>/dev/null | jq -r '.Self.DNSName' | sed 's/\.$//')
        echo "✅ code-server ativo em: https://$DNS_NAME:61337 (local: http://127.0.0.1:61337)"
    else
        echo "✅ code-server ativo em http://127.0.0.1:61337 (aviso: Tailscale Serve não configurado)"
    fi
    echo "   Para ver a senha de acesso: ujust code-password"

alias code-server-up := code-up

# 🛑 Parar o code-server e liberar memória
[group('Remote IDE')]
code-down:
    #!/usr/bin/env bash
    set -uo pipefail
    systemctl --user stop code-server.service
    echo "🛑 code-server desativado. Recursos liberados."

alias code-server-down := code-down

# 🔑 Exibir ou redefinir a senha do code-server
[group('Remote IDE')]
code-password new_password="":
    #!/usr/bin/env bash
    set -euo pipefail
    CONF_DIR="$HOME/.config/code-server"
    CONF_FILE="$CONF_DIR/config.yaml"
    NEW_PASS="{{ new_password }}"

    if [[ ! -f "$CONF_FILE" ]]; then
        echo "❌ Configuração do code-server não encontrada em $CONF_FILE."
        echo "   Inicie com 'ujust code-up' primeiro."
        exit 1
    fi

    if [[ -n "$NEW_PASS" ]]; then
        sed -i "s/^password:.*/password: $NEW_PASS/" "$CONF_FILE"
        chmod 600 "$CONF_FILE"
        systemctl --user try-restart code-server.service || true
        echo "✅ Senha do code-server atualizada com sucesso!"
    else
        CURRENT_PASS=$(sed -n 's/^password:[[:space:]]*//p' "$CONF_FILE" | head -1)
        echo "🔑 Senha atual do code-server: $CURRENT_PASS"
        echo "💡 Para alterar: ujust code-password <sua-nova-senha>"
    fi

alias code-server-password := code-password

# ⚡ Habilitar code-server para iniciar automaticamente no boot (Ative e esqueça)
[group('Remote IDE')]
code-enable-boot:
    #!/usr/bin/env bash
    set -euo pipefail
    just code-up
    systemctl --user enable code-server.service
    echo "⚡ code-server habilitado para iniciar automaticamente no boot!"

alias code-server-enable-boot := code-enable-boot

# 🔌 Desabilitar code-server da inicialização automática do boot
[group('Remote IDE')]
code-disable-boot:
    #!/usr/bin/env bash
    set -uo pipefail
    systemctl --user disable code-server.service
    echo "🔌 code-server removido do boot automático. Use 'ujust code-up' quando precisar."

alias code-server-disable-boot := code-disable-boot

# 🚀 Iniciar um VS Code Remote Tunnel (code, code-insiders) sob demanda
[group('Remote IDE')]
ide-tunnel-up name="code-insiders":
    #!/usr/bin/env bash
    set -euo pipefail
    NAME="{{ name }}"
    REF_DIR="/usr/share/ublue-os/remote-ide"
    TUNNEL_ENV_DIR="$HOME/.config/ide-tunnel"
    ENV_FILE="$TUNNEL_ENV_DIR/$NAME.env"

    if [[ "$NAME" == "antigravity" ]]; then
        echo "❌ antigravity-ide tunnel está aguardando binário dedicado upstream."
        exit 1
    fi

    mkdir -p "$TUNNEL_ENV_DIR"
    if [[ ! -f "$ENV_FILE" ]]; then
        if [[ -f "$REF_DIR/ide-tunnel-$NAME.env" ]]; then
            install -Dm644 "$REF_DIR/ide-tunnel-$NAME.env" "$ENV_FILE"
        else
            echo "❌ Configuração de túnel '$NAME' não encontrada."
            exit 1
        fi
    fi

    systemctl --user daemon-reload
    systemctl --user start "ide-tunnel@$NAME.service"
    echo "✅ Túnel '$NAME' iniciado."
    sleep 2
    URL=$(journalctl --user -u "ide-tunnel@$NAME" --no-pager 2>/dev/null | grep -F "Open:" | tail -1 | sed 's/.*Open:[[:space:]]*//')
    if [[ -n "$URL" ]]; then
        echo "🔗 Acesse em: $URL"
    else
        echo "ℹ️ Verifique o link de conexão ou autenticação em: journalctl --user -u ide-tunnel@$NAME -f"
    fi

# 🛑 Parar um VS Code Remote Tunnel
[group('Remote IDE')]
ide-tunnel-down name="code-insiders":
    #!/usr/bin/env bash
    set -uo pipefail
    NAME="{{ name }}"
    systemctl --user stop "ide-tunnel@$NAME.service"
    echo "🛑 Túnel '$NAME' desativado."

# ⚡ Habilitar um VS Code Remote Tunnel no boot (Ative e esqueça)
[group('Remote IDE')]
ide-tunnel-enable-boot name="code-insiders":
    #!/usr/bin/env bash
    set -euo pipefail
    NAME="{{ name }}"
    just ide-tunnel-up "$NAME"
    systemctl --user enable "ide-tunnel@$NAME.service"
    echo "⚡ Túnel '$NAME' habilitado para iniciar automaticamente no boot!"

# 🔌 Desabilitar um VS Code Remote Tunnel do boot
[group('Remote IDE')]
ide-tunnel-disable-boot name="code-insiders":
    #!/usr/bin/env bash
    set -uo pipefail
    NAME="{{ name }}"
    systemctl --user disable "ide-tunnel@$NAME.service"
    echo "🔌 Túnel '$NAME' removido do boot automático."

# Setup completo e login interativo no GitHub para Remote Tunnel
[group('Remote IDE')]
remote-ide-tunnel name:
    #!/usr/bin/env bash
    set -e
    NAME="{{ name }}"
    ENV_FILE="$HOME/.config/ide-tunnel/$NAME.env"
    REF_DIR="/usr/share/ublue-os/remote-ide"

    mkdir -p "$HOME/.config/ide-tunnel"
    if [[ ! -f "$ENV_FILE" && -f "$REF_DIR/ide-tunnel-$NAME.env" ]]; then
        install -Dm644 "$REF_DIR/ide-tunnel-$NAME.env" "$ENV_FILE"
    fi

    if [[ ! -f "$ENV_FILE" ]]; then
        echo "Unknown or unstaged tunnel '$NAME'."
        exit 1
    fi

    if [[ "$NAME" == "antigravity" ]]; then
        echo "antigravity-ide tunnel is broken upstream (missing antigravity-tunnel binary)."
        exit 1
    fi

    # shellcheck source=/dev/null
    source "$ENV_FILE"
    echo "Logging in to GitHub for $IDE_BINARY tunnel '$TUNNEL_NAME'..."
    "$IDE_BINARY" tunnel user login --provider github

    systemctl --user daemon-reload
    systemctl --user start "ide-tunnel@$NAME.service"
    echo "Tunnel '$TUNNEL_NAME' configurado e iniciado. Verifique 'ujust remote-ide-status'."

# Instalar e preparar infraestrutura de Remote IDE
[group('Remote IDE')]
remote-ide-setup:
    #!/usr/bin/env bash
    set -e
    REF_DIR="/usr/share/ublue-os/remote-ide"
    UNIT_DIR="$HOME/.config/systemd/user"
    CONF_DIR="$HOME/.config/code-server"
    TUNNEL_ENV_DIR="$HOME/.config/ide-tunnel"

    if ! command -v code-server >/dev/null 2>&1; then
        echo "code-server not found. Run 'ujust setup-personal-suite install' first."
        exit 1
    fi

    mkdir -p "$UNIT_DIR" "$CONF_DIR" "$TUNNEL_ENV_DIR"

    # Remove legacy copies from $HOME if present
    for unit in code-server.service ide-tunnel@.service; do
        if [[ -f "$UNIT_DIR/$unit" && ! -L "$UNIT_DIR/$unit" ]]; then
            rm -f "$UNIT_DIR/$unit"
            echo "Removed legacy $UNIT_DIR/$unit (now provided by the image)"
        fi
    done
    systemctl --user daemon-reload

    umask 077
    if [[ ! -f "$CONF_DIR/config.yaml" ]]; then
        PASS=$(openssl rand -base64 18)
        sed "s|__GENERATE__|$PASS|" "$REF_DIR/code-server-config.yaml.tmpl" >"$CONF_DIR/config.yaml"
        chmod 600 "$CONF_DIR/config.yaml"
        echo "Generated code-server password (save it): $PASS"
    fi

    for name in code code-insiders antigravity; do
        if [[ ! -f "$TUNNEL_ENV_DIR/$name.env" && -f "$REF_DIR/ide-tunnel-$name.env" ]]; then
            install -Dm644 "$REF_DIR/ide-tunnel-$name.env" "$TUNNEL_ENV_DIR/$name.env"
        fi
    done
    systemctl --user daemon-reload
    echo "✅ Ambiente Remote IDE pronto para uso."
    echo "   Para iniciar: ujust code-server-up"

# 📊 Diagnóstico dedicado do code-server e Remote Tunnels
[group('Remote IDE')]
remote-ide-status:
    #!/usr/bin/env bash
    set -uo pipefail
    echo "=== 🌐 CODE-SERVER ==="
    CS_STATE=$(systemctl --user is-active code-server.service 2>/dev/null || true)
    CS_ENABLED=$(systemctl --user is-enabled code-server.service 2>/dev/null || true)
    printf "%-12s %s (boot: %s)\n" "status:" "${CS_STATE:-inactive}" "${CS_ENABLED:-disabled}"
    if [[ "$CS_STATE" == "active" ]]; then
        DNS_NAME=$(tailscale status --self --json 2>/dev/null | jq -r '.Self.DNSName' | sed 's/\.$//' || true)
        echo "url:         https://${DNS_NAME:-localhost}:61337"
        PASS=$(sed -n 's/^password:[[:space:]]*//p' "$HOME/.config/code-server/config.yaml" 2>/dev/null || echo "(não encontrada)")
        echo "senha:       $PASS"
    fi

    echo ""
    echo "=== 🚇 VS CODE REMOTE TUNNELS ==="
    for name in code code-insiders antigravity; do
        ENV_FILE="$HOME/.config/ide-tunnel/$name.env"
        [[ -f "$ENV_FILE" ]] || continue
        STATE=$(systemctl --user is-active "ide-tunnel@$name.service" 2>/dev/null || true)
        ENABLED=$(systemctl --user is-enabled "ide-tunnel@$name.service" 2>/dev/null || true)
        printf "%-15s %s (boot: %s)\n" "$name:" "${STATE:-inactive}" "${ENABLED:-disabled}"
        if [[ "$STATE" == "active" ]]; then
            URL=$(journalctl --user -u "ide-tunnel@$name" --no-pager 2>/dev/null | grep -F "Open:" | tail -1 | sed 's/.*Open:[[:space:]]*//')
            [[ -n "$URL" ]] && echo "   🔗 $URL"
        fi
    done

alias ide-status := remote-ide-status
alias code-status := remote-ide-status

# ==============================================================================
# GROUP 8: GPU & Display Status (Dell G15 Hybrid / dGPU)
# ==============================================================================

# 📊 Diagnóstico da GPU ativa no KDE Plasma e consumo de VRAM
[group('Hardware')]
gpu-status:
    #!/usr/bin/env bash
    set -uo pipefail
    echo "=== GPU & Desktop (KDE Wayland) ==="
    echo "--- Renderer ---"
    qdbus --literal org.kde.KWin /KWin supportInformation 2>/dev/null | grep -E "OpenGL renderer string|Driver version" || echo "  (KWin via D-Bus indisponível)"
    echo
    echo "--- VRAM (RTX 3060) ---"
    if command -v nvidia-smi >/dev/null 2>&1; then
        nvidia-smi --query-gpu=memory.total,memory.used,memory.free --format=csv,noheader 2>/dev/null || true
    fi
    echo
    echo "--- Monitores ---"
    if [[ -f /sys/class/drm/card0-HDMI-A-1/status ]] && grep -q "^connected" /sys/class/drm/card0-HDMI-A-1/status 2>/dev/null; then
        echo "  HDMI: Conectado na NVIDIA (card0) — ~5.3 GB VRAM livre para IA/Jogos"
    elif grep -q "^connected" /sys/class/drm/card1-DP-*/status 2>/dev/null; then
        echo "  DisplayPort USB-C: Conectado na Intel (card1) — ~6.0 GB VRAM livre para IA/Jogos"
    else
        echo "  Tela interna: Intel (card1) — ~6.0 GB VRAM livre para IA/Jogos"
    fi

alias kwin-gpu-status := gpu-status
alias kde-gpu-status := gpu-status
