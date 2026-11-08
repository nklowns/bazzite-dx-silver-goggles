#!/usr/bin/env bash
# Installs the ujust surface exactly where the BlueBuild justfiles module put it:
# /usr/share/bluebuild/justfiles plus `import` lines in the optional 60-custom.just
# that /usr/share/ublue-os/justfile imports.
set -euo pipefail

readonly SRC="${CONTEXT_PATH}/files/justfiles"
readonly DEST="/usr/share/bluebuild/justfiles"
readonly IMPORT_FILE="/usr/share/ublue-os/just/60-custom.just"

mkdir -p "$DEST" "$(dirname "$IMPORT_FILE")"
touch "$IMPORT_FILE"

shopt -s nullglob
for file in "$SRC"/*.just; do
	name="$(basename "$file")"
	cp -f "$file" "${DEST}/${name}"
	import_line="import \"${DEST}/${name}\""
	if grep -Fqw "$import_line" "$IMPORT_FILE"; then
		echo "import already present: $name"
	else
		echo "$import_line" >>"$IMPORT_FILE"
		echo "imported: $name"
	fi
done
