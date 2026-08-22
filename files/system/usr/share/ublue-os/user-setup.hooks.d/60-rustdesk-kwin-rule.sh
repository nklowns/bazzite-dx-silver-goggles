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

# Provision loginctl host shim for RustDesk Flatpak console session verification
SHIM_DIR="$HOME/.var/app/com.rustdesk.RustDesk/data/bin"
mkdir -p "$SHIM_DIR"
if [ ! -f "$SHIM_DIR/loginctl" ]; then
	cat << 'EOF' > "$SHIM_DIR/loginctl"
#!/bin/sh
exec /usr/bin/flatpak-spawn --host loginctl "$@"
EOF
	chmod +x "$SHIM_DIR/loginctl"
fi
