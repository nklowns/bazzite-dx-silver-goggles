# vim: set ft=make :

# Setup kernel arguments to match current system configuration
setup-kargs:
    rpm-ostree kargs --append-if-missing="vconsole.keymap=br" \
                     --append-if-missing="bluetooth.disable_ertm=1" \
                     --append-if-missing="kvm.ignore_msrs=1" \
                     --append-if-missing="kvm.report_ignored_msrs=0" \
                     --append-if-missing="intel_iommu=on" \
                     --append-if-missing="iommu=pt" \
                     --append-if-missing="rd.driver.pre=vfio-pci" \
                     --append-if-missing="vfio_pci.disable_vga=1"

# Check current kernel arguments
check-kargs:
    rpm-ostree kargs

# Check hardware and system health status
status:
    /usr/bin/g15-status
