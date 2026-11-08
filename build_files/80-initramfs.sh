#!/usr/bin/env bash
# Regenerates the initramfs for every installed kernel with the same flags the
# BlueBuild initramfs module used. Required for gpu_unlock (force_drivers) and
# for the nvidia modeset regression workaround.
set -euo pipefail

DRACUT="/usr/bin/dracut"
[[ -x /usr/libexec/rpm-ostree/wrapped/dracut ]] && DRACUT="/usr/libexec/rpm-ostree/wrapped/dracut"

log_conf="$(mktemp /etc/dracut.conf.d/zzz-loglevels-XXXXXXXXXX.conf)"
cat >"$log_conf" <<'EOF'
stdloglvl=4
sysloglvl=0
kmsgloglvl=0
fileloglvl=0
EOF

for kernel_path in /usr/lib/modules/*/; do
	kernel_path="${kernel_path%/}"
	kver="${kernel_path##*/}"
	echo "Regenerating initramfs for ${kver}"
	"$DRACUT" \
		--kver "$kver" \
		--force \
		--add 'ostree' \
		--no-hostonly \
		--reproducible \
		"${kernel_path}/initramfs.img"
	chmod 0600 "${kernel_path}/initramfs.img"
done

rm -f "$log_conf"
