# vim: set ft=make :
# ==============================================================================
# Silver Goggles — Host, Remote Access, Remote IDE & Dell G15 Hardware
# ==============================================================================

# Check hardware and system health status (G15 specific)
[group('status')]
status:
    /usr/bin/g15-status

# Audit the Silver Goggles shell experience (bling infrastructure + tools)
[group('status')]
bling-check:
    /usr/bin/bling-check

# Initialize native Tailscale Tray with Systemd user integration
[group('network')]
init-tailscale-systray:
    tailscale configure systray --enable-startup=systemd
    systemctl --user daemon-reload
    systemctl --user enable --now tailscale-systray

# Gerenciar autologin + bloqueio imediato (para Sunshine sobreviver a reboot remoto). Opções: setup | teardown
[group('network')]
autologin ACTION="":
    #!/usr/bin/env bash
    set -euo pipefail
    OPT="{{ ACTION }}"
    if [[ -z "$OPT" ]]; then
        if [[ -t 0 && -t 1 ]] && command -v ugum >/dev/null 2>&1; then
            OPT="$(ugum choose --header "Autologin + lock-on-session-start:" "setup" "teardown")" || exit 0
        else
            echo "Uso: ujust autologin <setup|teardown>" >&2
            exit 2
        fi
    fi
    case "$OPT" in
    setup)
        AUTOLOGIN_USER="$(grep -oP '^\s*User=\K.*' /etc/plasmalogin.conf 2>/dev/null | tail -1 || true)"
        if [[ -z "$AUTOLOGIN_USER" ]]; then
            echo "❌ Autologin não está configurado em System Settings → Login Screen → Autologin." >&2
            exit 1
        fi
        id "$AUTOLOGIN_USER" >/dev/null 2>&1 || { echo "❌ Usuário '$AUTOLOGIN_USER' inexistente." >&2; exit 1; }
        systemctl --user enable --now lock-on-session-start.service
        echo "✅ Autologin ($AUTOLOGIN_USER) + bloqueio imediato ativos."
        ;;
    teardown)
        systemctl --user disable --now lock-on-session-start.service 2>/dev/null || true
        echo "🔓 Bloqueio automático desligado."
        AUTOLOGIN_USER="$(grep -oP '^\s*User=\K.*' /etc/plasmalogin.conf 2>/dev/null | tail -1 || true)"
        [[ -n "$AUTOLOGIN_USER" ]] && echo "⚠️  Autologin segue ativo para '$AUTOLOGIN_USER' em System Settings → Login Screen."
        ;;
    *) echo "Uso: ujust autologin <setup|teardown>" >&2; exit 2 ;;
    esac

# Gerenciar Cockpit Web Admin (:61390). Opções: status | up | down | boot-on | boot-off | remote-on | remote-off
[group('network')]
dx-cockpit ACTION="":
    #!/usr/bin/env bash
    set -euo pipefail
    OPT="{{ ACTION }}"
    if [[ -z "$OPT" ]]; then
        if [[ -t 0 && -t 1 ]] && command -v ugum >/dev/null 2>&1; then
            OPT="$(ugum choose --header "Cockpit (:61390):" "status" "up" "down" "boot-on" "boot-off" "remote-on" "remote-off")" || exit 0
        else
            OPT="status"
        fi
    fi
    case "$OPT" in
    status)
        SOCKET_STATE="$(systemctl is-active cockpit.socket 2>/dev/null || true)"
        SOCKET_ENABLED="$(systemctl is-enabled cockpit.socket 2>/dev/null || true)"
        SERVE_STATE="$(/usr/libexec/bazzite-dx-serve status 61390 61390 http 2>/dev/null || echo "absent")"
        printf "%-16s %s (boot: %s)\n" "cockpit.socket:" "${SOCKET_STATE:-inactive}" "${SOCKET_ENABLED:-disabled}"
        printf "%-16s %s\n" "tailscale serve:" "$SERVE_STATE"
        if [[ "$SOCKET_STATE" == "active" ]]; then
            DNS_NAME="$(tailscale status --self --json 2>/dev/null | jq -r '.Self.DNSName' | sed 's/\.$//' || true)"
            echo "   URL: https://${DNS_NAME:-localhost}:61390"
        fi
        ;;
    up)
        sudo systemctl start cockpit.socket
        /usr/libexec/bazzite-dx-serve ensure 61390 || true
        DNS_NAME="$(tailscale status --self --json 2>/dev/null | jq -r '.Self.DNSName' | sed 's/\.$//' || echo localhost)"
        echo "✅ Cockpit ativo em: https://$DNS_NAME:61390 (local: https://127.0.0.1:61390)"
        ;;
    down)
        sudo systemctl stop cockpit.socket cockpit.service 2>/dev/null || true
        echo "🛑 Cockpit desativado."
        ;;
    boot-on)
        sudo systemctl enable --now cockpit.socket
        echo "⚡ Cockpit habilitado no boot."
        ;;
    boot-off)
        sudo systemctl disable cockpit.socket || true
        echo "🔌 Cockpit removido do boot."
        ;;
    remote-on)
        /usr/libexec/bazzite-dx-serve ensure 61390 61390 http
        DNS_NAME="$(tailscale status --self --json 2>/dev/null | jq -r '.Self.DNSName' | sed 's/\.$//' || echo localhost)"
        echo "✅ Cockpit remoto: https://$DNS_NAME:61390"
        ;;
    remote-off)
        /usr/libexec/bazzite-dx-serve off 61390 || true
        echo "🔓 Cockpit removido do Tailscale Serve."
        ;;
    *) echo "Uso: ujust dx-cockpit <status|up|down|boot-on|boot-off|remote-on|remote-off>" >&2; exit 2 ;;
    esac

# Gerenciar Sunshine Game Streaming (:61395). Opções: status | up | down | boot-on | boot-off | remote-setup | multimon | lan-on | lan-off
[group('network')]
sunshine ACTION="":
    #!/usr/bin/env bash
    set -euo pipefail
    OPT="{{ ACTION }}"
    if [[ -z "$OPT" ]]; then
        if [[ -t 0 && -t 1 ]] && command -v ugum >/dev/null 2>&1; then
            OPT="$(ugum choose --header "Sunshine:" "status" "up" "down" "boot-on" "boot-off" "remote-setup" "multimon" "lan-on" "lan-off")" || exit 0
        else
            OPT="status"
        fi
    fi
    case "$OPT" in
    status)
        STATE="$(systemctl --user is-active sunshine.service 2>/dev/null || true)"
        ENABLED="$(systemctl --user is-enabled sunshine.service 2>/dev/null || true)"
        printf "%-12s %s (boot: %s)\n" "sunshine:" "${STATE:-inactive}" "${ENABLED:-disabled}"
        if [[ "${STATE:-inactive}" == "active" ]] && ss -tlnH 'sport = :47990' 2>/dev/null | grep -q .; then
            echo "   Web UI: https://127.0.0.1:47990"
        fi
        LOG="$HOME/.var/app/dev.lizardbyte.app.Sunshine/config/sunshine/sunshine.log"
        if [[ -f "$LOG" ]]; then
            ENC="$(grep -oE 'Found (H.264|HEVC) encoder: [a-z0-9_]+' "$LOG" | tail -2 | awk '{print $NF}' | paste -sd, - || true)"
            echo "   encoder: ${ENC:-desconhecido} (vaapi = iGPU Intel, nvenc = dGPU)"
        fi
        ;;
    up)
        if ! flatpak info dev.lizardbyte.app.Sunshine >/dev/null 2>&1; then
            flatpak install --system -y flathub dev.lizardbyte.app.Sunshine
        fi
        systemctl --user daemon-reload
        systemctl --user start sunshine.service
        /usr/libexec/bazzite-dx-sunshine-apps || true
        echo "✅ Sunshine ativo (https://127.0.0.1:47990)."
        ;;
    down)
        systemctl --user stop sunshine.service || true
        echo "🛑 Sunshine desativado."
        ;;
    boot-on)
        systemctl --user daemon-reload
        systemctl --user enable --now sunshine.service
        echo "⚡ Sunshine habilitado no login."
        ;;
    boot-off)
        systemctl --user disable sunshine.service || true
        echo "🔌 Sunshine removido do boot."
        ;;
    remote-setup)
        if ! systemctl --user is-active --quiet sunshine.service || ! ss -tlnH 'sport = :47990' 2>/dev/null | grep -q .; then
            echo "❌ Sunshine não está ativo em :47990. Rode 'ujust sunshine up' primeiro." >&2
            exit 1
        fi
        CONF_FILE="$HOME/.var/app/dev.lizardbyte.app.Sunshine/config/sunshine/sunshine.conf"
        if [[ -f "$CONF_FILE" ]] && ! grep -q 'origin_web_ui_allowed = pc' "$CONF_FILE"; then
            echo "origin_web_ui_allowed = pc" >>"$CONF_FILE"
            systemctl --user restart sunshine.service 2>/dev/null || true
        fi
        /usr/libexec/bazzite-dx-sunshine-apps
        /usr/libexec/bazzite-dx-serve ensure 61395 47990 https+insecure
        DNS_NAME="$(tailscale status --self --json | jq -r '.Self.DNSName' | sed 's/\.$//')"
        echo "✅ Sunshine Web UI: https://$DNS_NAME:61395"
        ;;
    multimon)
        /usr/libexec/bazzite-dx-sunshine-apps
        systemctl --user try-restart sunshine.service || true
        echo "✅ Apps multi-monitor provisionados no Sunshine."
        ;;
    lan-on)
        sudo firewall-cmd --add-port=47984/tcp --add-port=47989/tcp --add-port=48010/tcp \
            --add-port=47984/udp --add-port=47989/udp --add-port=48010/udp || true
        echo "✅ Portas LAN do Sunshine liberadas nesta sessão."
        ;;
    lan-off)
        sudo firewall-cmd --remove-port=47984/tcp --remove-port=47989/tcp --remove-port=48010/tcp \
            --remove-port=47984/udp --remove-port=47989/udp --remove-port=48010/udp || true
        echo "✅ Portas LAN do Sunshine fechadas."
        ;;
    *) echo "Uso: ujust sunshine <status|up|down|boot-on|boot-off|remote-setup|multimon|lan-on|lan-off>" >&2; exit 2 ;;
    esac

# Gerenciar receptor de webcam e microfone remoto (MediaMTX + webcam-receiver). Opções: status | up | down | boot-on | boot-off | setup [win_ip]
[group('network')]
webcam ACTION="" *ARGS:
    #!/usr/bin/env bash
    set -euo pipefail
    OPT="{{ ACTION }}"
    if [[ -z "$OPT" ]]; then
        if [[ -t 0 && -t 1 ]] && command -v ugum >/dev/null 2>&1; then
            OPT="$(ugum choose --header "Webcam & Mic remoto:" "status" "up" "down" "boot-on" "boot-off" "setup")" || exit 0
        else
            OPT="status"
        fi
    fi
    # shellcheck disable=SC2086
    set -- {{ ARGS }}
    case "$OPT" in
    status)
        echo "== MediaMTX =="
        systemctl --user status mediamtx.service --no-pager -n 3 2>/dev/null || echo "mediamtx inativo"
        echo ""
        echo "== Webcam Receiver =="
        systemctl --user status webcam-receiver.service --no-pager -n 3 2>/dev/null || echo "webcam-receiver inativo"
        echo ""
        ls -l /dev/video10 /dev/video9 2>/dev/null || echo "Nenhum nó V4L2 loopback"
        pactl list sources short 2>/dev/null | grep -E "Mic_Virtual|OBS_Virtual" || echo "Nenhum microfone virtual ativo"
        ;;
    up)
        systemctl --user daemon-reload
        systemctl --user start mediamtx.service webcam-receiver.service
        echo "✅ Webcam (/dev/video10) e Mic-Virtual-1 ativos (rtsp://127.0.0.1:8554/webcam)."
        ;;
    down)
        systemctl --user stop webcam-receiver.service mediamtx.service || true
        echo "🛑 Webcam e Mic remoto desativados."
        ;;
    boot-on)
        systemctl --user enable mediamtx.service webcam-receiver.service
        echo "⚡ Webcam remota habilitada no boot."
        ;;
    boot-off)
        systemctl --user disable webcam-receiver.service mediamtx.service || true
        echo "🔌 Webcam remota removida do boot."
        ;;
    setup)
        WIN_IP="${1:-${DEFAULT_WEBCAM_IP:-127.0.0.1}}"
        systemctl --user start mediamtx.service 2>/dev/null || true
        BIN="/usr/bin/webcam-receiver"
        [[ -x "$BIN" ]] || BIN="./files/system/usr/bin/webcam-receiver"
        "$BIN" "$WIN_IP"
        ;;
    *) echo "Uso: ujust webcam <status|up|down|boot-on|boot-off|setup [win_ip]>" >&2; exit 2 ;;
    esac

# Gerenciar RustDesk (acesso remoto). Opções: status | up | down | boot-on | boot-off
[group('network')]
rustdesk ACTION="":
    #!/usr/bin/env bash
    set -euo pipefail
    OPT="{{ ACTION }}"
    if [[ -z "$OPT" ]]; then
        if [[ -t 0 && -t 1 ]] && command -v ugum >/dev/null 2>&1; then
            OPT="$(ugum choose --header "RustDesk:" "status" "up" "down" "boot-on" "boot-off")" || exit 0
        else
            OPT="status"
        fi
    fi
    case "$OPT" in
    status)
        STATE="$(systemctl --user is-active rustdesk.service 2>/dev/null || true)"
        ENABLED="$(systemctl --user is-enabled rustdesk.service 2>/dev/null || true)"
        printf "%-12s %s (boot: %s)\n" "rustdesk:" "${STATE:-inactive}" "${ENABLED:-disabled}"
        ;;
    up)
        if ! flatpak info com.rustdesk.RustDesk >/dev/null 2>&1; then
            flatpak install -y com.rustdesk.RustDesk 2>/dev/null || flatpak install --user -y com.rustdesk.RustDesk 2>/dev/null || true
        fi
        mkdir -p "$HOME/.config/autostart"
        ln -sf /dev/null "$HOME/.config/autostart/com.rustdesk.RustDesk.desktop" 2>/dev/null || true
        CONF="$HOME/.var/app/com.rustdesk.RustDesk/config/rustdesk/RustDesk2.toml"
        mkdir -p "$(dirname "$CONF")"
        if [[ -f /usr/share/ublue-os/rustdesk/RustDesk2.toml.template && ! -s "$CONF" ]]; then
            cp /usr/share/ublue-os/rustdesk/RustDesk2.toml.template "$CONF"
        fi
        systemctl --user daemon-reload
        systemctl --user start rustdesk.service
        echo "✅ RustDesk ativo."
        if command -v tailscale >/dev/null && tailscale status >/dev/null 2>&1; then
            TS_IP="$(tailscale ip -4 2>/dev/null | head -1)"
            echo "💡 Direct IP: ${TS_IP}:21118"
        fi
        ;;
    down)
        systemctl --user stop rustdesk.service || true
        echo "🛑 RustDesk desativado."
        ;;
    boot-on)
        ujust rustdesk up
        systemctl --user enable rustdesk.service
        echo "⚡ RustDesk habilitado no login."
        ;;
    boot-off)
        systemctl --user disable rustdesk.service || true
        echo "🔌 RustDesk removido do boot."
        ;;
    *) echo "Uso: ujust rustdesk <status|up|down|boot-on|boot-off>" >&2; exit 2 ;;
    esac

# Gerenciar Apache Guacamole (:61392). Opções: status | up | down
[group('network')]
guacamole ACTION="":
    #!/usr/bin/env bash
    set -euo pipefail
    OPT="{{ ACTION }}"
    if [[ -z "$OPT" ]]; then
        if [[ -t 0 && -t 1 ]] && command -v ugum >/dev/null 2>&1; then
            OPT="$(ugum choose --header "Guacamole (:61392):" "status" "up" "down")" || exit 0
        else
            OPT="status"
        fi
    fi
    case "$OPT" in
    status)
        podman ps --filter name=guacamole-desktop --format 'table {{{{.Names}}}}\t{{{{.Status}}}}\t{{{{.Ports}}}}' 2>/dev/null || true
        ;;
    up)
        if ! ss -tlnH 'src 127.0.0.1 sport = :61392' 2>/dev/null | grep -q .; then
            podman run -d --name guacamole-desktop \
                --restart=unless-stopped \
                -p 127.0.0.1:61392:8080 \
                -e OPT_MYSQL=false \
                docker.io/jwetzell/guacamole:latest 2>/dev/null || podman start guacamole-desktop 2>/dev/null || true
        fi
        /usr/libexec/bazzite-dx-serve ensure 61392 61392 http || true
        DNS_NAME="$(tailscale status --self --json 2>/dev/null | jq -r '.Self.DNSName' | sed 's/\.$//' || echo localhost)"
        echo "✅ Guacamole: https://$DNS_NAME:61392"
        ;;
    down)
        podman stop guacamole-desktop 2>/dev/null || true
        echo "🛑 Guacamole desativado."
        ;;
    *) echo "Uso: ujust guacamole <status|up|down>" >&2; exit 2 ;;
    esac

# Check Wake-on-LAN (WoL) and background idle inhibitor status
[group('network')]
wol-status:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "== Wake-on-LAN (WoL) =="
    nmcli c show "Wired connection 1" 2>/dev/null | grep -i wake-on-lan || echo "Wired connection 1 not configured"
    nmcli c show "PRX-SEM.NUVEM-5G" 2>/dev/null | grep -i wake-on-wlan || echo "Wi-Fi WoL default"
    echo ""
    echo "== Background Idle Inhibitor =="
    for p in /usr/bin/smart-idle-checker /usr/local/bin/smart-idle-checker ./files/system/usr/bin/smart-idle-checker; do
        if [[ -x "$p" ]]; then "$p" || true; break; fi
    done

# Setup Deskflow (Software KVM over Tailscale)
[group('network')]
remote-deskflow-setup:
    #!/usr/bin/env bash
    set -euo pipefail
    flatpak install --user -y flathub com.deskflow.deskflow || true
    if command -v tailscale >/dev/null && tailscale status >/dev/null 2>&1; then
        DNS_NAME="$(tailscale status --self --json | jq -r '.Self.DNSName' | sed 's/\.$//')"
        TS_IP="$(tailscale ip -4 2>/dev/null | head -1)"
        echo "✅ Deskflow pronto. Tailnet: $DNS_NAME:24800 ($TS_IP:24800)"
    fi

# Master Status & Manager for Remote Access Suite
[group('network')]
remote-suite action="status":
    #!/usr/bin/env bash
    set -euo pipefail
    if [[ -x /usr/bin/remote-suite ]]; then
        /usr/bin/remote-suite "{{ action }}"
    elif [[ -x ./files/system/usr/bin/remote-suite ]]; then
        ./files/system/usr/bin/remote-suite "{{ action }}"
    else
        echo "❌ /usr/bin/remote-suite not found" >&2
        exit 1
    fi

# Gerenciar Remote IDE (code-server :61337 + VS Code Remote Tunnels). Opções: status | up | down | password [new] | boot-on | boot-off | setup | tunnel <up|down|boot-on|boot-off|auth> [name]
[group('remote-ide')]
code ACTION="" *ARGS:
    #!/usr/bin/env bash
    set -euo pipefail
    OPT="{{ ACTION }}"
    if [[ -z "$OPT" ]]; then
        if [[ -t 0 && -t 1 ]] && command -v ugum >/dev/null 2>&1; then
            OPT="$(ugum choose --header "Remote IDE (code-server & tunnels):" \
                "status" "up" "down" "password" "boot-on" "boot-off" "setup" "tunnel")" || exit 0
        else
            OPT="status"
        fi
    fi
    # shellcheck disable=SC2086
    set -- {{ ARGS }}
    REF_DIR="/usr/share/ublue-os/remote-ide"
    CONF_DIR="$HOME/.config/code-server"
    TUNNEL_ENV_DIR="$HOME/.config/ide-tunnel"

    case "$OPT" in
    status)
        echo "=== 🌐 CODE-SERVER ==="
        CS_STATE="$(systemctl --user is-active code-server.service 2>/dev/null || true)"
        CS_ENABLED="$(systemctl --user is-enabled code-server.service 2>/dev/null || true)"
        printf "%-12s %s (boot: %s)\n" "status:" "${CS_STATE:-inactive}" "${CS_ENABLED:-disabled}"
        if [[ "$CS_STATE" == "active" ]]; then
            DNS_NAME="$(tailscale status --self --json 2>/dev/null | jq -r '.Self.DNSName' | sed 's/\.$//' || true)"
            echo "url:         https://${DNS_NAME:-localhost}:61337"
            PASS="$(sed -n 's/^password:[[:space:]]*//p' "$CONF_DIR/config.yaml" 2>/dev/null || echo '(ausente)')"
            echo "senha:       $PASS"
        fi
        echo ""
        echo "=== 🚇 VS CODE REMOTE TUNNELS ==="
        for name in code code-insiders antigravity; do
            [[ -f "$TUNNEL_ENV_DIR/$name.env" ]] || continue
            ST="$(systemctl --user is-active "ide-tunnel@$name.service" 2>/dev/null || true)"
            EN="$(systemctl --user is-enabled "ide-tunnel@$name.service" 2>/dev/null || true)"
            printf "%-15s %s (boot: %s)\n" "$name:" "${ST:-inactive}" "${EN:-disabled}"
            if [[ "$ST" == "active" ]]; then
                URL="$(journalctl --user -u "ide-tunnel@$name" --no-pager 2>/dev/null | grep -F "Open:" | tail -1 | sed 's/.*Open:[[:space:]]*//' || true)"
                [[ -n "$URL" ]] && echo "   🔗 $URL"
            fi
        done
        ;;
    up)
        command -v code-server >/dev/null 2>&1 || { echo "❌ code-server não encontrado. Rode 'ujust brew install personal'." >&2; exit 1; }
        mkdir -p "$CONF_DIR"
        umask 077
        if [[ ! -f "$CONF_DIR/config.yaml" ]]; then
            PASS="$(openssl rand -base64 18)"
            sed "s|__GENERATE__|$PASS|" "$REF_DIR/code-server-config.yaml.tmpl" >"$CONF_DIR/config.yaml"
            chmod 600 "$CONF_DIR/config.yaml"
            echo "🔑 Senha gerada: $PASS"
        fi
        systemctl --user daemon-reload
        systemctl --user start code-server.service
        if /usr/libexec/bazzite-dx-serve ensure 61337; then
            DNS_NAME="$(tailscale status --self --json 2>/dev/null | jq -r '.Self.DNSName' | sed 's/\.$//')"
            echo "✅ code-server: https://$DNS_NAME:61337 (local: http://127.0.0.1:61337)"
        else
            echo "✅ code-server: http://127.0.0.1:61337"
        fi
        ;;
    down)
        systemctl --user stop code-server.service || true
        echo "🛑 code-server desativado."
        ;;
    password)
        NEW_PASS="${1:-}"
        CONF_FILE="$CONF_DIR/config.yaml"
        [[ -f "$CONF_FILE" ]] || { echo "❌ $CONF_FILE ausente. Rode 'ujust code up' primeiro." >&2; exit 1; }
        if [[ -n "$NEW_PASS" ]]; then
            sed -i "s/^password:.*/password: $NEW_PASS/" "$CONF_FILE"
            chmod 600 "$CONF_FILE"
            systemctl --user try-restart code-server.service || true
            echo "✅ Senha atualizada."
        else
            echo "🔑 Senha atual: $(sed -n 's/^password:[[:space:]]*//p' "$CONF_FILE" | head -1)"
        fi
        ;;
    boot-on)
        ujust code up
        systemctl --user enable code-server.service
        echo "⚡ code-server habilitado no boot."
        ;;
    boot-off)
        systemctl --user disable code-server.service || true
        echo "🔌 code-server removido do boot."
        ;;
    setup)
        command -v code-server >/dev/null 2>&1 || { echo "❌ code-server não encontrado." >&2; exit 1; }
        UNIT_DIR="$HOME/.config/systemd/user"
        mkdir -p "$UNIT_DIR" "$CONF_DIR" "$TUNNEL_ENV_DIR"
        for unit in code-server.service ide-tunnel@.service; do
            [[ -f "$UNIT_DIR/$unit" && ! -L "$UNIT_DIR/$unit" ]] && rm -f "$UNIT_DIR/$unit"
        done
        umask 077
        if [[ ! -f "$CONF_DIR/config.yaml" ]]; then
            PASS="$(openssl rand -base64 18)"
            sed "s|__GENERATE__|$PASS|" "$REF_DIR/code-server-config.yaml.tmpl" >"$CONF_DIR/config.yaml"
            chmod 600 "$CONF_DIR/config.yaml"
            echo "🔑 Senha gerada: $PASS"
        fi
        for name in code code-insiders antigravity; do
            [[ ! -f "$TUNNEL_ENV_DIR/$name.env" && -f "$REF_DIR/ide-tunnel-$name.env" ]] && \
                install -Dm644 "$REF_DIR/ide-tunnel-$name.env" "$TUNNEL_ENV_DIR/$name.env"
        done
        systemctl --user daemon-reload
        echo "✅ Ambiente Remote IDE pronto. Inicie com: ujust code up"
        ;;
    tunnel)
        sub="${1:-up}"
        NAME="${2:-code-insiders}"
        ENV_FILE="$TUNNEL_ENV_DIR/$NAME.env"
        [[ "$NAME" == "antigravity" ]] && { echo "❌ antigravity tunnel indisponível upstream." >&2; exit 1; }
        mkdir -p "$TUNNEL_ENV_DIR"
        [[ ! -f "$ENV_FILE" && -f "$REF_DIR/ide-tunnel-$NAME.env" ]] && install -Dm644 "$REF_DIR/ide-tunnel-$NAME.env" "$ENV_FILE"
        case "$sub" in
        up)
            [[ -f "$ENV_FILE" ]] || { echo "❌ Túnel '$NAME' não encontrado." >&2; exit 1; }
            systemctl --user daemon-reload
            systemctl --user start "ide-tunnel@$NAME.service"
            echo "✅ Túnel '$NAME' iniciado."
            ;;
        down)
            systemctl --user stop "ide-tunnel@$NAME.service" || true
            echo "🛑 Túnel '$NAME' parado."
            ;;
        boot-on)
            ujust code tunnel up "$NAME"
            systemctl --user enable "ide-tunnel@$NAME.service"
            echo "⚡ Túnel '$NAME' habilitado no boot."
            ;;
        boot-off)
            systemctl --user disable "ide-tunnel@$NAME.service" || true
            echo "🔌 Túnel '$NAME' removido do boot."
            ;;
        auth)
            [[ -f "$ENV_FILE" ]] || { echo "❌ Túnel '$NAME' não encontrado." >&2; exit 1; }
            # shellcheck source=/dev/null
            source "$ENV_FILE"
            "$IDE_BINARY" tunnel user login --provider github
            systemctl --user daemon-reload
            systemctl --user start "ide-tunnel@$NAME.service"
            ;;
        *) echo "Uso: ujust code tunnel <up|down|boot-on|boot-off|auth> [code|code-insiders]" >&2; exit 2 ;;
        esac
        ;;
    *) echo "Uso: ujust code <status|up|down|password|boot-on|boot-off|setup|tunnel>" >&2; exit 2 ;;
    esac

# Show or switch Dell G15 chassis power profile (no root needed)
[group('hardware')]
g15-profile profile="":
    #!/usr/bin/env bash
    set -uo pipefail
    PROV=/sys/class/platform-profile/platform-profile-0
    PPD=(--system net.hadess.PowerProfiles /net/hadess/PowerProfiles net.hadess.PowerProfiles ActiveProfile)
    HW="$(for d in /sys/class/hwmon/hwmon*; do [[ "$(cat "$d/name" 2>/dev/null)" == alienware_wmi ]] && echo "$d"; done)"
    [[ -d "$PROV" ]] || { echo "No platform-profile provider at $PROV." >&2; exit 1; }

    if [[ -z "{{ profile }}" ]]; then
        printf "%-14s %s\n" "active:" "$(busctl get-property "${PPD[@]}" 2>/dev/null | sed 's/^s "//; s/"$//')"
        printf "%-14s %s\n" "sysfs:" "$(cat "$PROV/profile")"
        printf "%-14s %s\n" "choices:" "$(cat "$PROV/choices")"
        if [[ -n "$HW" ]]; then
            printf "%-14s %s/%s (fans %s/%s rpm, max %s)\n" "fan boost:" \
                "$(cat "$HW/fan1_boost")" "$(cat "$HW/fan2_boost")" \
                "$(cat "$HW/fan1_input")" "$(cat "$HW/fan2_input")" "$(cat "$HW/fan1_max")"
        fi
        exit 0
    fi
    grep -qw -- "{{ profile }}" "$PROV/choices" || { echo "Unknown profile '{{ profile }}'." >&2; exit 1; }
    busctl set-property "${PPD[@]}" s "{{ profile }}"
    sleep 2
    printf "profile=%s\n" "$(cat "$PROV/profile")"

# Toggle laptop's built-in keyboard (enable/disable/toggle/status)
[group('hardware')]
toggle-keyboard state="toggle":
    #!/usr/bin/env bash
    set -euo pipefail
    CMD="/usr/bin/udev-keyboard-handler"
    [[ -x "$CMD" ]] || CMD="/usr/local/bin/udev-keyboard-handler"
    [[ -x "$CMD" ]] || { echo "udev-keyboard-handler not found." >&2; exit 1; }
    "$CMD" "{{ state }}"

# Diagnóstico da GPU ativa no KDE Plasma e consumo de VRAM
[group('hardware')]
gpu-status:
    #!/usr/bin/env bash
    set -uo pipefail
    echo "=== GPU & Desktop (KDE Wayland) ==="
    qdbus-qt6 --literal org.kde.KWin /KWin supportInformation 2>/dev/null | grep -E "OpenGL renderer string|Driver version" || echo "  (KWin via D-Bus indisponível)"
    echo ""
    if command -v nvidia-smi >/dev/null 2>&1; then
        nvidia-smi --query-gpu=memory.total,memory.used,memory.free --format=csv,noheader 2>/dev/null | sed 's/^/VRAM (RTX 3060): /' || true
    fi
    if [[ -f /sys/class/drm/card0-HDMI-A-1/status ]] && grep -q "^connected" /sys/class/drm/card0-HDMI-A-1/status 2>/dev/null; then
        echo "Monitor: HDMI na NVIDIA (card0) — ~5.3 GB VRAM livre"
    elif grep -q "^connected" /sys/class/drm/card1-DP-*/status 2>/dev/null; then
        echo "Monitor: DisplayPort USB-C na Intel (card1) — ~6.0 GB VRAM livre"
    else
        echo "Monitor: Tela interna na Intel (card1) — ~6.0 GB VRAM livre"
    fi

# Enroll the silver-goggles kmod signing key into the MOK
[group('hardware')]
enroll-silver-goggles-key:
    #!/usr/bin/env bash
    set -euo pipefail
    KEY=/etc/pki/silver-goggles/kmod.der
    if sudo mokutil --test-key "$KEY" 2>&1 | grep -q 'is already enrolled'; then
        echo "Key already enrolled: nothing to do."
        exit 0
    fi
    sudo mokutil --import "$KEY"
    echo 'Reboot -> MokManager -> "Enroll MOK" -> Continue -> password.'

# Gerenciar gpu-unlock (FP16/BF16 tensor-core rate, RTX 3060). Opções: status | setup [fw_dir] [pci] | remove
[group('hardware')]
gpu-unlock ACTION="" *ARGS:
    #!/usr/bin/env bash
    set -euo pipefail
    OPT="{{ ACTION }}"
    if [[ -z "$OPT" ]]; then
        if [[ -t 0 && -t 1 ]] && command -v ugum >/dev/null 2>&1; then
            OPT="$(ugum choose --header "gpu-unlock:" "status" "setup" "remove")" || exit 0
        else
            OPT="status"
        fi
    fi
    # shellcheck disable=SC2086
    set -- {{ ARGS }}
    case "$OPT" in
    status)
        echo "--- karg ---"; grep -o 'gpu_unlock[^ ]*' /proc/cmdline || echo "  not set"
        echo "--- module ---"; lsmod | grep -E '^gpu_unlock' || echo "  not loaded"
        echo "--- key ---"; mokutil --test-key /etc/pki/silver-goggles/kmod.der 2>&1 | tail -1
        echo "--- image kmod ---"; ls "/usr/lib/modules/$(uname -r)/extra/gpu_unlock.ko" 2>&1 | tail -1
        echo "--- firmware ---"; ls /etc/gpu-unlock/fw/gpu-unlock/610.43.03 2>/dev/null | wc -l | sed 's/$/ of 5 files/'
        echo "--- initramfs-etc ---"; rpm-ostree status | grep -m1 InitramfsEtc || echo "  not tracked"
        echo "--- kernel log ---"; journalctl -k -b --no-pager | grep -i gpu_unlock | tail -20 || echo "  no entries"
        ;;
    setup)
        fw_dir="${1:-$HOME/.cache/gpu-unlock/assets}"
        pci="${2:-0000:01:00.0}"
        KVER="$(uname -r)"
        [[ -f "/usr/lib/modules/$KVER/extra/gpu_unlock.ko" ]] || { echo "No gpu_unlock.ko for $KVER." >&2; exit 1; }
        mokutil --test-key /etc/pki/silver-goggles/kmod.der 2>&1 | grep -q 'is already enrolled' || {
            echo "Key not enrolled: run 'ujust enroll-silver-goggles-key' and reboot first." >&2
            exit 1
        }
        MANIFEST=/usr/share/silver-goggles/gpu-unlock-fw.sha256
        (cd "$fw_dir" && sha256sum --check --strict "$MANIFEST")
        FW=/etc/gpu-unlock/fw/gpu-unlock/610.43.03
        sudo install -d -m 755 "$FW"
        while read -r _ name; do sudo install -m 644 "$fw_dir/$name" "$FW/"; done <"$MANIFEST"
        sudo rpm-ostree initramfs --disable 2>/dev/null || true
        sudo rpm-ostree initramfs-etc --track=/etc/gpu-unlock
        sudo rpm-ostree kargs --append-if-missing="firmware_class.path=/etc/gpu-unlock/fw" --append-if-missing="gpu_unlock.targets=$pci"
        echo "Staged. Poweroff (cold boot) and power on. Rollback: ujust gpu-unlock remove"
        ;;
    remove)
        for karg in $(rpm-ostree kargs | tr ' ' '\n' | grep -E '^(gpu_unlock\.targets|firmware_class\.path)='); do
            sudo rpm-ostree kargs --delete="$karg"
        done
        sudo rpm-ostree initramfs-etc --untrack=/etc/gpu-unlock || true
        sudo rm -rf /etc/gpu-unlock
        echo "Done. Takes effect after next boot."
        ;;
    *) echo "Uso: ujust gpu-unlock <status|setup [fw_dir] [pci]|remove>" >&2; exit 2 ;;
    esac
