#!/usr/bin/bash
set -ouex pipefail

# shellcheck source=/dev/null
source /usr/lib/ublue/setup-services/libsetup.sh

version-script vt-switch-guard user 1 || exit 0

# Shift VT switching shortcuts away from Ctrl+Alt+F1..F4 (disabling F1..F4, enabling F5..F6)
# to prevent accidental TTY switching during gaming/streaming.
if command -v kwriteconfig6 >/dev/null 2>&1; then
	for i in {1..4}; do
		kwriteconfig6 --file kglobalshortcutsrc --group kwin --key "Switch to Virtual Terminal $i" "none,none,Switch to Virtual Terminal $i" || true
	done
	kwriteconfig6 --file kglobalshortcutsrc --group kwin --key "Switch to Virtual Terminal 5" "Ctrl+Alt+F5,Ctrl+Alt+F5,Switch to Virtual Terminal 5" || true
	kwriteconfig6 --file kglobalshortcutsrc --group kwin --key "Switch to Virtual Terminal 6" "Ctrl+Alt+F6,Ctrl+Alt+F6,Switch to Virtual Terminal 6" || true
fi
