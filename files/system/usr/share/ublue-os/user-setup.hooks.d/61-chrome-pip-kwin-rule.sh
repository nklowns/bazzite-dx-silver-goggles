#!/usr/bin/env bash
# ==============================================================================
# Declarative KWin Window Rules for Chrome/Chromium Picture-in-Picture
# Ensures PiP windows stay always on top, on all virtual desktops, and out of Alt-Tab/Taskbar.
# ==============================================================================
set -euo pipefail

if [ -f /run/.containerenv ] || [ -f /.dockerenv ]; then
	exit 0
fi

if ! command -v kwriteconfig6 >/dev/null 2>&1; then
	exit 0
fi

KWIN_RULES="$HOME/.config/kwinrulesrc"
mkdir -p "$HOME/.config"

RULE_ID="chrome-pip-rule"

EXISTING_RULES=""
if [ -f "$KWIN_RULES" ]; then
	EXISTING_RULES=$(kreadconfig6 --file kwinrulesrc --group General --key rules 2>/dev/null || true)
fi

CLEAN_RULES=$(echo "$EXISTING_RULES" | tr ',' '\n' | grep -v -E "^${RULE_ID}$" | grep -v '^$' | paste -sd ',' - || true)

if [ -z "$CLEAN_RULES" ]; then
	FINAL_RULES="$RULE_ID"
else
	FINAL_RULES="${CLEAN_RULES},$RULE_ID"
fi

kwriteconfig6 --file kwinrulesrc --group General --key rules "$FINAL_RULES"

# Rule properties
kwriteconfig6 --file kwinrulesrc --group "$RULE_ID" --key Description "Chrome Picture-in-Picture"
kwriteconfig6 --file kwinrulesrc --group "$RULE_ID" --key title "Picture.*picture"
kwriteconfig6 --file kwinrulesrc --group "$RULE_ID" --key titlematch 3
kwriteconfig6 --file kwinrulesrc --group "$RULE_ID" --key wmclassmatch 0
kwriteconfig6 --file kwinrulesrc --group "$RULE_ID" --key types 1
kwriteconfig6 --file kwinrulesrc --group "$RULE_ID" --key above true
kwriteconfig6 --file kwinrulesrc --group "$RULE_ID" --key aboverule 2

# KWin Virtual Desktops syntax: desktop=-1 (All Desktops) and desktops= (KDE Plasma 6)
kwriteconfig6 --file kwinrulesrc --group "$RULE_ID" --key desktop -- -1
kwriteconfig6 --file kwinrulesrc --group "$RULE_ID" --key desktoprule 2
kwriteconfig6 --file kwinrulesrc --group "$RULE_ID" --key desktops ""
kwriteconfig6 --file kwinrulesrc --group "$RULE_ID" --key desktopsrule 2

# Clean legacy non-existent keys
kwriteconfig6 --file kwinrulesrc --group "$RULE_ID" --key alldesktops --delete 2>/dev/null || true
kwriteconfig6 --file kwinrulesrc --group "$RULE_ID" --key alldesktopsrule --delete 2>/dev/null || true

kwriteconfig6 --file kwinrulesrc --group "$RULE_ID" --key skipswitcher true
kwriteconfig6 --file kwinrulesrc --group "$RULE_ID" --key skipswitcherrule 2
kwriteconfig6 --file kwinrulesrc --group "$RULE_ID" --key skiptaskbar true
kwriteconfig6 --file kwinrulesrc --group "$RULE_ID" --key skiptaskbarrule 2

# Update rule count
ALL_RULES=$(kreadconfig6 --file kwinrulesrc --group General --key rules 2>/dev/null || true)
COUNT=$(echo "$ALL_RULES" | tr ',' '\n' | grep -c -v '^$' || true)
kwriteconfig6 --file kwinrulesrc --group General --key count "$COUNT"

# Reload KWin rules
qdbus org.kde.KWin /KWin reconfigure 2>/dev/null || qdbus-qt6 org.kde.KWin /KWin reconfigure 2>/dev/null || true
