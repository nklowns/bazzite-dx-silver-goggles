#!/usr/bin/bash
# ==============================================================================
# Declarative IDE Keybindings & Terminal Integrity Sync
# Ensures terminal control sequences and chord-free integrity are deployed
# to user IDE profiles across Code, Code - Insiders, Cursor, and Antigravity IDE.
# ==============================================================================
set -euo pipefail

# shellcheck source=/dev/null
source /usr/lib/ublue/setup-services/libsetup.sh

if [[ "${1:-}" != "--force" ]]; then
	version-script ide-terminal-keybindings user 2 || exit 0
fi

IDES=("Code" "Code - Insiders" "Cursor" "Antigravity IDE")
SKEL_DIR="/etc/skel/.config"

for ide in "${IDES[@]}"; do
	target_dir="${HOME}/.config/${ide}/User"
	skel_kb="${SKEL_DIR}/${ide}/User/keybindings.json"
	skel_settings="${SKEL_DIR}/${ide}/User/settings.json"

	ide_bin=""
	case "$ide" in
		"Code") ide_bin="code" ;;
		"Code - Insiders") ide_bin="code-insiders" ;;
		"Cursor") ide_bin="cursor" ;;
		"Antigravity IDE") ide_bin="antigravity-ide" ;;
	esac

	# Process if target exists or if the corresponding IDE is installed
	if [[ -d "$target_dir" ]] || { [[ -n "$ide_bin" ]] && command -v "$ide_bin" >/dev/null 2>&1; }; then
		mkdir -p "$target_dir"
		# 1. Keybindings sync / merge
		if [[ -f "$skel_kb" ]]; then
			if [[ ! -f "${target_dir}/keybindings.json" ]]; then
				install -Dm644 "$skel_kb" "${target_dir}/keybindings.json"
			else
				python3 - "${target_dir}/keybindings.json" "$skel_kb" << 'PYEOF'
import json, re, sys

target_path = sys.argv[1]
skel_path = sys.argv[2]

def load_jsonc(path):
    try:
        with open(path, "r", encoding="utf-8") as f:
            content = f.read()
        cleaned = re.sub(r"//.*$", "", content, flags=re.MULTILINE)
        cleaned = re.sub(r",(\s*[}\]])", r"\1", cleaned)
        data = json.loads(cleaned)
        return data if isinstance(data, list) else []
    except Exception:
        return []

target_data = load_jsonc(target_path)
skel_data = load_jsonc(skel_path)

if target_data is not None and skel_data:
    existing = {
        (b.get("key"), b.get("command"), b.get("when"))
        for b in target_data if isinstance(b, dict)
    }
    modified = False
    for item in skel_data:
        if isinstance(item, dict):
            sig = (item.get("key"), item.get("command"), item.get("when"))
            if sig not in existing:
                target_data.append(item)
                existing.add(sig)
                modified = True
    if modified:
        with open(target_path, "w", encoding="utf-8") as f:
            json.dump(target_data, f, indent=4)
            f.write("\n")
PYEOF
			fi
		fi

		# 2. Settings sync (ensure terminal.integrated.allowChords = false)
		if [[ ! -f "${target_dir}/settings.json" ]] && [[ -f "$skel_settings" ]]; then
			install -Dm644 "$skel_settings" "${target_dir}/settings.json"
		elif [[ -f "${target_dir}/settings.json" ]]; then
			if ! grep -q "terminal.integrated.allowChords" "${target_dir}/settings.json"; then
				sed -i '0,/^[[:space:]]*{/s/^[[:space:]]*{/{\n    "terminal.integrated.allowChords": false,/' "${target_dir}/settings.json" 2>/dev/null || true
			fi
		fi
	fi
done
