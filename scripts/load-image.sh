#!/usr/bin/env bash

# Loads a user-built image into the rootful Podman storage for local rebase.
set -euo pipefail

TARGET_IMAGE="${1:-bazzite-nvidia}"
TAG="${2:-latest}"
PODMAN="${PODMAN:-podman}"
UID_VAL=$(id -u)

# Skip copy if already running with sufficient privileges.
if [[ -n "${SUDO_USER:-}" || "${UID_VAL}" -eq "0" ]]; then
	echo "Running as root; skip user-to-root image migration."
	exit 0
fi

full_image="${TARGET_IMAGE}:${TAG}"
[[ "${full_image}" != */* ]] && full_image="localhost/${full_image}"

USER_IMG_ID=$("${PODMAN}" images --filter reference="${full_image}" --format "{{.ID}}")

if [[ -n "$USER_IMG_ID" ]]; then
	# Synchronization Logic: Move image from user storage to root storage.
	ROOT_IMG_ID=$(sudo "${PODMAN}" images --filter reference="${full_image}" --format "{{.ID}}")
	if [[ "$ROOT_IMG_ID" != "$USER_IMG_ID" ]]; then
		echo "Image mismatch detected. Migrating image to root storage..."
		COPYTMP=$(mktemp -p "${PWD}" -d -t _build_podman_scp.XXXXXXXXXX)
		sudo TMPDIR="${COPYTMP}" "${PODMAN}" image scp "${UID_VAL}@localhost::${full_image}" "root@localhost::${full_image}"
		rm -rf "${COPYTMP}"
	else
		echo "Image in root storage is already synchronized with user storage."
	fi
else
	# Fallback: Pull from registry if not found in local user storage.
	echo "Image not found in user storage. Pulling from registry..."
	sudo "${PODMAN}" pull "${full_image}"
fi
