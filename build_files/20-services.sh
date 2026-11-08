#!/usr/bin/env bash
# Declares unit state at build time. Mirrors the previous `systemd` modules.
# `systemctl enable` writes into /etc during the build, which ostree seeds once —
# the systemd module did the same, so behaviour is unchanged.
set -euo pipefail

enable_units=(
	ublue-system-setup.service
	ublue-os-libvirt-workarounds.service
	swtpm-workaround.service
	bazzite-dx-groups.service
	pmcd.service
	pmlogger.service
	pmproxy.service
	cockpit.socket
	docker.socket
	podman.socket
	uupd.timer
	input-remapper.service
	virtqemud.socket
	virtnetworkd.socket
	virtstoraged.socket
	virtnodedevd.socket
	ublue-nvctk-cdi.service
)

for unit in "${enable_units[@]}"; do
	systemctl -f enable "$unit"
done

systemctl --global -f enable ublue-user-setup.service

# thermald fights the in-tree alienware-wmi platform profiles; measured, see AGENTS.md.
systemctl -f mask thermald.service
