# vim: set ft=make :
# ==============================================================================
# CASTING & MOBILE BRIDGE (AirPlay/UxPlay, FCast, Android scrcpy, KDE Connect)
#
# - AirPlay (uxplay): mDNS/L2 -> LAN-only.
# - FCast (:46899), scrcpy (ADB/TCP) and KDE Connect: work over Tailnet.
# ==============================================================================

# Gerenciar Casting & Mobile Bridge. Opções: status | airplay <up|down|status|boot-on|boot-off|setup|off> | fcast <setup|off> | android <pair|mirror> | kdeconnect <host> | firewall
[group('casting')]
casting ACTION="" *ARGS:
    #!/usr/bin/env bash
    set -euo pipefail
    OPT="{{ ACTION }}"
    if [[ -z "$OPT" ]]; then
        if [[ -t 0 && -t 1 ]] && command -v ugum >/dev/null 2>&1; then
            OPT="$(ugum choose --header "Casting & Mobile Bridge:" \
                "status" "airplay" "fcast" "android" "kdeconnect" "firewall")" || exit 0
        else
            OPT="status"
        fi
    fi

    # shellcheck disable=SC2086
    set -- {{ ARGS }}

    case "$OPT" in
    status)
        CASTING_DIR="/usr/share/ublue-os/casting"
        echo "== Receivers (user session) =="
        STATE="$(systemctl --user is-active uxplay.service 2>/dev/null || true)"
        ENABLED="$(systemctl --user is-enabled uxplay.service 2>/dev/null || true)"
        case "$ENABLED" in
        not-found) SUFFIX="(NOT FOUND -- expected in /usr/lib/systemd/user)" ;;
        enabled | enabled-runtime | linked | linked-runtime) SUFFIX="($ENABLED)" ;;
        *) SUFFIX="($ENABLED -- ujust casting airplay setup)" ;;
        esac
        printf "%-16s %-10s %s\n" "uxplay" "${STATE:-unknown}" "$SUFFIX"

        if flatpak info org.fcast.Receiver >/dev/null 2>&1; then
            FCAST_N="$(flatpak ps --columns=application 2>/dev/null | grep -cx 'org.fcast.Receiver' || true)"
            case "${FCAST_N:-0}" in
            0) printf "%-16s %-10s %s\n" "fcast (app)" "not running" "(launch from the app menu)" ;;
            1) printf "%-16s %-10s %s\n" "fcast (app)" "running" "(1 copy)" ;;
            *) printf "%-16s %-10s %s\n" "fcast (app)" "running" "$FCAST_N copies -- CONFLICT (ujust casting fcast off)" ;;
            esac
        else
            printf "%-16s %-10s %s\n" "fcast (app)" "absent" "(ujust casting fcast setup)"
        fi

        echo ""
        echo "== Discovery =="
        AVAHI="$(systemctl is-active avahi-daemon.service 2>/dev/null || true)"
        printf "%-16s %s\n" "avahi-daemon" "${AVAHI:-unknown}"
        printf "%-16s %s\n" "firewall zone" "$(firewall-cmd --get-default-zone 2>/dev/null || echo unknown)"

        echo ""
        echo "== Listening ports =="
        ss -tulnp 2>/dev/null | grep -E ':(7000|7001|7100|6000|6001|7011|46898|46899|5353|1716|5555)\b' || echo "(no casting port bound)"

        echo ""
        echo "== Tailnet (FCast / scrcpy / KDE Connect) =="
        if command -v tailscale >/dev/null && tailscale status >/dev/null 2>&1; then
            DNS_NAME="$(tailscale status --self --json | jq -r '.Self.DNSName' | sed 's/\.$//')"
            echo "MagicDNS : $DNS_NAME"
            echo "IPv4     : $(tailscale ip -4 2>/dev/null | head -1)"
            echo "FCast    : $DNS_NAME:46899"
        else
            echo "tailscale not up — LAN only"
        fi

        echo ""
        echo "== KDE Connect =="
        kdeconnect-cli --list-devices 2>/dev/null || echo "kdeconnectd not reachable"
        echo ""
        echo "Config template: $CASTING_DIR/uxplayrc.tmpl -> ~/.config/uxplayrc"
        ;;
    airplay)
        sub="${1:-}"
        if [[ -z "$sub" ]]; then
            if [[ -t 0 && -t 1 ]] && command -v ugum >/dev/null 2>&1; then
                sub="$(ugum choose --header "AirPlay (UxPlay):" "status" "up" "down" "boot-on" "boot-off" "setup" "off")" || exit 0
            else
                sub="status"
            fi
        fi
        airplay_up() {
            local rc_file="$HOME/.config/uxplayrc"
            command -v uxplay >/dev/null 2>&1 || { echo "❌ uxplay não encontrado." >&2; exit 1; }
            mkdir -p "$HOME/.config"
            [[ -f "$rc_file" ]] || install -Dm644 "/usr/share/ublue-os/casting/uxplayrc.tmpl" "$rc_file"
            systemctl --user daemon-reload
            systemctl --user start uxplay.service
            echo "✅ UxPlay (AirPlay) ativo como \"Silver Goggles\"."
            echo "   PIN na primeira conexão: journalctl --user -u uxplay -f"
        }
        case "$sub" in
        up) airplay_up ;;
        down)
            systemctl --user stop uxplay.service || true
            echo "🛑 UxPlay (AirPlay) desativado."
            ;;
        status)
            STATE="$(systemctl --user is-active uxplay.service 2>/dev/null || true)"
            ENABLED="$(systemctl --user is-enabled uxplay.service 2>/dev/null || true)"
            printf "%-12s %s (boot: %s)\n" "airplay:" "${STATE:-inactive}" "${ENABLED:-disabled}"
            ;;
        boot-on | setup)
            airplay_up
            systemctl --user enable uxplay.service
            echo "⚡ UxPlay (AirPlay) habilitado no login."
            ;;
        boot-off)
            systemctl --user disable uxplay.service || true
            echo "🔌 UxPlay removido do boot."
            ;;
        off)
            systemctl --user disable --now uxplay.service || true
            echo "🛑 UxPlay parado e desabilitado."
            ;;
        *) echo "Uso: ujust casting airplay <status|up|down|boot-on|boot-off|setup|off>" >&2; exit 2 ;;
        esac
        ;;
    fcast)
        sub="${1:-setup}"
        with_sender="${2:-no}"
        case "$sub" in
        setup)
            UNIT_DIR="$HOME/.config/systemd/user"
            command -v flatpak >/dev/null 2>&1 || { echo "flatpak not found." >&2; exit 1; }
            if ! flatpak info org.fcast.Receiver >/dev/null 2>&1; then
                flatpak install --user --assumeyes flathub org.fcast.Receiver
            fi
            if [[ "$with_sender" == "yes" ]] && ! flatpak info org.fcast.Sender >/dev/null 2>&1; then
                flatpak install --user --assumeyes flathub org.fcast.Sender
            fi
            if [[ -e "$UNIT_DIR/fcast-receiver.service" ]]; then
                systemctl --user disable --now fcast-receiver.service >/dev/null 2>&1 || true
                rm -f "$UNIT_DIR/fcast-receiver.service" "$UNIT_DIR"/*.target.wants/fcast-receiver.service
                systemctl --user daemon-reload
            fi
            echo "✅ FCast receiver instalado (abra pelo menu ou 'flatpak run org.fcast.Receiver')."
            if command -v tailscale >/dev/null && tailscale status >/dev/null 2>&1; then
                DNS_NAME="$(tailscale status --self --json | jq -r '.Self.DNSName' | sed 's/\.$//')"
                echo "   Tailnet: $DNS_NAME:46899 ($(tailscale ip -4 2>/dev/null | head -1):46899)"
            fi
            ;;
        off)
            flatpak kill org.fcast.Receiver 2>/dev/null || true
            systemctl --user disable --now fcast-receiver.service >/dev/null 2>&1 || true
            echo "🛑 FCast receiver encerrado."
            ;;
        *) echo "Uso: ujust casting fcast <setup [yes]|off>" >&2; exit 2 ;;
        esac
        ;;
    android)
        sub="${1:-mirror}"
        shift || true
        case "$sub" in
        pair)
            HOST="${1:-}"; PORT="${2:-}"
            [[ -n "$HOST" && -n "$PORT" ]] || { echo "Uso: ujust casting android pair <host> <port>" >&2; exit 2; }
            command -v adb >/dev/null 2>&1 || { echo "adb not found. Run 'ujust brew install personal'." >&2; exit 1; }
            TARGET="$HOST"
            if command -v tailscale >/dev/null && tailscale status >/dev/null 2>&1; then
                RESOLVED="$(tailscale ip -4 "$HOST" 2>/dev/null | head -1 || true)"
                [[ -n "$RESOLVED" ]] && TARGET="$RESOLVED"
            fi
            adb pair "$TARGET:$PORT"
            echo "Paired. Mirror with: ujust casting android mirror $HOST <connect-port>"
            ;;
        mirror)
            HOST="${1:-}"; PORT="${2:-}"
            for tool in adb scrcpy; do
                command -v "$tool" >/dev/null 2>&1 || { echo "$tool not found. Run 'ujust brew install personal'." >&2; exit 1; }
            done
            if [[ -z "$HOST" ]]; then
                exec scrcpy
            fi
            TARGET="$HOST"
            if command -v tailscale >/dev/null && tailscale status >/dev/null 2>&1; then
                RESOLVED="$(tailscale ip -4 "$HOST" 2>/dev/null | head -1 || true)"
                [[ -n "$RESOLVED" ]] && TARGET="$RESOLVED"
            fi
            if [[ -z "$PORT" ]]; then
                PORT="$(adb mdns services 2>/dev/null | awk '/_adb-tls-connect/ {split($3, a, ":"); print a[2]; exit}')"
                PORT="${PORT:-5555}"
            fi
            adb connect "$TARGET:$PORT"
            exec scrcpy --tcpip="$TARGET:$PORT"
            ;;
        *) echo "Uso: ujust casting android <pair <host> <port>|mirror [host] [port]>" >&2; exit 2 ;;
        esac
        ;;
    kdeconnect)
        HOST="${1:-}"
        [[ -n "$HOST" ]] || { echo "Uso: ujust casting kdeconnect <host-or-ip>" >&2; exit 2; }
        command -v gdbus >/dev/null 2>&1 || { echo "gdbus not found." >&2; exit 1; }
        TARGET="$HOST"
        if command -v tailscale >/dev/null && tailscale status >/dev/null 2>&1; then
            RESOLVED="$(tailscale ip -4 "$HOST" 2>/dev/null | head -1 || true)"
            [[ -n "$RESOLVED" ]] && TARGET="$RESOLVED"
        fi
        if [[ ! "$TARGET" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
            echo "'$TARGET' is not an IPv4 literal (KDE Connect ignores hostnames)." >&2
            exit 1
        fi
        DEST="org.kde.kdeconnect"
        OBJ="/modules/kdeconnect"
        IFACE="org.kde.kdeconnect.daemon"
        CURRENT="$(gdbus call --session --dest "$DEST" --object-path "$OBJ" --method org.freedesktop.DBus.Properties.Get "$IFACE" customDevices)"
        mapfile -t HOSTS < <(grep -o "'[^']*'" <<<"$CURRENT" | tr -d "'" || true)
        for existing in "${HOSTS[@]}"; do
            if [[ "$existing" == "$TARGET" ]]; then
                echo "$TARGET já está em customDevices."
                kdeconnect-cli --refresh >/dev/null 2>&1 || true
                exit 0
            fi
        done
        HOSTS+=("$TARGET")
        LIST="$(printf "'%s', " "${HOSTS[@]}")"
        LIST="[${LIST%, }]"
        gdbus call --session --dest "$DEST" --object-path "$OBJ" \
            --method org.freedesktop.DBus.Properties.Set "$IFACE" customDevices "<$LIST>" >/dev/null
        UNIT="app-org.kde.kdeconnect.daemon@autostart.service"
        if systemctl --user is-active --quiet "$UNIT" 2>/dev/null; then
            systemctl --user restart "$UNIT" || true
            sleep 5
        fi
        kdeconnect-cli --refresh >/dev/null 2>&1 || true
        echo "✅ $TARGET adicionado ao KDE Connect."
        ;;
    firewall)
        command -v firewall-cmd >/dev/null 2>&1 || { echo "firewalld not present." >&2; exit 1; }
        ZONE="$(firewall-cmd --get-default-zone)"
        if firewall-cmd --zone="$ZONE" --list-ports | grep -q '1025-65535/tcp'; then
            echo "Zone '$ZONE' já abre 1025-65535/tcp+udp — nada a fazer."
            exit 0
        fi
        sudo firewall-cmd --permanent --zone="$ZONE" --add-service=uxplay
        sudo firewall-cmd --permanent --zone="$ZONE" --add-service=fcast
        sudo firewall-cmd --reload
        echo "✅ Serviços uxplay e fcast adicionados à zona '$ZONE'."
        ;;
    help | -h | --help)
        echo "Uso: ujust casting <status|airplay <...>|fcast <setup|off>|android <pair|mirror>|kdeconnect <host>|firewall>"
        ;;
    *)
        echo "❌ Ação desconhecida para casting: '$OPT'" >&2
        exit 2
        ;;
    esac
