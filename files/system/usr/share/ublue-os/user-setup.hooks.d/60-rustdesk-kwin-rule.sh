#!/usr/bin/env bash
# ==============================================================================
# Declarative KWin Window Rules for RustDesk: Auto-Minimize to Tray & Hide from Alt+Tab
# Prevents RustDesk (all windows/sub-windows) from showing in Alt-Tab / KRunner / Taskbar.
# ==============================================================================
set -euo pipefail

KWIN_RULES="$HOME/.config/kwinrulesrc"

mkdir -p "$HOME/.config"

RULE_ID="rustdesk-hide-rule"

EXISTING_RULES=""
if [ -f "$KWIN_RULES" ]; then
	EXISTING_RULES=$(kreadconfig6 --file kwinrulesrc --group General --key rules 2>/dev/null || true)
fi

# Clean legacy IDs from General rules list
CLEAN_RULES=$(echo "$EXISTING_RULES" | tr ',' '\n' | grep -v -E '^(rustdesk-minimize|rustdesk-minimize-full|rustdesk-minimize-short|rustdesk-hide-rule)$' | paste -sd ',' - || true)

if [ -z "$CLEAN_RULES" ]; then
	FINAL_RULES="$RULE_ID"
else
	FINAL_RULES="${CLEAN_RULES},$RULE_ID"
fi

kwriteconfig6 --file kwinrulesrc --group General --key rules "$FINAL_RULES"

kwriteconfig6 --file kwinrulesrc --group "$RULE_ID" --key Description "Hide all RustDesk windows from Alt-Tab/Taskbar/KRunner to Systray"
kwriteconfig6 --file kwinrulesrc --group "$RULE_ID" --key minimize true
kwriteconfig6 --file kwinrulesrc --group "$RULE_ID" --key minimizerule 1
kwriteconfig6 --file kwinrulesrc --group "$RULE_ID" --key skiptaskbar true
kwriteconfig6 --file kwinrulesrc --group "$RULE_ID" --key skiptaskbarrule 2
kwriteconfig6 --file kwinrulesrc --group "$RULE_ID" --key skipswitcher true
kwriteconfig6 --file kwinrulesrc --group "$RULE_ID" --key skipswitcherrule 2
kwriteconfig6 --file kwinrulesrc --group "$RULE_ID" --key types 1
kwriteconfig6 --file kwinrulesrc --group "$RULE_ID" --key wmclass "rustdesk"
kwriteconfig6 --file kwinrulesrc --group "$RULE_ID" --key wmclasscomplete false
kwriteconfig6 --file kwinrulesrc --group "$RULE_ID" --key wmclassmatch 2

# Clean legacy title keys if present in rule
kwriteconfig6 --file kwinrulesrc --group "$RULE_ID" --key title --delete 2>/dev/null || true
kwriteconfig6 --file kwinrulesrc --group "$RULE_ID" --key titlematch --delete 2>/dev/null || true

# Update General count key
ALL_RULES=$(kreadconfig6 --file kwinrulesrc --group General --key rules 2>/dev/null || true)
COUNT=$(echo "$ALL_RULES" | tr ',' '\n' | grep -c -v '^$')
kwriteconfig6 --file kwinrulesrc --group General --key count "$COUNT"

# Trigger KWin configuration reload
qdbus org.kde.KWin /KWin reconfigure 2>/dev/null || true

# Provision self-contained loginctl emulator for RustDesk Flatpak session verification
# (Parses read-only /run/systemd/{sessions,seats} inside sandbox without flatpak-spawn or host escape)
SHIM_DIR="$HOME/.var/app/com.rustdesk.RustDesk/data/bin"
mkdir -p "$SHIM_DIR"
cat <<'EOF' >"$SHIM_DIR/loginctl"
#!/bin/sh
SESSION_DIR="/run/systemd/sessions"
SEAT_DIR="/run/systemd/seats"

cmd="$1"
shift 2>/dev/null || true

case "$cmd" in
    show-session)
        sess=""
        prop=""
        val_only=0
        while [ $# -gt 0 ]; do
            case "$1" in
                -p|--property) prop="$2"; shift 2 ;;
                --value) val_only=1; shift ;;
                -*) shift ;;
                *) [ -z "$sess" ] && sess="$1"; shift ;;
            esac
        done
        [ -z "$sess" ] && sess=$(ls -1 "$SESSION_DIR" 2>/dev/null | head -1)
        target="$SESSION_DIR/$sess"
        if [ ! -f "$target" ]; then
            exit 1
        fi
        if [ -n "$prop" ]; then
            uprop=$(echo "$prop" | tr '[:lower:]' '[:upper:]')
            [ "$uprop" = "NAME" ] && uprop="USER"
            val=$(grep -E "^${uprop}=" "$target" 2>/dev/null | cut -d= -f2-)
            if [ "$val_only" -eq 1 ]; then
                echo "$val"
            else
                echo "${prop}=${val}"
            fi
        else
            cat "$target"
        fi
        ;;
    list-sessions)
        echo "SESSION  UID USER  SEAT  LEADER CLASS   TTY  IDLE SINCE"
        for s in "$SESSION_DIR"/*; do
            [ -f "$s" ] || continue
            id=$(basename "$s")
            uid=$(grep '^UID=' "$s" | cut -d= -f2-)
            user=$(grep '^USER=' "$s" | cut -d= -f2-)
            seat=$(grep '^SEAT=' "$s" | cut -d= -f2-)
            class=$(grep '^CLASS=' "$s" | cut -d= -f2-)
            tty=$(grep '^TTY=' "$s" | cut -d= -f2-)
            printf "%7s %4s %-5s %-5s %6s %-7s %-4s %-4s %s\n" "$id" "$uid" "$user" "${seat:--}" "-" "$class" "${tty:--}" "no" "-"
        done
        ;;
    list-seats)
        echo "SEAT"
        for st in "$SEAT_DIR"/*; do
            [ -f "$st" ] || continue
            basename "$st"
        done
        ;;
    *)
        exit 0
        ;;
esac
EOF
chmod +x "$SHIM_DIR/loginctl"

