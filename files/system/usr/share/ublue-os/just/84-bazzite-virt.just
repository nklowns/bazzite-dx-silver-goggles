# vim: set ft=make :

# Setup and configure virtualization and vfio
setup-virtualization ACTION="":
    #!/usr/bin/bash
    source /usr/lib/ujust/ujust.sh
    if [[ $(id -u) -eq 0 ]]; then
      echo "Please do not run this command as root"
      exit 1
    fi
    # Check if we are running on a Steam Deck
    if /usr/libexec/hwsupport/valve-hardware; then
      echo "${red}${b}WARNING${n}: Virtualization is not properly supported on Steam Deck by Valve"
      echo "Use at your own risk and performance may not be ideal."
    fi
    if [ "$(systemctl is-enabled libvirtd.service)" == "disabled" ]; then
      echo "${b}libvirtd${n} service is ${red}disabled${n}!"
      echo "${green}enabling${n} and starting libvirtd"
      echo "If virt-manager says libvirtd.sock is not available after a big update, re-run this command."
      sudo systemctl enable --now libvirtd 2> /dev/null
      echo "Press ESC if you want to exit and do not need to do anything"
    fi
    OPTION={{ ACTION }}
    if [ "$OPTION" == "help" ]; then
      echo "Usage: ujust setup-virtualization <option>"
      echo "  <option>: Specify the quick option to skip the prompt"
      echo "  Use 'virt-on' to select Enable Virtualization"
      echo "  Use 'virt-off' to select Disable Virtualization"
      echo "  Use 'group' to select Add $USER to libvirt group"
      echo "  Use 'vfio-on' to select Enable VFIO drivers"
      echo "  Use 'vfio-off' to select Disable VFIO drivers"
      echo "  Use 'kvmfr' to select Autocreate Looking-Glass shm"
      echo "  Use 'usbhp-on' to select Enable SPICE USB hot plugging"
      echo "  Use 'usbhp-off' to select Disable SPICE USB hot plugging"
      exit 0
    elif [ "$OPTION" == "" ]; then
      echo "${bold}Virtualization Setup${normal}"
      echo "NOTE: Enabling Virtualization will install the virt-manager flatpak and set kernel args"
      OPTION=$(Choose \
        "Enable Virtualization" \
        "Disable Virtualization" \
        "Add $USER to libvirt group" \
        "Enable VFIO drivers" \
        "Disable VFIO drivers" \
        "Enable kvmfr module" \
        "Enable USB hot plugging" \
        "Disable USB hot plugging" \
      )
    fi
    if [[ "${OPTION,,}" =~ (^enable[[:space:]]virtualization|virt-on) ]]; then
        if ! rpm -q virt-manager | grep -P "^virt-manager-" 1>/dev/null; then
          echo "Setting up Virtualization arguments..."
          VIRT_KARGS=$(rpm-ostree kargs)
          if [[ ! "$VIRT_KARGS" =~ "kvm.ignore_msrs=1" ]]; then
              rpm-ostree kargs \
              --append-if-missing="kvm.ignore_msrs=1" \
              --append-if-missing="kvm.report_ignored_msrs=0"
          else
              echo "Virtualization kargs already present."
          fi
          echo "Making sure swtpm will work"
          if [ ! -d "/var/lib/swtpm-localca" ]; then
            sudo mkdir /var/lib/swtpm-localca
          fi
          sudo chown tss /var/lib/swtpm-localca
          sudo restorecon -rv /var/lib/libvirt
          sudo restorecon -rv /var/log/libvirt
          echo "Giving qemu access to read ISO files from $HOME"
          sudo setfacl -m u:qemu:rx $HOME

          echo 'Please reboot to apply changes'
        fi
    elif [[ "${OPTION,,}" =~ (^disable[[:space:]]virtualization|virt-off) ]]; then
      if [ "$(systemctl is-enabled libvirtd.service)" == "enabled" ]; then
        echo "${red}Disabling${n} libvirtd before removal"
        sudo systemctl disable --now libvirtd 2> /dev/null
      fi
      if [ "$(systemctl is-enabled bazzite-libvirtd-setup.service)" == "enabled" ]; then
        echo "${red}Disabling${n} bazzite-libvirtd-setup"
        sudo systemctl disable --now bazzite-libvirtd-setup.service 2> /dev/null
      fi

      rpm-ostree kargs \
      --delete-if-present="kvm.ignore_msrs=1" \
      --delete-if-present="kvm.report_ignored_msrs=0"
      echo 'Please reboot to apply changes'
    elif [[ "${OPTION,,}" =~ (^enable[[:space:]]vfio|vfio-on) ]]; then
      # Check if we are running on a Steam Deck
      if /usr/libexec/hwsupport/valve-hardware; then
        echo "IOMMU is not supported on Steam Deck"
        exit 0
      fi
      echo "Enabling VFIO..."
      VIRT_TEST=$(rpm-ostree kargs)
      CPU_VENDOR=$(grep "vendor_id" "/proc/cpuinfo" | uniq | awk -F": " '{ print $2 }')
      VENDOR_KARG="unset"
      if [[ ${VIRT_TEST} == *kvm.report_ignored_msrs* ]]; then
        rpm-ostree initramfs --enable
        if [[ ${CPU_VENDOR} == "AuthenticAMD" ]]; then
          VENDOR_KARG="amd_iommu=on"
        elif [[ ${CPU_VENDOR} == "GenuineIntel" ]]; then
          VENDOR_KARG="intel_iommu=on"  
        fi
        if [[ ${VENDOR_KARG} == "unset" ]]; then
          echo "Failed to get CPU vendor, exiting..."
          exit 1
        else
          rpm-ostree kargs \
            --append-if-missing="${VENDOR_KARG}" \
            --append-if-missing="iommu=pt" \
            --append-if-missing="rd.driver.pre=vfio-pci" \
            --append-if-missing="vfio_pci.disable_vga=1"
          echo "VFIO will be enabled on next boot, make sure you enable IOMMU, VT-d or AMD-v in your BIOS!"
          echo "Please understand that since this is such a niche use case, support will be very limited!"
          echo 'Use the command "ls-iommu -grk" to get iommu information about your GPUs, use the "--help" flag for more options'
          echo ""
          echo "${b}Systems with multiple GPUs${n}"
          echo "Bind your unused/second GPU device ids to the vfio driver by running"
          echo 'rpm-ostree kargs --append-if-missing="vfio_pci.ids=xxxx:yyyy,xxxx:yyzz"'
          echo "You will require a $(Urllink "https://www.amazon.com/s?k=hdmi+displayport+dummy+plug" "Dummy HDMI/DisplayPort plug (Ghost Adapter)") or hook the GPU"
          echo "to a separate monitor input in order to turn the GPU on when starting the VM."
          echo "NOTE: Your second GPU should be as different as possible from your main GPU and will not be usable by the host after you bind it to the vfio driver!"
          echo ""
          echo "${b}Systems with 1 GPU${n}"
          echo "Once rebooted you can continue setting up whatever scripts and hooks you need"
          echo "to get Single GPU passthrough working, however ${u}you will be on your own${n}."
          echo "${b}Do not ask for support for setting up Single GPU Passthrough, we can not help you!${n}"
        fi
      fi
    elif [[ "${OPTION,,}" =~ (^disable[[:space:]]vfio|vfio-off) ]]; then
      # Check if we are running on a Steam Deck
      if /usr/libexec/hwsupport/valve-hardware; then
        echo "IOMMU is not supported on Steam Deck"
        exit 0
      fi
      echo ""
      echo "Make sure you have ${b}disabled autostart of all VMs using VFIO${n} before continuing!"
      CONFIRM=$(Choose Cancel Continue)
      if [ "$CONFIRM" == "Continue" ]; then
        echo "Disabling VFIO..."
        VFIO_IDS="$(rpm-ostree kargs | sed -E 's/.+(vfio_pci.ids=.+\s)/\1/' | awk '{ print $1 }' | grep vfio_pci.ids)"
        VFIO_IDS_KARG=""
        if [ -n "$VFIO_IDS" ]; then
          echo "Found VFIO ids in kargs, adding the below line to removal list"
          echo "$VFIO_IDS"
          VFIO_IDS_KARG="--delete-if-present=\"$VFIO_IDS\""
        fi
        KVMFR_VAL="$(rpm-ostree kargs | sed -E 's/.+(kvmfr.static_size_mb=.+\s)/\1/' | awk '{ print $1 }' | grep kvmfr.static_size_mb)"
        KVMFR_KARG=""
        if [ -n "$KVMFR_VAL" ]; then
          echo "Found KVMFR static_size_mb in kargs, adding the below line to removal list"
          echo "$KVMFR_VAL"
          KVMFR_KARG="--delete-if-present=\"$KVMFR_VAL\""
        fi
        echo "Removing deprecated dracut modules"
        sudo rm /etc/dracut.conf.d/vfio.conf
        sudo rm /etc/modprobe.d/kvmfr.conf
        rpm-ostree kargs \
        --delete-if-present="iommu=pt" \
        --delete-if-present="iommu=on" \
        --delete-if-present="amd_iommu=on" \
        --delete-if-present="intel_iommu=on" \
        --delete-if-present="rd.driver.pre=vfio-pci" \
        --delete-if-present="vfio_pci.disable_vga=1" \
        --delete-if-present="vfio_pci.disable_vga=0" \
        $VFIO_IDS_KARG \
        $KVMFR_KARG
      fi
    elif [[ "${OPTION,,}" =~ kvmfr ]]; then
      sudo /usr/libexec/bazzite-dx-kvmfr-setup
    elif [[ "${OPTION,,}" =~ (^enable[[:space:]]usb|usbhp-on) ]]; then
      echo "Adding udev rule for USB devices"
      sudo bash -c 'cat << USBHP_UDEV > /etc/udev/rules.d/72-usbhp.rules
    ACTION=="add" SUBSYSTEM=="usb", TAG+="uaccess"
    USBHP_UDEV'
    elif [[ "${OPTION,,}" =~ (^disable[[:space:]]usb|usbhp-off) ]]; then
      sudo bash -c 'rm /etc/udev/rules.d/72-usbhp.rules'
    elif [[ "${OPTION,,}" =~ group ]]; then
      if ! grep -q "^libvirt" /etc/group; then
        grep '^libvirt' /usr/lib/group | sudo tee -a /etc/group > /dev/null
      fi
      sudo usermod -aG libvirt $USER
    fi

# Download and prepare essential tools for Windows Guests
install-windows-utils:
    #!/usr/bin/bash
    source /usr/lib/ujust/ujust.sh
    echo "${bold}Windows Guest Utility Suite (Bazzite-DX)${normal}"
    echo "This helper provides links and snippets for high-performance Windows VMs."
    echo "----------------------------------------------------------------------"

    OPTION=$(Choose \
      "Download VirtIO Drivers (ISO)" \
      "Download Looking Glass B7 Host (Windows)" \
      "Install Looking Glass B7 Client (Linux Host)" \
      "Download Virtual Display Driver (Idd)" \
      "Show Libvirt XML Snippets" \
    )

    if [[ "$OPTION" =~ "VirtIO" ]]; then
        echo "Opening download link for latest stable VirtIO drivers..."
        echo "Link: https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/latest-virtio/virtio-win.iso"
        xdg-open "https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/latest-virtio/virtio-win.iso" || true

    elif [[ "$OPTION" =~ "Windows" ]]; then
        echo "Opening Looking Glass B7 Host Setup download..."
        echo "Note: Ensure you download the 'Host' version for Windows."
        echo "Link: https://looking-glass.io/downloads"
        xdg-open "https://looking-glass.io/downloads" || true

    elif [[ "$OPTION" =~ "Linux Host" ]]; then
        echo "${bold}Looking Glass Client Installation (Bazzite Way)${normal}"
        echo "Since there is no official Flatpak, you have two high-performance options:"
        echo ""
        echo "${green}Option A: Layering (Recommended for most)${normal}"
        echo "Run this command to add the repository and install the client:"
        echo "------------------------------------------------"
        echo "sudo wget https://copr.fedorainfracloud.org/coprs/pgaskin/looking-glass-client/repo/fedora-\$(rpm -E %fedora)/pgaskin-looking-glass-client-fedora-\$(rpm -E %fedora).repo -O /etc/yum.repos.d/_copr_pgaskin-looking-glass-client.repo"
        echo "rpm-ostree install looking-glass-client"
        echo "------------------------------------------------"
        echo ""
        echo "${yellow}Option B: No-Layering (Distrobox)${normal}"
        echo "Use a Fedora container to compile and run without touching the host:"
        echo "1. distrobox create --image fedora:latest --name lg-build"
        echo "2. distrobox enter lg-build -- bash -c \"sudo dnf install -y cmake gcc-c++ binutils-devel ... (see looking-glass.io/docs/B7/build)\""
        echo ""

    elif [[ "$OPTION" =~ "Virtual Display" ]]; then
        echo "Opening IddSampleDriver (Virtual Display) repository..."
        echo "Useful if you don't have a physical dummy plug."
        echo "Link: https://github.com/georgemorgan/IddSampleDriver/releases"
        xdg-open "https://github.com/georgemorgan/IddSampleDriver/releases" || true

    elif [[ "$OPTION" =~ "XML Snippets" ]]; then
        echo "${bold}1. IVSHMEM (Looking Glass)${normal}"
        echo "Place this under <devices>:"
        echo "------------------------------------------------"
        echo "<shm dev='kvmfr0' size='128'/>"
        echo "------------------------------------------------"
        echo ""
        echo "${bold}2. CPU Passthrough${normal}"
        echo "<cpu mode='host-passthrough' check='none'/>"
        echo ""
        echo "${bold}3. Optimization (Remove Tablet)${normal}"
        echo "Remove: <input type='tablet' bus='usb'/>"
        echo "Add: <input type='mouse' bus='virtio'/>"
        echo "------------------------------------------------"
    fi

# Manage GPU Passthrough (Bind/Unbind NVIDIA GPU to VFIO)
manage-vfio-gpu ACTION="":
    #!/usr/bin/bash
    source /usr/lib/ujust/ujust.sh
    echo "${bold}VFIO GPU Passthrough Manager${normal}"
    echo "This tool binds or unbinds your NVIDIA GPU to the VFIO driver."
    echo "This is required if you want exclusive VM access to the GPU."
    echo "----------------------------------------------------------------------"

    OPTION="{{ ACTION }}"
    if [ -z "$OPTION" ]; then
        OPTION=$(Choose \
          "Bind NVIDIA GPU to VFIO (Require Reboot)" \
          "Unbind GPU (Return to Host)" \
          "Check Current GPU Status" \
        )
    fi

    if [[ "$OPTION" =~ "Bind" ]]; then
        echo "Searching for NVIDIA GPU IDs..."
        # Extract the PCI IDs for the NVIDIA VGA and Audio devices
        NVIDIA_VGA=$(lspci -nn | grep -i "VGA compatible controller.*NVIDIA" | grep -o "\[[0-9a-fA-F]\{4\}:[0-9a-fA-F]\{4\}\]" | tr -d '[]' || true)
        NVIDIA_AUDIO=$(lspci -nn | grep -i "Audio device.*NVIDIA" | grep -o "\[[0-9a-fA-F]\{4\}:[0-9a-fA-F]\{4\}\]" | tr -d '[]' || true)

        if [ -z "$NVIDIA_VGA" ]; then
            echo "${red}Error:${n} Could not detect an NVIDIA GPU."
            exit 1
        fi

        VFIO_IDS="$NVIDIA_VGA"
        if [ -n "$NVIDIA_AUDIO" ]; then
            VFIO_IDS="$VFIO_IDS,$NVIDIA_AUDIO"
        fi

        echo "Found NVIDIA IDs: ${green}$VFIO_IDS${n}"
        echo "Appending to kernel arguments..."
        rpm-ostree kargs --append-if-missing="vfio_pci.ids=$VFIO_IDS"
        echo "${yellow}Reboot required${n} to apply GPU binding."

    elif [[ "$OPTION" =~ "Unbind" ]]; then
        echo "Removing VFIO bindings from kernel arguments..."
        VFIO_IDS_KARG="$(rpm-ostree kargs | sed -E 's/.+(vfio_pci.ids=[^ ]+).*/\1/' | grep vfio_pci.ids || true)"
        if [ -n "$VFIO_IDS_KARG" ]; then
            rpm-ostree kargs --delete-if-present="$VFIO_IDS_KARG"
            echo "Binding removed. ${yellow}Reboot required${n} to return GPU to host."
        else
            echo "No vfio_pci.ids found in kernel arguments. GPU is likely already attached to the host."
        fi

    elif [[ "$OPTION" =~ "Check" ]]; then
        echo "Checking current driver for NVIDIA GPU..."
        lspci -nnk | grep -iA 3 "NVIDIA" | grep "Kernel driver in use" || echo "GPU not active or found."

        echo ""
        echo "Current VFIO Kernel Args:"
        rpm-ostree kargs | grep -o "vfio_pci.ids=[^ ]*" || echo "None"
    fi
