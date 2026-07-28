# vim: set ft=make :
# ==============================================================================
# CASTING & MOBILE BRIDGE
#
# Two discovery regimes, and the split is architectural:
#   * AirPlay (uxplay) rides on mDNS/L2. Tailscale carries no
#     multicast and the iOS AirPlay picker has no manual-IP entry, so these are
#     LAN-only. Permanently.
#   * FCast (TCP 46899), scrcpy (ADB over TCP) and KDE Connect all accept a
#     hostname typed by hand, so all three work across the tailnet.
#
# Assets are staged read-only in /usr/share/ublue-os/casting/; these recipes wire
# them into the user session. Nothing listens on the network until you ask.
# ==============================================================================

# Show the state of every casting receiver, its ports, and the tailnet address to hand to senders
[group('Casting')]
casting-status:
    #!/usr/bin/env bash
    CASTING_DIR="/usr/share/ublue-os/casting"

    echo "== Receivers (user session) =="
    # uxplay is a service: it has no window of its own worth managing and must survive the
    # session, so it is a unit and enablement is the interesting state. is-enabled behaves like
    # is-active (state on stdout, non-zero exit) and writes "not-found" for a missing unit
    # rather than going quiet.
    STATE=$(systemctl --user is-active uxplay.service 2>/dev/null || true)
    ENABLED=$(systemctl --user is-enabled uxplay.service 2>/dev/null || true)
    case "$ENABLED" in
        not-found) SUFFIX="(NOT FOUND -- image regression, expected in /usr/lib/systemd/user)" ;;
        enabled | enabled-runtime | linked | linked-runtime) SUFFIX="($ENABLED)" ;;
        *) SUFFIX="($ENABLED -- ujust airplay-setup)" ;;
    esac
    printf "%-16s %-10s %s\n" "uxplay" "${STATE:-unknown}" "$SUFFIX"

    # FCast is a windowed Flatpak app, not a service — no unit, launched from the app menu. So
    # report what actually matters: how many copies are alive. More than one is a conflict, since
    # only the first binds TCP 46899 and the others display "no network" instead (#119).
    if flatpak info org.fcast.Receiver >/dev/null 2>&1; then
        FCAST_N=$(flatpak ps --columns=application 2>/dev/null | grep -cx 'org.fcast.Receiver' || true)
        case "${FCAST_N:-0}" in
            0) printf "%-16s %-10s %s\n" "fcast (app)" "not running" "(launch from the app menu)" ;;
            1) printf "%-16s %-10s %s\n" "fcast (app)" "running" "(1 copy)" ;;
            *) printf "%-16s %-10s %s\n" "fcast (app)" "running" "$FCAST_N copies -- CONFLICT, only one can bind 46899 (ujust fcast-off)" ;;
        esac
    else
        printf "%-16s %-10s %s\n" "fcast (app)" "absent" "(ujust fcast-setup)"
    fi

    echo ""
    echo "== Discovery =="
    AVAHI=$(systemctl is-active avahi-daemon.service 2>/dev/null || true)
    printf "%-16s %s\n" "avahi-daemon" "${AVAHI:-unknown}"
    printf "%-16s %s\n" "firewall zone" "$(firewall-cmd --get-default-zone 2>/dev/null || echo unknown)"

    echo ""
    echo "== Listening ports =="
    ss -tulnp 2>/dev/null | grep -E ':(7000|7001|7100|6000|6001|7011|46898|46899|5353|1716|5555)\b' || echo "(no casting port bound)"

    echo ""
    echo "== Tailnet (hand this to FCast / scrcpy / KDE Connect senders) =="
    if command -v tailscale >/dev/null && tailscale status >/dev/null 2>&1; then
        DNS_NAME=$(tailscale status --self --json | jq -r '.Self.DNSName' | sed 's/\.$//')
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

# Enable the UxPlay AirPlay receiver (LAN-only) with pin authentication
[group('Casting')]
airplay-setup:
    #!/usr/bin/env bash
    set -e
    CASTING_DIR="/usr/share/ublue-os/casting"
    UNIT_DIR="$HOME/.config/systemd/user"
    RC_FILE="$HOME/.config/uxplayrc"

    if ! command -v uxplay >/dev/null 2>&1; then
        echo "uxplay not found. This image should ship it — check 'rpm -q uxplay'."
        exit 1
    fi

    mkdir -p "$UNIT_DIR" "$HOME/.config"

    if [[ ! -f "$RC_FILE" ]]; then
        install -Dm644 "$CASTING_DIR/uxplayrc.tmpl" "$RC_FILE"
        echo "Installed $RC_FILE (NVDEC + xvimagesink + pipewiresink, pin auth on)"
    else
        echo "Keeping existing $RC_FILE — compare against $CASTING_DIR/uxplayrc.tmpl if something misbehaves."
    fi

    # The rc file above is user config, so it is never overwritten. The unit is the opposite:
    # it holds no tunables at all (every knob lives in uxplayrc), and it now ships read-only
    # in /usr/lib/systemd/user/, so there is nothing to install and nothing that can drift.
    # A copy in $HOME would *shadow* the image unit — ~/.config/systemd/user has precedence —
    # which is exactly how this host kept running an ExecStart with no `stdbuf` wrapper after
    # the fix shipped. Delete the legacy copy and reenable so the graphical-session.target.wants
    # symlink stops pointing at the file that just went away.
    if [[ -f "$UNIT_DIR/uxplay.service" && ! -L "$UNIT_DIR/uxplay.service" ]]; then
        rm -f "$UNIT_DIR/uxplay.service"
        systemctl --user daemon-reload
        systemctl --user reenable uxplay.service >/dev/null 2>&1 || true
        echo "Removed legacy $UNIT_DIR/uxplay.service (now provided by the image)"
    fi

    systemctl --user daemon-reload
    systemctl --user enable --now uxplay.service

    echo ""
    echo "UxPlay is up as \"Silver Goggles\"."
    echo "  * LAN ONLY. AirPlay discovery is mDNS, which Tailscale does not carry, and the"
    echo "    iOS picker accepts no manual address. There is no tailnet path for this."
    echo "  * First connection from each client prints a 4-digit pin here:"
    echo "        journalctl --user -u uxplay -f"
    echo "    Authenticated clients are remembered in ~/.uxplay.register."
    echo "  * Turn it off with 'ujust airplay-off'."

# Stop and disable the UxPlay AirPlay receiver
[group('Casting')]
airplay-off:
    #!/usr/bin/env bash
    systemctl --user disable --now uxplay.service 2>/dev/null || true
    echo "UxPlay disabled. ~/.config/uxplayrc and ~/.uxplay.register are left in place."

# Install the FCast receiver flatpak (and optionally the sender), then print sender addresses
[group('Casting')]
fcast-setup with_sender="no":
    #!/usr/bin/env bash
    set -e
    UNIT_DIR="$HOME/.config/systemd/user"

    if ! command -v flatpak >/dev/null 2>&1; then
        echo "flatpak not found."
        exit 1
    fi

    if ! flatpak info org.fcast.Receiver >/dev/null 2>&1; then
        echo "Installing org.fcast.Receiver from Flathub..."
        flatpak install --user --assumeyes flathub org.fcast.Receiver
    fi

    if [[ "{{ with_sender }}" == "yes" ]] && ! flatpak info org.fcast.Sender >/dev/null 2>&1; then
        echo "Installing org.fcast.Sender from Flathub..."
        flatpak install --user --assumeyes flathub org.fcast.Sender
    fi

    # This layer used to ship an fcast-receiver.service. It is gone: a windowed Flatpak app is
    # launched by the desktop, not by systemd. Clean up after that experiment on hosts that ran
    # the older recipes, otherwise a leftover copy in $HOME (or a wants symlink from a
    # `reenable`) keeps starting the receiver at login.
    if [[ -e "$UNIT_DIR/fcast-receiver.service" ]]; then
        systemctl --user disable --now fcast-receiver.service >/dev/null 2>&1 || true
        rm -f "$UNIT_DIR/fcast-receiver.service"
        rm -f "$UNIT_DIR"/*.target.wants/fcast-receiver.service
        systemctl --user daemon-reload
        echo "Removed the old fcast-receiver.service from $UNIT_DIR (the app is launched by hand now)."
    fi

    echo ""
    echo "FCast receiver installed. Launch it when you want to receive something:"
    echo "        from the app menu, or:  flatpak run org.fcast.Receiver"
    echo "Closing its window quits it, and nothing starts it at login."
    echo ""
    echo "Point senders at:"
    if command -v tailscale >/dev/null && tailscale status >/dev/null 2>&1; then
        DNS_NAME=$(tailscale status --self --json | jq -r '.Self.DNSName' | sed 's/\.$//')
        echo "  LAN     : auto-discovered (mDNS), nothing to type"
        echo "  Tailnet : $DNS_NAME:46899   (or $(tailscale ip -4 2>/dev/null | head -1):46899)"
        echo "            added MANUALLY in the sender — mDNS does not cross the tailnet, but a"
        echo "            typed address does, and tailscale0 is already in the trusted zone."
    else
        echo "  LAN only (tailscale is not up): auto-discovered via mDNS"
    fi
    echo ""
    echo "One caveat, upstream: do not open it twice. The second copy cannot bind TCP 46899 and"
    echo "says \"Your device isn't connected to a network\" instead (futo-org/fcast#119), and"
    echo "there is no tray icon on KDE Wayland to find the first one with (#120). If a copy is"
    echo "running with no window, 'ujust fcast-off' clears it."

# Force-quit every FCast receiver copy — the rescue for a running copy with no window
[group('Casting')]
fcast-off:
    #!/usr/bin/env bash
    # No unit to stop any more; app-menu launches live in their own
    # app-flatpak-org.fcast.Receiver-*.scope, which systemd never owned. Without a tray icon on
    # KDE Wayland (upstream #120) this is the only way to reach a windowless copy still holding
    # TCP 46899 — which is what makes the NEXT launch look broken (#119).
    flatpak kill org.fcast.Receiver 2>/dev/null || true
    systemctl --user disable --now fcast-receiver.service >/dev/null 2>&1 || true
    echo "Any running FCast receiver has been killed. The flatpak stays installed."

# Pair this host with an Android device's wireless debugging (once per device)
[group('Casting')]
android-pair host port:
    #!/usr/bin/env bash
    set -e
    if ! command -v adb >/dev/null 2>&1; then
        echo "adb not found. Run 'ujust setup-personal-suite install' first."
        exit 1
    fi

    TARGET="{{ host }}"
    if command -v tailscale >/dev/null && tailscale status >/dev/null 2>&1; then
        RESOLVED=$(tailscale ip -4 "{{ host }}" 2>/dev/null | head -1 || true)
        [[ -n "$RESOLVED" ]] && { TARGET="$RESOLVED"; echo "Resolved '{{ host }}' to $TARGET"; }
    fi

    echo "On the device: Developer options -> Wireless debugging -> Pair device with pairing code."
    echo "That screen shows an address and a SIX-DIGIT code. The pairing port it shows is NOT the"
    echo "same port used for connecting afterwards -- both are random, and the pairing one only"
    echo "exists while that dialog is open."
    echo ""
    adb pair "$TARGET:{{ port }}"
    echo ""
    echo "Paired. Now bring the mirror up with:"
    echo "    ujust android-mirror {{ host }} <connect-port>"
    echo "Take <connect-port> from the main Wireless debugging screen (\"IP address & Port\")."

# Mirror an Android screen here via scrcpy — over the tailnet with a host, or over USB without
[group('Casting')]
android-mirror host="" port="":
    #!/usr/bin/env bash
    set -e
    HOST="{{ host }}"
    PORT="{{ port }}"

    for tool in adb scrcpy; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            echo "$tool not found. Install the personal suite first:"
            echo "    ujust setup-personal-suite install"
            exit 1
        fi
    done

    if [[ -z "$HOST" ]]; then
        echo "USB mode. Plug the device in, accept the debugging prompt, then this window opens."
        exec scrcpy
    fi

    TARGET="$HOST"
    if command -v tailscale >/dev/null && tailscale status >/dev/null 2>&1; then
        RESOLVED=$(tailscale ip -4 "$HOST" 2>/dev/null | head -1 || true)
        if [[ -n "$RESOLVED" ]]; then
            TARGET="$RESOLVED"
            echo "Resolved '$HOST' to tailnet address $TARGET"
        fi
    fi

    # Port handling is the whole difficulty here. Android 11+ "Wireless debugging" listens on a
    # RANDOM port that changes every time the toggle is flipped -- 5555 only applies to the older
    # `adb tcpip 5555` flow, and assuming it gets "Connection refused". adb can discover the real
    # port over mDNS (`adb mdns services` -> _adb-tls-connect._tcp), but mDNS does not cross the
    # tailnet, so a remote device's port has to be read off its screen and passed in.
    if [[ -z "$PORT" ]]; then
        echo "No port given; trying mDNS discovery (works on the LAN only)..."
        PORT=$(adb mdns services 2>/dev/null | awk '/_adb-tls-connect/ {split($3, a, ":"); print a[2]; exit}')
        if [[ -n "$PORT" ]]; then
            echo "Discovered wireless-debugging port $PORT"
        else
            PORT=5555
            echo "Nothing on mDNS; falling back to 5555 (the 'adb tcpip 5555' flow)."
        fi
    fi

    echo "Connecting ADB to $TARGET:$PORT ..."
    if ! adb connect "$TARGET:$PORT"; then
        echo ""
        echo "Connect failed. Read the error precisely, the two cases differ:"
        echo "  'Connection refused'  -> nothing listening on that port. Wireless debugging is off,"
        echo "                           or the port rotated. Re-read it on the device."
        echo "  'failed to connect'   -> the TCP connection worked but the TLS handshake did not:"
        echo "                           this host is not paired yet. Run 'ujust android-pair"
        echo "                           $HOST <pairing-port>' first."
        exit 1
    fi

    # Once connected, this makes the device listen on a STABLE 5555 until it reboots, so later
    # sessions need no port hunting -- worth doing for a device used remotely.
    echo ""
    echo "Tip: run 'adb -s $TARGET:$PORT tcpip 5555' to pin a stable port that survives toggling"
    echo "wireless debugging (but not a reboot). Then 'ujust android-mirror $HOST 5555' just works."
    echo ""
    exec scrcpy --tcpip="$TARGET:$PORT"

# Register a device with KDE Connect by tailnet address (its discovery broadcast does not cross the tailnet)
[group('Casting')]
kdeconnect-tailnet-add host:
    #!/usr/bin/env bash
    set -e
    HOST="{{ host }}"
    DEST="org.kde.kdeconnect"
    OBJ="/modules/kdeconnect"
    IFACE="org.kde.kdeconnect.daemon"

    if ! command -v gdbus >/dev/null 2>&1; then
        echo "gdbus not found (expected from glib2)."
        exit 1
    fi

    TARGET="$HOST"
    if command -v tailscale >/dev/null && tailscale status >/dev/null 2>&1; then
        RESOLVED=$(tailscale ip -4 "$HOST" 2>/dev/null | head -1 || true)
        if [[ -n "$RESOLVED" ]]; then
            TARGET="$RESOLVED"
            echo "Resolved '$HOST' to tailnet address $TARGET"
        fi
    fi

    # KDE Connect's LanLinkProvider::getBroadcastAddresses() builds each custom entry
    # with QHostAddress(QString). A hostname yields a null address, which it drops with
    # only a qCWarning -- the entry would sit in the config looking correct and do
    # nothing. Refuse anything that is not a dotted-quad IPv4 literal.
    if [[ ! "$TARGET" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
        echo "'$TARGET' is not an IPv4 literal, and KDE Connect silently ignores custom"
        echo "devices that are not. Pass a tailnet IP, or a peer hostname that"
        echo "'tailscale ip -4 <host>' can resolve."
        exit 1
    fi

    CURRENT=$(gdbus call --session --dest "$DEST" --object-path "$OBJ" \
        --method org.freedesktop.DBus.Properties.Get "$IFACE" customDevices)

    mapfile -t HOSTS < <(grep -o "'[^']*'" <<<"$CURRENT" | tr -d "'")
    for existing in "${HOSTS[@]}"; do
        if [[ "$existing" == "$TARGET" ]]; then
            echo "$TARGET is already in the KDE Connect custom device list."
            kdeconnect-cli --refresh >/dev/null 2>&1 || true
            exit 0
        fi
    done

    HOSTS+=("$TARGET")
    LIST=$(printf "'%s', " "${HOSTS[@]}")
    LIST="[${LIST%, }]"

    gdbus call --session --dest "$DEST" --object-path "$OBJ" \
        --method org.freedesktop.DBus.Properties.Set "$IFACE" customDevices "<$LIST>" >/dev/null

    echo "Added $TARGET to the KDE Connect custom device list."

    # A --refresh alone is not enough when the device has just changed networks.
    # kdeconnectd holds the previous link and keeps reporting the device reachable at
    # its old address through a socket whose peer is gone -- TCP does not notice a
    # vanished peer without traffic or keepalives, so `ss` still shows ESTAB and the
    # daemon never dials the new unicast destination. Measured here: with the phone off
    # Wi-Fi, the stale 192.168.x link stayed "reachable" until the daemon was restarted,
    # at which point the tailnet link established immediately. Restarting drops every
    # link and forces re-discovery.
    UNIT="app-org.kde.kdeconnect.daemon@autostart.service"
    if systemctl --user is-active --quiet "$UNIT" 2>/dev/null; then
        echo "Restarting kdeconnectd to drop stale links..."
        systemctl --user restart "$UNIT" || true
        sleep 5
    fi
    kdeconnect-cli --refresh >/dev/null 2>&1 || true
    echo ""
    echo "How this works, so the next step is not a mystery: a custom device is only an"
    echo "extra UNICAST destination for the UDP identity packet the desktop sends on"
    echo "refresh or network change. The phone must then dial TCP 1716 back here, so the"
    echo "app on the phone has to be awake to receive that datagram."
    echo ""
    echo "Measured on this host, same tailnet, same probe, opposite results. Android on"
    echo "cellular: TCP 1716 answered and the link established at tailnet addresses"
    echo "(100.x:1716 <- 100.x:60774 in ss). iPhone on cellular: connection REFUSED,"
    echo "meaning packets arrived and nothing was listening, while tailscale ping answered"
    echo "through the carrier. Android holds the socket via a persistent foreground"
    echo "service; iOS does not. So this is an Android feature -- for iOS file transfer,"
    echo "'tailscale file cp' (Taildrop) needs no listener on either side."
    echo ""
    echo "Note the display is misleading: kdeconnect-cli labels the link 'via LAN' even"
    echo "over the tailnet, because LanLinkProvider is the backend name, not the path."
    echo ""
    echo "Diagnosing: connection REFUSED means the app is not listening (a phone-side"
    echo "problem); a TIMEOUT means packets are not arriving (a routing or firewall one)."
    echo "    timeout 8 bash -c 'exec 3<>/dev/tcp/<phone-tailnet-ip>/1716'"
    echo ""
    echo "Open KDE Connect on the device, then:"
    echo "    kdeconnect-cli --refresh && kdeconnect-cli --list-available"
    echo "    kdeconnect-cli --pair --device <id>   # only if not already paired"

# Bind the staged firewalld service definitions to the active zones (only needed off FedoraWorkstation)
[group('Casting')]
casting-firewall:
    #!/usr/bin/env bash
    set -e
    if ! command -v firewall-cmd >/dev/null 2>&1; then
        echo "firewalld not present."
        exit 1
    fi

    ZONE=$(firewall-cmd --get-default-zone)
    echo "Default zone: $ZONE"

    if firewall-cmd --zone="$ZONE" --list-ports | grep -q '1025-65535/tcp'; then
        echo "Zone '$ZONE' already opens 1025-65535/tcp+udp — every casting port is reachable."
        echo "Nothing to do. Undo path if you add them anyway:"
        echo "    sudo firewall-cmd --permanent --zone=$ZONE --remove-service={uxplay,fcast} && sudo firewall-cmd --reload"
        exit 0
    fi

    echo "Adding the uxplay and fcast services to zone '$ZONE'..."
    sudo firewall-cmd --permanent --zone="$ZONE" --add-service=uxplay
    sudo firewall-cmd --permanent --zone="$ZONE" --add-service=fcast
    sudo firewall-cmd --reload
    echo "Done. Undo with:"
    echo "    sudo firewall-cmd --permanent --zone=$ZONE --remove-service=uxplay"
    echo "    sudo firewall-cmd --permanent --zone=$ZONE --remove-service=fcast"
    echo "    sudo firewall-cmd --reload"
