#!/bin/bash
# ==============================================================================
# macOS Zero-Touch Unattended Installer Script (bazzite-dx-silver-goggles)
# Designed for execution via macOS Recovery Terminal, Serial Console, or Agent
# ==============================================================================
set -e

echo "=== [macOS Zero-Touch Bootstrap] Starting Automated Provisioning ==="
date

# 1. Detect target installation disk (target >= 60GB raw image)
echo "[1/4] Detecting Target NVMe / SATA Disk..."
TARGET_DISK=$(diskutil list | grep -E "\*(6[0-9]\.|[7-9][0-9]\.|1[0-9]{2}\.)" | awk '{print $NF}' | head -n 1)

if [ -z "$TARGET_DISK" ]; then
	# Fallback to finding QEMU HARDDISK or /dev/disk1
	TARGET_DISK=$(diskutil list | grep -B 2 "QEMU HARDDISK" | grep "/dev/disk" | awk '{print $1}' | head -n 1)
fi

if [ -z "$TARGET_DISK" ]; then
	TARGET_DISK="/dev/disk1"
fi

echo "  -> Selected Target Disk: ${TARGET_DISK}"

# 2. Format target disk to APFS with GUID Partition Map
echo "[2/4] Formatting ${TARGET_DISK} as APFS (Volume: 'Macintosh HD')..."
diskutil eraseDisk APFS "Macintosh HD" "$TARGET_DISK"

# Verify volume is mounted
if [ ! -d "/Volumes/Macintosh HD" ]; then
	echo "  [ERROR] /Volumes/Macintosh HD not found after format!"
	exit 1
fi
echo "  -> Target Volume Mounted at: /Volumes/Macintosh HD"

# 3. Locate startosinstall binary
echo "[3/4] Locating startosinstall binary..."
INSTALLER_APP=$(find / -maxdepth 2 -name "Install macOS*.app" 2>/dev/null | head -n 1)

if [ -z "$INSTALLER_APP" ]; then
	INSTALLER_APP=$(find /Volumes -maxdepth 3 -name "Install macOS*.app" 2>/dev/null | head -n 1)
fi

if [ -n "$INSTALLER_APP" ] && [ -f "${INSTALLER_APP}/Contents/Resources/startosinstall" ]; then
	STARTOSINSTALL="${INSTALLER_APP}/Contents/Resources/startosinstall"
	echo "  -> Found Installer: ${STARTOSINSTALL}"
else
	echo "  [ERROR] Could not find startosinstall binary!"
	echo "  Contents of root:"
	ls -la /
	exit 1
fi

# 4. Trigger Unattended macOS Installation
echo "[4/4] Executing startosinstall (Unattended)..."
echo "  -> Flags: --agreetolicense --nointeraction --volume '/Volumes/Macintosh HD'"

"${STARTOSINSTALL}" \
	--agreetolicense \
	--nointeraction \
	--volume "/Volumes/Macintosh HD"

echo "=== [macOS Zero-Touch Bootstrap] Preparation Complete. System will reboot into installer stage 2 ==="
