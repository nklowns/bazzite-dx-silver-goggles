# GEMINI.md - Project Context & Instructions

This project is a **Personal Customization Layer** for **Bazzite DX** (Fedora Atomic/Silverblue based) targeting Dell G15 5520 hardware. It uses the [BlueBuild](https://blue-build.org) framework to build a declarative, immutable OCI container image.

## Project Overview

- **Name:** Bazzite-DX-Silver-Goggles
- **Base Image:** `ghcr.io/ublue-os/bazzite-nvidia` (KDE/NVIDIA variant)
- **Target Hardware:** Dell G15 5520 (Intel i7-12700H, NVIDIA RTX 3060)
- **Framework:** [BlueBuild](https://blue-build.org)
- **Core Principles:** Declarative architecture, Atomic State Policy, Immutable host.

## Building and Running

The project uses `just` as a command runner. `bluebuild` CLI and `podman` (or `docker`) are required.

### Core Commands

- `just check`: Validates syntax, runs BlueBuild validation, and ShellChecks scripts.
- `just build`: Compiles the OCI image locally via BlueBuild.
- `just rebase-local`: Rebase the current running system to the locally built image (requires reboot).
- `just status`: Check image configuration, local images, and tooling versions.
- `just build-awcc`: Build the AWCC (Alienware Command Center) RPM from source.
- `just hot-swap-awcc <path>`: Build and apply AWCC live without a reboot for rapid iteration.

### Requirements

- `just`
- `podman` or `docker`
- `bluebuild` CLI: `podman run --pull always --rm ghcr.io/blue-build/cli:latest-installer | bash`

## Project Structure

- `recipes/`: Build declarations.
    - `recipe.yml`: Main entry point (template).
    - `build-recipe.yml`: **Generated** file used for the actual build. **DO NOT EDIT MANUALLY.**
    - `dx.yml`: Extensions (Cockpit, Docker, Libvirt, Fonts, etc.).
    - `silver-goggles.yml`: Hardware-specific logic (Kernel args, AWCC, etc.).
- `files/system/`: Static files overlaid onto `/` at build time.
- `files/justfiles/`: Host-side `ujust` recipes injected into the image.
- `modules/`: Custom BlueBuild modules (e.g., `dx-verify` for integrity audits).
- `scripts/`: Utility and generation scripts (e.g., `generate-recipe.sh`).
- `image-versions.yaml`: Pins the base image digest for reproducible builds.

## Development Conventions

### Atomic State Policy (Mandatory)

This is an **immutable/atomic host**. Imperative system mutations on the live host are strictly forbidden. All system-level changes must be baked into the image during the build process.

1.  **Image Transformation:** Build-time scripts (local modules) are authorized for branding, policy enforcement, and complex configurations that cannot be achieved via static file overlays.
2.  **Static Files:** For simple configuration, place under `files/system/` to be overlaid onto `/`.
3.  **Flatpak Overrides:** Use `tmpfiles.d` with `L+` symlinks in `files/system/usr/lib/tmpfiles.d/`.
4.  **Global Environment Variables:** Define in `files/system/usr/lib/environment.d/*.conf`.
5.  **Services:** Orchestrate via Systemd Presets or the `systemd` module in recipes.

### Scripting & Tooling

- **Shell Scripts:** Must pass `shellcheck`. Use `just lint` to verify.
- **Formatting:** Use `shfmt` for shell scripts (`just format`).
- **BlueBuild Modules:** Custom modules should follow the pattern in `modules/` and include an integrity check if possible (see `dx-verify`).

## Deployment

The image is built and pushed to `ghcr.io/nklowns/bazzite-dx-silver-goggles` via GitHub Actions.
To rebase a system to this image:
```bash
rpm-ostree rebase ostree-image-signed:docker://ghcr.io/nklowns/bazzite-dx-silver-goggles:latest
```
