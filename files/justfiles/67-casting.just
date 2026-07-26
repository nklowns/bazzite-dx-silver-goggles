# vim: set ft=make :
# ==============================================================================
# CASTING & MOBILE BRIDGE
#
# Two discovery regimes, and the split is architectural:
#   * AirPlay (uxplay, shairport-sync) rides on mDNS/L2. Tailscale carries no
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
    for unit in uxplay fcast-receiver; do
        if [[ -f "$HOME/.config/systemd/user/$unit.service" ]]; then
            printf "%-16s %s\n" "$unit" "$(systemctl --user is-active "$unit.service" 2>/dev/null || echo inactive)"
        else
            printf "%-16s %s\n" "$unit" "not installed (ujust ${unit/fcast-receiver/fcast}-setup)"
        fi
    done
    printf "%-16s %s\n" "shairport-sync" "$(systemctl is-active shairport-sync.service 2>/dev/null || echo 'inactive (system unit, AirPlay 1 only)')"

    echo ""
    echo "== Discovery =="
    printf "%-16s %s\n" "avahi-daemon" "$(systemctl is-active avahi-daemon.service 2>/dev/null || echo inactive)"
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
        echo "Installed $RC_FILE (NVDEC + waylandsink + pipewiresink, pin auth on)"
    else
        echo "Keeping existing $RC_FILE — compare against $CASTING_DIR/uxplayrc.tmpl if something misbehaves."
    fi

    if [[ ! -f "$UNIT_DIR/uxplay.service" ]]; then
        install -Dm644 "$CASTING_DIR/uxplay.service" "$UNIT_DIR/uxplay.service"
        echo "Installed uxplay.service"
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

# Install and enable the FCast receiver, then print the tailnet address for senders
[group('Casting')]
fcast-setup with_sender="no":
    #!/usr/bin/env bash
    set -e
    CASTING_DIR="/usr/share/ublue-os/casting"
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

    mkdir -p "$UNIT_DIR"
    if [[ ! -f "$UNIT_DIR/fcast-receiver.service" ]]; then
        install -Dm644 "$CASTING_DIR/fcast-receiver.service" "$UNIT_DIR/fcast-receiver.service"
        echo "Installed fcast-receiver.service"
    fi

    systemctl --user daemon-reload
    systemctl --user enable --now fcast-receiver.service

    echo ""
    echo "FCast receiver is up on TCP 46899."
    if command -v tailscale >/dev/null && tailscale status >/dev/null 2>&1; then
        DNS_NAME=$(tailscale status --self --json | jq -r '.Self.DNSName' | sed 's/\.$//')
        echo "  Tailnet: in the FCast sender app, add a receiver MANUALLY as:"
        echo "        $DNS_NAME:46899"
        echo "        (or $(tailscale ip -4 2>/dev/null | head -1):46899)"
        echo "  Auto-discovery only works on the LAN — mDNS does not cross the tailnet,"
        echo "  but the manual entry above does, and tailscale0 is already in the trusted zone."
    else
        echo "  Tailscale is not up; only LAN auto-discovery will find this receiver."
    fi
    echo "  Turn it off with 'ujust fcast-off'."

# Stop and disable the FCast receiver
[group('Casting')]
fcast-off:
    #!/usr/bin/env bash
    systemctl --user disable --now fcast-receiver.service 2>/dev/null || true
    echo "FCast receiver disabled. The flatpak itself is left installed."

# Mirror an Android screen here via scrcpy — over the tailnet with a host, or over USB without
[group('Casting')]
android-mirror host="":
    #!/usr/bin/env bash
    set -e
    HOST="{{ host }}"

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

    echo "Connecting ADB to $TARGET:5555 ..."
    if ! adb connect "$TARGET:5555"; then
        echo ""
        echo "Connect failed. On the Android device: Developer options -> Wireless debugging -> on."
        echo "First time only, pair with the 6-digit code it shows:"
        echo "    adb pair $TARGET:<pairing-port>"
        exit 1
    fi

    exec scrcpy --tcpip="$TARGET:5555"

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
    kdeconnect-cli --refresh >/dev/null 2>&1 || true
    echo ""
    echo "How this works, so the next step is not a mystery: a custom device is only an"
    echo "extra UNICAST destination for the UDP identity packet the desktop sends on"
    echo "refresh or network change. The phone must then dial TCP 1716 back here, so the"
    echo "app on the phone has to be awake to receive that datagram."
    echo ""
    echo "Measured on this host with an iPhone: on Wi-Fi, TCP 1716 on the phone's tailnet"
    echo "address answered; on cellular it returned connection REFUSED, meaning packets"
    echo "arrived and nothing was listening. The tailnet itself was fine (tailscale ping"
    echo "answered in 155ms through the carrier). Android keeps a persistent foreground"
    echo "service and holds that socket; iOS does not, so treat KDE Connect over the"
    echo "tailnet as an Android feature. For iOS file transfer, 'tailscale file cp'"
    echo "(Taildrop) works without either app listening on anything."
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
