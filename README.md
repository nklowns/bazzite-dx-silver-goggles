# Bazzite-DX-Silver-Goggles

> [!WARNING]
> I built this image for me. You may use it yourself, of course, but I provide no support. I strongly suggest learning how to customize your own image using the [ublue image template](https://github.com/ublue-os/image-template). Documentation can be found [here.](https://blue-build.org/)

My system: Dell G15 5521 Laptop, 12th Generation Intel Core i7-12700H, NVIDIA GeForce RTX 3060 6GB, 64GB DDR5 RAM

Base image: [Bazzite DX (KDE/NVIDIA)](https://bazzite.gg/) - *Slim edition: built specifically for my Dell G15 setup.*

Modifications:

- Dell G15 (5521) Specific Tweaks
  - Install Dell management utilities (smbios-utils-python)
  - Ensure `akmod-acpi_call` module is built and available at boot for Alienware/Dell WMI registers
  - Install AWCC (Alienware Command Center) from source to control thermal modes

# Installation instructions:

Install any atomic fedora (Silverblue, Kinoite, Bazzite, Aurora, ... etc)

Run:
`rpm-ostree rebase ostree-image-signed:docker://ghcr.io/nklowns/bazzite-dx-silver-goggles:latest`
