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

# 🔒 Expose Cockpit (system admin UI, :9090) privately via tailscale serve — separate port, doesn't collide with code-server's root (443)
[group('Network')]
remote-cockpit-setup:
    #!/usr/bin/env bash
    set -e
    if ! systemctl is-active --quiet cockpit.socket 2>/dev/null; then
        echo "cockpit.socket not active. Enable first: sudo systemctl enable --now cockpit.socket"
        exit 1
    fi
    tailscale serve --bg --https=9090 9090
    DNS_NAME=$(tailscale status --self --json | jq -r '.Self.DNSName' | sed 's/\.$//')
    echo "Cockpit ready at: https://$DNS_NAME:9090"

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

    if [[ ! -f "$UNIT_DIR/code-server.service" ]]; then
        install -Dm644 "$REF_DIR/code-server.service" "$UNIT_DIR/code-server.service"
        echo "Installed code-server.service"
    fi

    if [[ ! -f "$CONF_DIR/config.yaml" ]]; then
        PASS=$(openssl rand -base64 18)
        sed "s|__GENERATE__|$PASS|" "$REF_DIR/code-server-config.yaml.tmpl" >"$CONF_DIR/config.yaml"
        chmod 600 "$CONF_DIR/config.yaml"
        echo "Generated code-server password (save it, shown once): $PASS"
    fi

    systemctl --user daemon-reload
    systemctl --user enable --now code-server.service
    tailscale serve --bg 61337

    if [[ ! -f "$UNIT_DIR/ide-tunnel@.service" ]]; then
        install -Dm644 "$REF_DIR/ide-tunnel@.service" "$UNIT_DIR/ide-tunnel@.service"
        echo "Installed ide-tunnel@.service template"
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
    systemctl --user is-active code-server.service 2>/dev/null || echo "inactive"
    printf "local check: "
    curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:61337/login || echo "unreachable"
    tailscale serve status

    echo ""
    echo "== IDE Remote Tunnels =="
    for name in code code-insiders antigravity; do
        ENV_FILE="$HOME/.config/ide-tunnel/$name.env"
        [[ -f "$ENV_FILE" ]] || continue
        STATE=$(systemctl --user is-active "ide-tunnel@$name.service" 2>/dev/null || echo "inactive")
        echo "-- $name: $STATE"
        journalctl --user -u "ide-tunnel@$name" --no-pager 2>/dev/null | grep -F "Open:" | tail -1
    done
