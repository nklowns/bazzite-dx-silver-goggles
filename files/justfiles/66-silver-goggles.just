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

# 🔒 Expose Cockpit (system admin UI, :61390) privately via tailscale serve
[group('Network')]
remote-cockpit-setup:
    #!/usr/bin/env bash
    set -euo pipefail
    if ! systemctl is-active --quiet cockpit.socket 2>/dev/null; then
        echo "cockpit.socket not active. Enable first: sudo systemctl enable --now cockpit.socket"
        exit 1
    fi
    # Cockpit moved off 9090 into the reserved 61300-61399 range — 9090 is Prometheus' default
    # and cockpit.socket squats it on every boot whether Cockpit is used or not. The drop-in
    # doing the move is files/system/usr/lib/systemd/system/cockpit.socket.d/10-port.conf, so
    # this only works on an image that carries it: check rather than announce a URL nobody can
    # open.
    if ! ss -tln 2>/dev/null | grep -q ':61390 '; then
        echo "❌ Nada escutando em 61390. Esta imagem já tem o drop-in que move o Cockpit?"
        echo "   Se acabou de rebasear, reinicie o socket:"
        echo "       sudo systemctl daemon-reload && sudo systemctl restart cockpit.socket"
        exit 1
    fi
    # Shared helper rather than an inline guard — see /usr/libexec/bazzite-dx-serve for why the
    # three recipes stopped rolling their own (the old grep matched the proxy target and
    # ignored the listener, so a service published on the wrong endpoint read as "already
    # correct" and never migrated).
    /usr/libexec/bazzite-dx-serve ensure 61390
    # A host that ran the pre-move recipe still publishes 9090, now pointing at a dead port.
    if [[ "$(/usr/libexec/bazzite-dx-serve status 9090)" != absent ]]; then
        echo "⚠️  Ainda existe um serve publicando 9090, agora sem nada escutando. Remova com:"
        echo "       sudo tailscale serve --https=9090 off"
    fi
    DNS_NAME=$(tailscale status --self --json | jq -r '.Self.DNSName' | sed 's/\.$//')
    echo "Cockpit ready at: https://$DNS_NAME:61390"

# 🔒 Expose Sunshine Web UI (:61395) privately via tailscale serve and provision multi-monitor apps
[group('Network')]
remote-sunshine-setup:
    #!/usr/bin/env bash
    set -euo pipefail
    if ! ss -tln 2>/dev/null | grep -q ':47990 '; then
        echo "❌ Nada escutando em 47990. O Sunshine Web UI está ativo?"
        echo "   Se necessário, inicie o serviço com: systemctl --user start homebrew.sunshine.service"
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

# 🎮 Provision multi-monitor display shortcuts (Tela 1, Tela 2, Dual Canvas 32:9) in Sunshine apps.json
[group('Network')]
remote-sunshine-multimon-setup:
    #!/usr/bin/env bash
    set -euo pipefail
    /usr/libexec/bazzite-dx-sunshine-apps
    systemctl --user try-restart homebrew.sunshine.service || true
    echo "✅ Sunshine multi-monitor apps ready. Connect via Moonlight to select Tela 1, Tela 2, or Dual Canvas!"

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

# 🔒 Expose Apache Guacamole + KRDP / Real Host Desktop (:61392) privately via tailscale serve
[group('Network')]
remote-guacamole-setup:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "🌐 Setting up Apache Guacamole on port 61392..."
    echo "⚠️ Note: KRDP is unstable on Bazzite Wayland/NVIDIA (bazzite#2173 - black screens/PipeWire crashes)."
    echo "💡 For reliable desktop access, prefer Sunshine in Desktop Mode or KasmVNC."
    if ! systemctl --user is-active --quiet krdp.service 2>/dev/null; then
        echo "⚙️ Enabling KDE Remote Desktop (KRDP) service..."
        systemctl --user enable --now krdp.service 2>/dev/null || true
    fi
    if ! ss -tln 2>/dev/null | grep -q ':61392 '; then
        echo "🚀 Spawning rootless Apache Guacamole container on 127.0.0.1:61392..."
        podman run -d --name guacamole-desktop \
            --restart=unless-stopped \
            -p 127.0.0.1:61392:8080 \
            -e OPT_MYSQL=false \
            docker.io/jwetzell/guacamole:latest 2>/dev/null || podman start guacamole-desktop 2>/dev/null || true
    fi
    /usr/libexec/bazzite-dx-serve ensure 61392 61392 http || true
    DNS_NAME=$(tailscale status --self --json | jq -r '.Self.DNSName' | sed 's/\.$//')
    echo "Guacamole ready at: https://$DNS_NAME:61392"
    echo "Default login: guacadmin / guacadmin"

# 🎮 Setup Parsec client (Note: Linux supports CLIENT mode only to access Windows hosts)
[group('Network')]
remote-parsec-setup:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "🎮 Installing Parsec client..."
    flatpak install --user -y flathub com.parsec.app || true
    echo "✅ Parsec installed."
    echo "⚠️ Note: Parsec on Linux operates as a CLIENT only (to connect to remote Windows hosts)."
    echo "💡 Multi-monitor tip: Use 'Add Screens' (Ctrl+Shift+S) when connected to a remote host."

# 🦀 Setup RustDesk open-source remote desktop client
[group('Network')]
remote-rustdesk-setup:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "🦀 Installing and preparing RustDesk (Tailscale-first remote access)..."
    if ! flatpak info com.rustdesk.RustDesk >/dev/null 2>&1; then
        flatpak install -y com.rustdesk.RustDesk 2>/dev/null || flatpak install --user -y com.rustdesk.RustDesk 2>/dev/null || true
    fi
    rm -f "$HOME/.config/autostart/com.rustdesk.RustDesk.desktop" 2>/dev/null || true
    CONF="$HOME/.var/app/com.rustdesk.RustDesk/config/rustdesk/RustDesk2.toml"
    mkdir -p "$(dirname "$CONF")"
    if [ -f /usr/share/ublue-os/rustdesk/RustDesk2.toml.template ] && [ ! -s "$CONF" ]; then
        cp /usr/share/ublue-os/rustdesk/RustDesk2.toml.template "$CONF"
    else
        touch "$CONF"
        if ! grep -q "direct-server" "$CONF" 2>/dev/null; then
            if grep -q "\[options\]" "$CONF" 2>/dev/null; then
                sed -i '/\[options\]/a direct-server = "Y"\nallow-ip-directing = "Y"\ndirect-access-port = "21118"\nclose-to-tray = "Y"' "$CONF"
            else
                echo -e "\n[options]\ndirect-server = \"Y\"\nallow-ip-directing = \"Y\"\ndirect-access-port = \"21118\"\nclose-to-tray = \"Y\"" >> "$CONF"
            fi
        fi
    fi
    systemctl --user daemon-reload
    systemctl --user enable --now rustdesk.service || true
    echo "✅ RustDesk installed, configured, and systemd background service activated."
    if command -v tailscale >/dev/null && tailscale status >/dev/null 2>&1; then
        DNS_NAME=$(tailscale status --self --json | jq -r '.Self.DNSName' | sed 's/\.$//')
        TS_IP=$(tailscale ip -4 2>/dev/null | head -1)
        echo "🔒 Tailnet: $DNS_NAME ($TS_IP)"
        echo "💡 Direct IP Connection: In RustDesk client on Windows, click '...' next to ID box -> 'Direct IP Access' and enter '$TS_IP:21118'."
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
# ==============================================================================

# Install/enable code-server (127.0.0.1:61337) exposed via `tailscale serve`, and stage tunnel units
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

    # Both units now ship read-only in /usr/lib/systemd/user/, so there is nothing to
    # install: `systemctl --user enable` is the whole opt-in, and the unit can never drift
    # from what the image ships. Earlier versions of this recipe copied them into $HOME
    # under `if [[ ! -f ]]`, which froze each host on whatever the image shipped the first
    # time it ran — that is how a host ended up running code-server.service from before
    # commit 7f52615 (no ProtectKernel*/LockPersonality) long after the fix was published.
    #
    # A leftover copy in $HOME does not merely linger: ~/.config/systemd/user takes
    # PRECEDENCE over /usr/lib/systemd/user, so it would keep shadowing the image unit
    # forever. Remove it, and re-enable so the *.target.wants symlink stops pointing at the
    # file that just went away.
    MIGRATED=""
    for unit in code-server.service ide-tunnel@.service; do
        if [[ -f "$UNIT_DIR/$unit" && ! -L "$UNIT_DIR/$unit" ]]; then
            rm -f "$UNIT_DIR/$unit"
            MIGRATED="yes"
            echo "Removed legacy $UNIT_DIR/$unit (now provided by the image)"
        fi
    done
    systemctl --user daemon-reload
    if [[ -n "$MIGRATED" ]]; then
        # reenable, not enable: enable leaves an existing (now dangling) symlink alone.
        systemctl --user reenable code-server.service >/dev/null 2>&1 || true
        # Enabled instances of a template are NOT listed by
        # `list-unit-files 'ide-tunnel@*.service'` — that reports only the template itself
        # ("indirect disabled"). The enabled instances exist solely as symlinks under
        # *.target.wants, so enumerate those.
        for link in "$UNIT_DIR"/*.target.wants/ide-tunnel@*.service; do
            [[ -e "$link" || -L "$link" ]] || continue
            systemctl --user reenable "$(basename "$link")" >/dev/null 2>&1 || true
        done
    fi

    # config.yaml is BOTH user secret and image policy, which is why "never overwrite" was the
    # wrong rule for it. The password is the only line this host owns; bind-addr, auth, cert and
    # the disable-telemetry/disable-update-check pair are policy from the template. Guarding the
    # whole file behind `! -f` trapped that policy: commit 7f52615 added both disable-* keys and
    # a host set up before it kept reporting telemetry indefinitely, with nothing to signal it.
    #
    # So: generate on first run, and on every later run rebuild from the template while carrying
    # the existing password across. That converges on image policy without ever regenerating a
    # working credential.
    umask 077
    if [[ ! -f "$CONF_DIR/config.yaml" ]]; then
        PASS=$(openssl rand -base64 18)
        sed "s|__GENERATE__|$PASS|" "$REF_DIR/code-server-config.yaml.tmpl" >"$CONF_DIR/config.yaml"
        chmod 600 "$CONF_DIR/config.yaml"
        echo "Generated code-server password (save it, shown once): $PASS"
    else
        PASS=$(sed -n 's/^password:[[:space:]]*//p' "$CONF_DIR/config.yaml" | head -1)
        PASS_NOTE="Password preserved."
        if [[ -z "$PASS" ]]; then
            PASS=$(openssl rand -base64 18)
            PASS_NOTE="No password was present, so a new one was generated (shown once): $PASS"
        fi
        # Staged inside $CONF_DIR, not /tmp: the file holds the password, and umask 077 above
        # only covers the mode, not who can see the path.
        RENDERED=$(mktemp -p "$CONF_DIR" .config.yaml.XXXXXX)
        sed "s|__GENERATE__|$PASS|" "$REF_DIR/code-server-config.yaml.tmpl" >"$RENDERED"
        if cmp -s "$RENDERED" "$CONF_DIR/config.yaml"; then
            rm -f "$RENDERED"
        else
            # Report the keys that changed, without printing values (one of them is the password).
            CHANGED=$(diff <(sed 's/:.*//' "$CONF_DIR/config.yaml" | sort) <(sed 's/:.*//' "$RENDERED" | sort) | grep '^>' | sed 's/^> //' | paste -sd, -)
            install -m600 "$RENDERED" "$CONF_DIR/config.yaml"
            rm -f "$RENDERED"
            echo "Reconciled $CONF_DIR/config.yaml with image policy${CHANGED:+ (added: $CHANGED)}. $PASS_NOTE"
            CONF_CHANGED="yes"
        fi
    fi

    systemctl --user enable --now code-server.service
    # enable --now does not restart an already-running unit, so a policy change would sit
    # unapplied until the next login. Written as `if`, not `[[ ... ]] && cmd`: under `set -e` the
    # latter exits the whole recipe with status 1 whenever the variable is empty.
    if [[ -n "${CONF_CHANGED:-}" ]]; then
        systemctl --user try-restart code-server.service
    fi
    # `tailscale serve` needs root unless `sudo tailscale set --operator=$USER` has been run
    # once, and it is re-asserted on every run of this recipe. Under `set -e` a permission
    # error aborted everything after this line — the tunnel env staging and the final
    # instructions never ran. Measured here: serve was already proxying 61337 from an earlier
    # root invocation, so the call was both redundant and fatal.
    # Explicit --https=61337 keeps code-server off the bare tailnet domain (443/root), which is
    # reserved so a per-project dev server can `tailscale serve` its own port.
    #
    # The inline grep this replaced looked for the proxy TARGET and ignored the listener, so on
    # a host that had already published code-server at the root it matched, reported "already
    # proxies 61337", and never migrated anything — the fix was inert exactly where it was
    # needed. /usr/libexec/bazzite-dx-serve asks `serve status --json` for the listener/target
    # pair instead, and reports a misplaced mapping rather than mistaking it for success.
    if ! /usr/libexec/bazzite-dx-serve ensure 61337; then
        echo "code-server segue de pé em 127.0.0.1:61337; falta só o proxy do tailnet."
    fi

    for name in code code-insiders antigravity; do
        if [[ ! -f "$TUNNEL_ENV_DIR/$name.env" ]]; then
            install -Dm644 "$REF_DIR/ide-tunnel-$name.env" "$TUNNEL_ENV_DIR/$name.env"
        fi
    done
    systemctl --user daemon-reload

    DNS_NAME=$(tailscale status --self --json | jq -r '.Self.DNSName' | sed 's/\.$//')
    echo ""
    echo "code-server ready at: https://$DNS_NAME"
    echo "Next: run 'ujust remote-ide-tunnel code' (or code-insiders) to log in and enable a tunnel."
    echo "If typing still feels off for your layout, prefer 'ujust remote-ide-tunnel code' — the desktop client isn't subject to browser layout detection."

# Log into GitHub and enable a VS Code family Remote Tunnel (code, code-insiders; antigravity pending upstream fix)
[group('Remote IDE')]
remote-ide-tunnel name:
    #!/usr/bin/env bash
    set -e
    NAME="{{ name }}"
    ENV_FILE="$HOME/.config/ide-tunnel/$NAME.env"

    if [[ ! -f "$ENV_FILE" ]]; then
        echo "Unknown or unstaged tunnel '$NAME'. Run 'ujust remote-ide-setup' first."
        exit 1
    fi

    if [[ "$NAME" == "antigravity" ]]; then
        echo "antigravity-ide tunnel is broken upstream (missing antigravity-tunnel binary)."
        echo "Not attempting login. Will work once the cask ships the tunnel binary."
        exit 1
    fi

    # shellcheck source=/dev/null
    source "$ENV_FILE"
    echo "Logging in to GitHub for $IDE_BINARY tunnel '$TUNNEL_NAME'..."
    "$IDE_BINARY" tunnel user login --provider github

    systemctl --user daemon-reload
    systemctl --user enable --now "ide-tunnel@$NAME.service"
    echo "Tunnel '$TUNNEL_NAME' enabled. Check 'ujust remote-ide-status' for the access URL."

# Show status of code-server and all configured IDE tunnels
[group('Remote IDE')]
remote-ide-status:
    #!/usr/bin/env bash
    echo "== code-server =="
    # `is-active` prints the state on stdout AND exits non-zero for anything but active, so
    # `|| echo inactive` printed it twice ("inactive" then "inactive"). Reproduced here before
    # the fix. Capture with `|| true` and substitute only when the output is truly empty.
    CS_STATE=$(systemctl --user is-active code-server.service 2>/dev/null || true)
    CS_ENABLED=$(systemctl --user is-enabled code-server.service 2>/dev/null || true)
    printf "%-12s %s (%s)\n" "state:" "${CS_STATE:-unknown}" "${CS_ENABLED:-unknown}"
    printf "local check: "
    curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:61337/login || echo "unreachable"
    tailscale serve status

    echo ""
    echo "== IDE Remote Tunnels =="
    for name in code code-insiders antigravity; do
        ENV_FILE="$HOME/.config/ide-tunnel/$name.env"
        [[ -f "$ENV_FILE" ]] || continue
        # Same trap as above: `|| echo inactive` would capture BOTH strings into STATE.
        STATE=$(systemctl --user is-active "ide-tunnel@$name.service" 2>/dev/null || true)
        echo "-- $name: ${STATE:-inactive}"
        journalctl --user -u "ide-tunnel@$name" --no-pager 2>/dev/null | grep -F "Open:" | tail -1
    done
