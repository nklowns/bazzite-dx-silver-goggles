# Bazzite-DX-Silver-Goggles

> [!WARNING]
> I built this image for me. You may use it yourself, of course, but I provide no support. I strongly suggest learning how to customize your own image using the [ublue image template](https://github.com/ublue-os/image-template). Documentation can be found [here.](https://blue-build.org/)

My system: Dell G15 5521 Laptop, 12th Generation Intel Core i7-12700H, NVIDIA GeForce RTX 3060 6GB, 64GB DDR5 RAM

Base image: [Bazzite DX (KDE/NVIDIA)](https://bazzite.gg/) - _Slim edition: built specifically for my Dell G15 setup._

Modifications:

- Dell G15 (5521) Specific Tweaks
  - Install Dell management utilities (smbios-utils-python)
  - Ensure `akmod-acpi_call` module is built and available at boot for Alienware/Dell WMI registers
  - Install AWCC (Alienware Command Center) from source to control thermal modes

# Installation instructions:

Install any atomic fedora (Silverblue, Kinoite, Bazzite, Aurora, ... etc)

Run:
`rpm-ostree rebase ostree-image-signed:docker://ghcr.io/nklowns/bazzite-dx-silver-goggles:latest`

# Local Development

To test changes on your local system:

1. **Build Your Image**:

   ```bash
   just build             # Standard build using default Spec
   just build-fork <user> <branch>    # From a Bazzite-DX fork (GHCR)
   just build-dev <user> <branch> <spec> # Full Integration test (GHCR + Custom AWCC)
   BASE_IMAGE=localhost/bazzite-dx:dev just build # Build using a locally built base
   ```

2. **Full System Test (requires reboot)**:

   ```bash
   just rebase-local      # Rebases your system to the locally built image
   just rollback-local    # Reverses the local rebase
   ```

3. **Component Hot-Swap (AWCC Only - no reboot)**:
   This is the fastest way to test AWCC changes. It builds an RPM from your local source and applies it live.

   ```bash
   # Usage: just hot-swap-awcc <path_to_AWCC_source>
   just hot-swap-awcc /home/cloud/dev/linux/uBlueOs/dell_related/AWCC
   ```

4. **Verify Installation**:
   Check if the development version is correctly applied:

   ```bash
   rpm -q awcc          # Should show dev.swap version
   rpm-ostree status    # Should show 'Unlocked: transient' and replacements
   ```

5. **Safety & Reversal**:
   - Undo Local Rebase: `just rollback-local` (reboot required)
   - Reset to Official: `just rebase-official` (reboot required)
   - Undo AWCC Hot-Swap: `just uninstall-awcc` (live apply - no reboot)

> [!TIP]
> If `hot-swap-awcc` fails due to version conflicts, the script now automatically injects a `dev.swap` version to force the override.
