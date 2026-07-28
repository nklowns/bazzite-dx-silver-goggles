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
    # Same permission trap as remote-ide-setup: serve needs root unless --operator is set, and
    # re-asserting it on every run turned a redundant call into a fatal one under `set -e`.
    if tailscale serve status 2>/dev/null | grep -q 'proxy http://127.0.0.1:9090'; then
        echo "tailscale serve already proxies 9090 — left as is."
    elif ! tailscale serve --bg --https=9090 9090 2>/dev/null; then
        echo "Could not configure 'tailscale serve' (it needs root here). Run either:"
        echo "    sudo tailscale serve --bg --https=9090 9090"
        echo "    sudo tailscale set --operator=$USER   # once, then this recipe can do it"
        exit 1
    fi
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
    if tailscale serve status 2>/dev/null | grep -q 'proxy http://127.0.0.1:61337'; then
        echo "tailscale serve already proxies 61337 — left as is."
    elif ! tailscale serve --bg 61337 2>/dev/null; then
        echo "Could not configure 'tailscale serve' (it needs root here). Run either:"
        echo "    sudo tailscale serve --bg 61337"
        echo "    sudo tailscale set --operator=$USER   # once, then this recipe can do it"
        echo "code-server is still up on 127.0.0.1:61337; only the tailnet proxy is missing."
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
