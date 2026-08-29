# VM Bootstrap Architecture

This directory contains the declarative answer files and bootstrap scripts for fully automated, headless VM installations. These files are injected into the VMs during provisioning (e.g., via Cloud-Init, floppy, CD-ROM, or serial console) to achieve zero-touch installations.

## Architecture by OS

### 1. Linux (Fedora/Silverblue/Bazzite)
- **Mechanism:** Kickstart (`ks.cfg`) or Ignition/Cloud-Init.
- **Injection:** Attached as an `OEMdrv` volume or `cidata` ISO.
- **Outcome:** The installer reads the kickstart file, partitions the disk, creates the default user, configures SSH/networking, and reboots into the OS.

### 2. Windows 11
- **Mechanism:** `autounattend.xml`
- **Injection:** Attached as a virtual floppy or secondary CD-ROM (`virtio-win` drivers can also be included here).
- **Outcome:** Windows Setup bypasses OOBE, accepts the EULA, formats the drive, installs VirtIO drivers, and configures the Administrator account for WinRM/SSH access.

### 3. macOS (Ventura/Sonoma/Sequoia)
- **Mechanism:** Serial Console + Shell Scripts / QMP Injection
- **Injection:** Since macOS does not support standard answer files like Windows/Linux, we use the Virtio-Serial console and QMP keyboard injection to trigger a bash script (`install.sh`) that uses `startosinstall` or navigates the UI natively.
- **Reference:** We will eventually integrate principles from [reims-vgpu](https://github.com/steelbrain/reims-vgpu) for vGPU/acceleration setup.

## Usage
When spinning up a VM, the orchestrator mounts the appropriate directory as a volume or builds a dynamic ISO from it to feed to the VM.
