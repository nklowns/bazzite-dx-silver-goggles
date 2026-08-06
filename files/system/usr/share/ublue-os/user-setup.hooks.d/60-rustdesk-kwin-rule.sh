#!/usr/bin/env bash
# ==============================================================================
# Declarative KWin Window Rule for RustDesk: Auto-Minimize to System Tray
# Prevents RustDesk from grabbing window focus or popping up on screen.
# ==============================================================================
set -euo pipefail

KWIN_RULES="$HOME/.config/kwinrulesrc"

if [ ! -f "$KWIN_RULES" ] || ! grep -q "rustdesk-minimize" "$KWIN_RULES"; then
	mkdir -p "$HOME/.config"
	if [ ! -f "$KWIN_RULES" ]; then
		cat << 'EOF' > "$KWIN_RULES"
[General]
count=1
rules=rustdesk-minimize

[rustdesk-minimize]
Description=Start RustDesk Minimized to Tray
minimize=true
minimizerule=2
wmclass=com.rustdesk.RustDesk
wmclassmatch=1
EOF
	else
		if ! grep -q "\[rustdesk-minimize\]" "$KWIN_RULES"; then
			cat << 'EOF' >> "$KWIN_RULES"

[rustdesk-minimize]
Description=Start RustDesk Minimized to Tray
minimize=true
minimizerule=2
wmclass=com.rustdesk.RustDesk
wmclassmatch=1
EOF
		fi
	fi
	qdbus6 org.kde.KWin /KWin reconfigure 2>/dev/null || true
fi
