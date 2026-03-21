# Bazzite-DX-Silver-Goggles AI Agent Guide

This repository is a **Personal Customization Layer** for Bazzite DX, specifically optimized for Dell G15 (5520) hardware. It uses the [ublue-os/image-template](https://github.com/ublue-os/image-template) structure.

## 📐 Project Role: Personal Customization

Focus on hardware-specific tweaks (Dell G15) and "state integrity" logic. Use the `[Silver Goggles]` prefix for agent-created issues or messages.

## 🛡️ Atomic State Policy (MANDATORY)

To maintain enterprise-grade quality on an atomic host, follow these rules:

1. **Declarative Overrides**: NEVER use `sudo cp` or manual `flatpak override` commands in scripts.
   - Use `tmpfiles.d` with the **`L+` (Symlink with overwrite)** pattern to link override files from `/usr/share/flatpak/overrides/` to `/var/lib/flatpak/overrides/`.
2. **Global Environment**: Use `usr/lib/environment.d/*.conf` for system-wide environment variables (session-wide persistence).
3. **Service Orchestration**:
   - **Enable Services**: Use `usr/lib/systemd/system-preset/*.preset`.
   - **Mask Services**: Masked services MUST be symlinked to `/dev/null` inside the image layer (`/usr/lib/systemd/system/`).
     - `thermald.service`: (Required for AWCC compatibility).
     - `systemd-udev-settle.service`: (Required for VFIO/IOMMU stability on Bazzite).
4. **Boot Logic**: All kernel arguments must be handled via `usr/lib/bootc/kargs.d/` (`.toml` format) for native bootc support.

---

## 📚 MCP Context7 Knowledge Strategy

Use these libraries for BlueBuild patterns and templates:

- `blue-build.org/reference`: Technical reference for build logic.
- `blue-build.org/learn`: Tutorials and educational material for BlueBuild.
- `blue-build.org/how-to`: Practical guides for specific build tasks.
- `blue-build.org/docs`: Main BlueBuild documentation hub.
- `/blue-build/modules`: Reusable components for the image.
- `/blue-build/template`: Official repository for the BlueBuild project template.
- `/ublue-os/image-template`: The foundation of this repository's structure.
- `/blue-build/base-images`: Base context for BlueBuild.
- `/ublue-os/bazzite-dx`: The immediate upstream base of this image.

---

## 🛠️ Development Lifecycle

### 1. Build & Apply Patterns

- **Standard**: `just build` -> `just rebase-local` (requires reboot).
- **Component (Dev AWCC)**: `AWCC_SPEC=awcc.dev.spec just build`.
- **Full Integration (Fork + Dev AWCC)**: `just build-dev <user> <branch> awcc.dev.spec`.
- **Hot-Swap (AWCC)**: `just hot-swap-awcc <path>` (Build and apply RPM live, no reboot).

### 2. Working with Forks & Branch Overrides

If developing features in a fork of `bazzite-dx`:

1. **Override Base Image**: `just build --build-arg BASE_IMAGE=ghcr.io/USER/bazzite-dx:BRANCH`.
2. **Automated Fork Build**: `just build-fork github_user branch_name`.

### 3. Local-Only Base Image Testing (Recursive)

1. **Inside `bazzite-dx` folder**: `podman build -t localhost/bazzite-dx:dev .`.
2. **Inside this folder**: `BASE_IMAGE=localhost/bazzite-dx:dev just build` then `just rebase-local`.

---

## 🏗️ Repository Architecture

- **Justfile Split**:
  - Root `Justfile`: Development tasks (build, rebase, lint).
  - `system_files/usr/share/ublue-os/just/60-custom.just`: Host-side recipes (ujust).
- **Builder Stage**: AWCC is built in a multi-stage `Containerfile` to keep the final image lean.

---

## 🏁 Safety & Reversal (Rollback)

- **Undo System Rebase**: `just rollback-local` (reboot).
- **Return to Official Image**: `just rebase-official` (reboot).
- **Undo AWCC Hot-Swap**: `just uninstall-awcc` (live transient removal).

---

## 🚀 CI/CD & Local Runner Strategy

### 1. Local GHA Testing (`act`)

Run `just act` to simulate GitHub Actions locally.
_Note: Requires the `--privileged` flag to allow buildah namespaces._

### 2. Self-Hosted Runner (Distrobox)

To keep the host clean, run the runner in a container:

1. `distrobox-create --name gha-runner --image fedora:43 --init`.
2. `distrobox-enter gha-runner`.
3. Install dependencies (`git`, `podman`, `curl`) and configure the runner manually.
4. Use `sudo ./svc.sh install/start` to run as a service inside the container.

---

## 🧠 System State & Lifecycle

Use `rpm-ostree status` to identify your current deployment:

- **● Signed**: Production state.
- **● Unverified**: Local testing state.
- **LocalPackages**: Active Hot-Swap on top of base image.
