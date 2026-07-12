# Bazzite-DX-Silver-Goggles — AI Agent Guide

Single source of truth for AI agents in this repository (`CLAUDE.md` and `GEMINI.md` are symlinks to this file).

Personal customization layer targeting **Dell G15 5520** (Intel i7-12700H, NVIDIA RTX 3060), KDE/NVIDIA, Fedora 44. Builds a declarative, immutable OCI container image with the [BlueBuild](https://blue-build.org) framework.

- **Base image**: `ghcr.io/ublue-os/bazzite-nvidia` — DX tooling is applied by this repo's own `recipes/dx.yml`, following `bazzite-dx` patterns.
- **Entry point**: `recipes/recipe.yml`. Everything flows from there.
- Use the `[Silver Goggles]` prefix for agent-created issues or messages.

## 🛠️ Commands

```bash
just check          # Validate: Just syntax + bluebuild validate + ShellCheck
just build          # Compile image via BlueBuild (requires podman/docker)
just rebase-local   # Apply built image to running system (reboot required)
just rollback-local # Undo last rebase (reboot required)
just rebase-official # Return to upstream Bazzite image (reboot required)

just lint           # ShellCheck all scripts
just format         # shfmt all scripts
just clean          # Remove build artifacts

just build-awcc                    # Build stable AWCC RPM (version matched to base image)
just build-awcc /path/to/AWCC      # Build dev AWCC RPM from local source
just hot-swap-awcc /path/to/AWCC   # Build + apply AWCC live (no reboot)
just uninstall-awcc                # Revert hot-swap (live, rpm-ostree apply-live --reset)

just status         # Image config, local images, tooling versions
just g15-status     # Dell G15 hardware health check
just act            # Simulate GitHub Actions locally (requires --privileged for buildah)
```

Requirements: `just`, `podman` (or `docker`), `bluebuild` CLI. Install the CLI if missing:
```bash
podman run --pull always --rm ghcr.io/blue-build/cli:latest-installer | bash
```

## 🏗️ Architecture

### Modular Hybrid Build Model

```
recipe.yml              ← Entry point (declarative orchestration)
├── files module        ← Overlays files/system/ onto /
├── dx.yml              ← EXTENSIONS: Cockpit, Docker, Libvirt, eBPF tools, fonts
│   └── local modules   ← Encapsulated logic: dx-flavor (branding/policy), dx-udev
├── silver-goggles.yml  ← HARDWARE: Dell G15 kargs, AWCC RPM (rpm-ostree), thermald mask
├── initramfs module
├── dx-verify           ← System integrity auditor (custom module in modules/)
├── os-release          ← OCI metadata
└── signing             ← cosign
```

`recipes/build-recipe.yml` is **generated** by `scripts/generate-recipe.sh` at CI time — never edit it manually.

### Expert Monolith Layers

1. **CORE** — Fedora/uBlue base modules (`bazzite-nvidia` upstream).
2. **EXTENSIONS** — extra packages and repos (`dx.yml`).
3. **TUNING** — kernel and performance optimization (native `kargs` module).
4. **HARDWARE** — Dell G15 customization (AWCC, dGPU, services).
5. **IDENTITY** — visual identity and branding.

### Key Directories

| Path | Purpose |
|------|---------|
| `recipes/` | Build declarations (`recipe.yml`, `dx.yml`, `silver-goggles.yml`, generated `build-recipe.yml`) |
| `files/system/` | Static files overlaid onto `/` at build time via the `files` module |
| `files/system/usr/lib/tmpfiles.d/` | Atomic symlinks (L+ pattern) — Flatpak overrides and symlinks |
| `files/system/usr/lib/environment.d/` | System-wide environment variables (CHROME_EXTRA_FLAGS, etc.) |
| `files/system/usr/lib/bootc/kargs.d/` | Kernel arguments (IOMMU, KVM, VFIO, Bluetooth) |
| `files/system/etc/modules-load.d/` | Kernel module loading (acpi_call) |
| `files/justfiles/` | Host-side `ujust` recipes (66-silver-goggles.just, 95-bazzite-dx.just), injected via the `justfiles` module |
| `files/rpm-ostree/` | Pre-compiled RPMs committed to git (awcc-dev.rpm) |
| `modules/` | Custom BlueBuild modules (dx-flavor, dx-udev, dx-verify) |
| `build_files/` | AWCC RPM specs (stable: `awcc.spec`; dev fork: `awcc.dev.spec`) |
| `just/` | Modular Just recipe files (build, dev, maint, status) |
| `scripts/` | Utility/generation scripts (`generate-recipe.sh`) |
| `disk_config/` | Bootc Image Builder (BIB) configs for QCOW2/ISO output |
| `image-versions.yaml` | Pins the base image digest (updated by Renovate PRs; consumed by `generate-recipe.sh`) |

**Justfile split**: root `Justfile` = development tasks (build, rebase, lint, AWCC); `files/justfiles/66-silver-goggles.just` = modular host-side `ujust` recipes.

## 🛡️ Atomic State Policy (MANDATORY)

Immutable/atomic host — imperative system mutations on the live host are forbidden. Everything is baked into the image at build time.

1. **Static files** go under `files/system/` (the `files` module overlays them onto `/`). Never mutate `/etc` directly.
2. **Flatpak overrides**: NEVER use `flatpak override` or `sudo cp` in scripts. Use `tmpfiles.d` with the **`L+` (symlink with overwrite)** pattern linking `/usr/share/flatpak/overrides/` → `/var/lib/flatpak/overrides/`.
3. **Global env vars** go in `files/system/usr/lib/environment.d/*.conf`. Never `export` in profile scripts.
4. **Service enable/mask** is declared via the `systemd` module in `recipe.yml` OR generated by local modules at build time (e.g., `dx-flavor` presets). Reference: `thermald.service` masked (AWCC compat), `systemd-udev-settle.service` masked (VFIO/IOMMU stability). Do not add preset files manually.
5. **Kernel args** go via the `kargs` module (plus local-module tuning if needed). Never use imperative boot scripts.
6. **Image transformation**: build-time scripts (local modules) are the authorized escape hatch for branding, policy enforcement, and config that static overlays can't express.

### Scripting Conventions

- Shell scripts must pass `shellcheck` (`just lint`); format with `shfmt` (`just format`).
- Custom BlueBuild modules follow the pattern in `modules/` and should include an integrity check where possible (see `dx-verify`).

## ⚙️ AWCC RPM Workflow

`files/rpm-ostree/awcc-dev.rpm` is committed to the repo and installed at image build time via the `rpm-ostree` module.

| Command | Spec used | Source |
|---|---|---|
| `just build-awcc` | `awcc.spec` (default) | Downloads tarball from `tr1xem/AWCC`, version synced with base image |
| `AWCC_SPEC=awcc.dev.spec just build-awcc <src>` | `awcc.dev.spec` | Local source from `nklowns/AWCC` fork (pinned commit) |

After rebuilding, commit the RPM: `git add -f files/rpm-ostree/awcc-dev.rpm && git commit`.
Rapid iteration: `just hot-swap-awcc <path>` (live apply, no reboot); revert with `just uninstall-awcc`.
Full workflow: [`docs/AWCC-BUILD.md`](docs/AWCC-BUILD.md).

## 🔀 Testing Forks & Branch Overrides

To test a fork of the base image:
1. Edit `base-image` in `recipes/recipe.yml` (e.g., `ghcr.io/nklowns/bazzite-dx-nvidia:latest`).
2. `just build`.
3. Revert after testing.

## 🚀 CI/CD & Deployment

`.github/workflows/build.yml` on push to main:
1. **check** job — `just check` (lint + validate).
2. **bluebuild** job — builds, signs (cosign), and pushes to `ghcr.io/nklowns/bazzite-dx-silver-goggles`.

`.github/workflows/build-disk.yml` — manual workflow for QCOW2/ISO disk images via BIB.

Rebase a system to the published image:
```bash
rpm-ostree rebase ostree-image-signed:docker://ghcr.io/nklowns/bazzite-dx-silver-goggles:latest
```

### Local Build

```bash
just build 2>&1 | tee output/build.log
```

### Local GHA Testing (`act`)

```bash
just act   # Simulates GitHub Actions locally (requires --privileged for buildah)
```

### Self-Hosted Runner (Distrobox)

Keep the host clean — run the runner in a container:
1. `distrobox-create --name gha-runner --image fedora:44 --init`
2. `distrobox-enter gha-runner`
3. Install deps (`git`, `podman`, `curl`) and configure the runner manually.
4. `sudo ./svc.sh install/start` to run as a service inside the container.

## 🏁 Safety & Rollback

- **Undo system rebase**: `just rollback-local` (reboot required).
- **Return to official image**: `just rebase-official` (reboot required).
- **Undo AWCC hot-swap**: `just uninstall-awcc` (live transient removal via `rpm-ostree apply-live --reset`).

## 🧠 System State Identification

`rpm-ostree status` deployment markers:
- **● Signed** — production state (rebased from `ghcr.io/nklowns/bazzite-dx-silver-goggles`).
- **● Unverified** — local testing state (rebased from `localhost/`).
- **LocalPackages** — active hot-swap on top of the base image.

## 📚 BlueBuild Reference (Context7 MCP)

- `blue-build.org/reference` — technical reference for build logic.
- `blue-build.org/learn` — tutorials and educational material.
- `blue-build.org/how-to` — practical guides for specific build tasks.
- `/blue-build/modules` — reusable module catalog.
- `/ublue-os/image-template` — foundation of this repository's structure.
- `/ublue-os/bazzite-dx` — upstream DX patterns reference.

For grep-level lookups of upstream implementations, prefer the local clones in `../ublue-os/` and `../blue-build/` (see workspace `AGENTS.md`).
