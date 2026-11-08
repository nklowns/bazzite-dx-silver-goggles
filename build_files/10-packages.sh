#!/usr/bin/env bash
# Installs every package the image declares, from the same repos the recipes used.
# Fedora 45 base images are composefs-native: rpm-ostree install no longer works
# inside the build container (composefs-native root), dnf5 does.
set -euo pipefail

echo "Enabling build-time repositories"
dnf5 -y copr enable karmab/kcli
dnf5 -y copr enable ublue-os/packages

# cloud-hypervisor ships in an openSUSE OBS repository. The file is removed again in
# 90-cleanup.sh, so the atomic host never sees a foreign repo.
curl -fsSL --retry 5 --retry-all-errors \
	"https://download.opensuse.org/repositories/home:/cloud-hypervisor/Fedora_Rawhide/home:cloud-hypervisor.repo" \
	-o /etc/yum.repos.d/home:cloud-hypervisor.repo

install_list() {
	local file="$1"
	echo "Installing packages from $(basename "$file")"
	# Weak dependencies stay off, explicitly. That is Bazzite's own policy
	# (system_files/desktop/shared/etc/dnf/dnf.conf in ublue-os/bazzite), and
	# stating it here keeps the image a function of packages/*.txt instead of
	# Fedora's Recommends metadata. A capability that needs a completion
	# declares it in its list; verify-image.sh asserts the tool it provides.
	# shellcheck disable=SC2046
	dnf5 -y --setopt=install_weak_deps=False install \
		$(sed -E 's/#.*//' "$file" | grep -vE '^\s*$')
}

# Every list in packages/ is installed; adding a domain is dropping a file there.
for list in "${CONTEXT_PATH}"/packages/*.txt; do
	install_list "$list"
done
