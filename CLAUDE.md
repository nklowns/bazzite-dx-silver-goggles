# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Personal customization layer for **Bazzite DX** (KDE/NVIDIA, Fedora 43) targeting Dell G15 5520 hardware. Builds a declarative, immutable OCI container image using the [BlueBuild](https://blue-build.org) framework.

The central build declaration is `recipes/recipe.yml`. Everything flows from there.

## Commands

```bash
just check          # Validate: Just syntax + bluebuild validate + ShellCheck
just build          # Compile image via BlueBuild (requires podman/docker)
just rebase-local   # Apply built image to running system (reboot required)
just rollback-local # Undo last rebase (reboot required)
just rebase-official # Return to upstream Bazzite image (reboot required)

just lint           # ShellCheck all scripts
just format         # shfmt all scripts
just clean          # Remove build artifacts

just build-awcc                           # Build stable AWCC RPM (version matched to base image)
just build-awcc /path/to/AWCC            # Build dev AWCC RPM from local source
just hot-swap-awcc /path/to/AWCC         # Build + apply AWCC live (no reboot)
just uninstall-awcc                       # Revert hot-swap (live, no reboot)

just status         # Image config, local images, tooling versions
just g15-status     # Dell G15 hardware health check
just act            # Simulate GitHub Actions locally (requires --privileged)
```

Install the `bluebuild` CLI if missing:
```bash
podman run --pull always --rm ghcr.io/blue-build/cli:latest-installer | bash
```

## Architecture

### Modular Hybrid Build Model

```
recipe.yml              ← Entry point (declarative orchestration)
├── files module        ← Overlays files/system/ onto /
├── dx.yml              ← EXTENSIONS: Cockpit, Docker, Libvirt, eBPF tools, fonts
│   └── local modules   ← Encapsulated Logic: dx-flavor (branding/policy), dx-udev
├── silver-goggles.yml  ← HARDWARE: Dell G15 kargs, AWCC RPM (rpm-ostree), thermald mask
├── initramfs module
├── dx-verify           ← System integrity auditor (custom module in modules/)
├── os-release          ← OCI metadata
└── signing             ← cosign
```

`recipes/build-recipe.yml` is **generated** by `scripts/generate-recipe.sh` at CI time — do not edit it manually.

### Key Directories

| Path | Purpose |
|------|---------|
| `files/system/` | Static files overlaid onto `/` at build time via the `files` module |
| `files/system/usr/lib/tmpfiles.d/` | Atomic symlinks (L+ pattern) — Flatpak overrides and symlinks |
| `files/system/usr/lib/environment.d/` | System-wide environment variables |
| `files/system/usr/lib/bootc/kargs.d/` | Kernel arguments (IOMMU, KVM, VFIO, Bluetooth) |
| `files/justfiles/` | Host-side `ujust` recipes (66-silver-goggles.just, 95-bazzite-dx.just) |
| `files/rpm-ostree/` | Location for pre-compiled RPMs (awcc-dev.rpm) |
| `modules/` | Custom BlueBuild modules (dx-flavor, dx-udev, dx-verify) |
| `build_files/` | RPM specs for AWCC (stable: `awcc.spec`, dev fork: `awcc.dev.spec`) |
| `just/` | Modular Just recipe files (build, dev, maint, status) |
| `disk_config/` | Bootc Image Builder (BIB) configs for QCOW2/ISO output |

### AWCC RPM

`files/rpm-ostree/awcc-dev.rpm` is committed to the repo and installed at image build time via the `rpm-ostree` module. Rebuild it when updating AWCC:

- Stable: `just build-awcc` (uses `awcc.spec`, version synced with base image)
- Dev fork: `AWCC_SPEC=awcc.dev.spec just build-awcc /path/to/AWCC` (uses `awcc.dev.spec`)

After rebuilding, commit the new RPM: `git add -f files/awcc-dev.rpm`.

### Base Image Pinning

`image-versions.yaml` pins the base image digest. Renovate automatically updates it with PRs. At CI time, `scripts/generate-recipe.sh` reads this file to populate `build-recipe.yml`.

## Atomic State Policy (Mandatory)

This is an **immutable/atomic host** — imperative system mutations are forbidden.

1. **Static files** go under `files/system/` (the `files` module overlays them onto `/`).
2. **Flatpak overrides** use `tmpfiles.d` with `L+` symlinks from `/usr/share/flatpak/overrides/` → `/var/lib/flatpak/overrides/`. Never use `flatpak override` commands in scripts.
3. **Global env vars** go in `files/system/usr/lib/environment.d/*.conf`. Never `export` in profile scripts.
4. **Service enable/mask** is declared in the `systemd` module in `recipe.yml`. Do not add preset files manually.
5. **Kernel args** go via the `kargs` module in `recipe.yml`. Never use imperative boot scripts.

## CI/CD

`.github/workflows/build.yml` runs on push to main:
1. **check** job: `just check` (lint + validate)
2. **bluebuild** job: builds and signs the OCI image, pushes to `ghcr.io/nklowns/bazzite-dx-silver-goggles`

`.github/workflows/build-disk.yml`: manual workflow for generating QCOW2/ISO disk images via BIB.

## BlueBuild Reference

Use the Context7 MCP server with these library IDs for BlueBuild documentation:
- `blue-build.org/reference` — technical reference
- `blue-build.org/learn` — tutorials
- `/blue-build/modules` — reusable module catalog
- `/ublue-os/bazzite-dx` — upstream base image
