#!/usr/bin/env bash
# scripts/load-image.sh
# Loads a user-built image into the rootful Podman storage.

set -euxo pipefail

TARGET_IMAGE="${1:-bazzite-nvidia}"
TAG="${2:-latest}"
PODMAN="${PODMAN:-podman}"
UID_VAL=$(id -u)

if [[ -n "${SUDO_USER:-}" || "${UID_VAL}" -eq "0" ]]; then
	echo "Already root or running under sudo, no need to load image from user ${PODMAN}."
	exit 0
fi

# Ensure localhost/ prefix for local images
full_image="${TARGET_IMAGE}:${TAG}"
if [[ "${full_image}" != */* ]]; then
	full_image="localhost/${full_image}"
fi

USER_IMG_ID=$("${PODMAN}" images --filter reference="${full_image}" --format "{{.ID}}")

if [[ -n "$USER_IMG_ID" ]]; then
	# Load into Rootful ${PODMAN}
	ID=$(sudo "${PODMAN}" images --filter reference="${full_image}" --format "{{.ID}}")
	if [[ "$ID" != "$USER_IMG_ID" ]]; then
		echo "Image ID mismatch. Copying image from user storage to root storage..."
		COPYTMP=$(mktemp -p "${PWD}" -d -t _build_podman_scp.XXXXXXXXXX)
		sudo TMPDIR="${COPYTMP}" "${PODMAN}" image scp "${UID_VAL}@localhost::${full_image}" "root@localhost::${full_image}"
		rm -rf "${COPYTMP}"
	else
		echo "Image already present in root storage and matches user image."
	fi
else
	# Make sure the image is present and/or up to date
	echo "Image not found locally. Pulling..."
	sudo "${PODMAN}" pull "${full_image}"
fi
