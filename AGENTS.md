# Bazzite-DX-Silver-Goggles AI Agent Guide

This repository is a **Personal Customization Layer** for Bazzite DX, specifically optimized for Dell G15 (5520) hardware. The entire build is driven by [`recipes/recipe.yml`](recipes/recipe.yml) following the **BlueBuild** declarative architecture.

## 📐 Project Role: Personal Customization

Focus on hardware-specific tweaks (Dell G15) and "state integrity" logic. Use the `[Silver Goggles]` prefix for agent-created issues or messages.

## 🛡️ Atomic State Policy (MANDATORY)

To maintain enterprise-grade quality on an atomic host, follow these rules:

1. **Declarative Overrides**: NEVER use `sudo cp` or manual `flatpak override` commands in scripts.
   - Use `tmpfiles.d` with the **`L+` (Symlink with overwrite)** pattern to link override files from `/usr/share/flatpak/overrides/` to `/var/lib/flatpak/overrides/`.
2. **Global Environment**: Use `files/system/usr/lib/environment.d/*.conf` for system-wide environment variables.
3. **Service Orchestration**:
   - **Enable/Mask Services**: Declared in `recipe.yml` via the `systemd` module. Do NOT add preset files manually.
   - As a reference, `thermald.service` is masked (AWCC compat) and `systemd-udev-settle.service` is masked (VFIO/IOMMU stability).
4. **Boot Logic**: Todos os argumentos de kernel são declarados via módulo `kargs` na `recipe.yml`, sem scripts imperativos intermediários.
5. **Static Files**: All system configuration goes under `files/system/`, injected by the `files` module in `recipe.yml`.

---

## 📚 MCP Context7 Knowledge Strategy

Use these libraries for BlueBuild patterns and templates:

- `blue-build.org/reference`: Technical reference for build logic.
- `blue-build.org/learn`: Tutorials and educational material for BlueBuild.
- `blue-build.org/how-to`: Practical guides for specific build tasks.
- `/blue-build/modules`: Reusable components for the image.
- `/ublue-os/image-template`: The foundation of this repository's structure.
- `/ublue-os/bazzite-dx`: The immediate upstream base of this image.

---

## 🛠️ Development Lifecycle

### 1. Build & Apply Patterns

- **Standard Build**: `just build` → `just rebase-local` (requires reboot).
- **AWCC (Stable Upstream)**: `just build-awcc` → `git add -f files/awcc-dev.rpm && git commit`.
- **AWCC (Local Dev)**: `just build-awcc /path/to/AWCC-source` (compiles from local source).
- **Hot-Swap (AWCC)**: `just hot-swap-awcc <path>` (build + apply RPM live, no reboot).
- **Full validate**: `just check` (just syntax + shellcheck + flatpak override validation).

### 2. AWCC RPM Workflow

The AWCC RPM (`files/awcc-dev.rpm`) is committed to the repo and installed at build time. Two modes:

| Command | Spec Used | Source |
|---|---|---|
| `just build-awcc` | `awcc.spec` (default) | Downloads tarball from `tr1xem/AWCC` |
| `AWCC_SPEC=awcc.dev.spec just build-awcc <src>` | `awcc.dev.spec` | Local source from `nklowns/AWCC` fork |

See [`docs/AWCC-BUILD.md`](docs/AWCC-BUILD.md) for the full workflow.

### 3. Working with Forks & Branch Overrides

If testing a fork of `bazzite-dx` as base image:

1. Edit `base-image` in `recipes/recipe.yml` to `ghcr.io/nklowns/bazzite-dx-nvidia:latest`.
2. Run `just build`.
3. Revert the change after testing.

---

## 🏗️ Repository Architecture

```
recipes/recipe.yml          ← Central build declaration (BlueBuild)
files/
  system/                   ← Static files overlaid onto / (via files module)
    usr/lib/
      environment.d/        ← Global env vars (CHROME_EXTRA_FLAGS, etc.)
      tmpfiles.d/           ← Atomic symlinks (L+ pattern)
      systemd/system-preset/← Service presets (enabled via recipe.yml systemd module)
    etc/modules-load.d/     ← Kernel module loading (acpi_call)
  scripts/
    00-install-awcc.sh      ← Installs files/awcc-dev.rpm at build time
  awcc-dev.rpm              ← Pre-compiled AWCC binary (committed to git)
build_files/
  awcc.spec                 ← Stable RPM spec (tr1xem/AWCC)
  awcc.dev.spec             ← Dev RPM spec (nklowns/AWCC fork, specific commit)
```

**Justfile Split**:
- Root `Justfile`: Development tasks (build, rebase, lint, AWCC).
- `files/justfiles/60-custom.just`: Modular host-side recipes (ujust). Injected via the `justfiles` module.

---

## 🏗️ Estratificação Expert Monolith
O Silver Goggles adota a estrutura de camadas (Layers) para máxima clareza e declaratividade:

1.  **CORE**: Fundação Federada (Módulos base Fedora/uBlue).
2.  **EXTENSIONS**: Pacotes e Repositórios extras (Bazzite-DX).
3.  **TUNING**: Otimizações de Kernel e Performance (Módulo `kargs` nativo).
4.  **HARDWARE**: Customizações Dell G15 (AWCC, dGPU, Services).
5.  **IDENTITY**: Identidade Visual e Branding.

---

## 🏁 Safety & Reversal (Rollback)

- **Undo System Rebase**: `just rollback-local` (reboot required).
- **Return to Official Image**: `just rebase-official` (reboot required).
- **Undo AWCC Hot-Swap**: `just uninstall-awcc` (live transient removal via `rpm-ostree apply-live --reset`).

---

## 🚀 CI/CD & Local Runner Strategy

### 1. Local Build

```bash
# Requires: bluebuild CLI
# Install: podman run --pull always --rm ghcr.io/blue-build/cli:latest-installer | bash
just build 2>&1 | tee output/build.log
```

### 2. Local GHA Testing (`act`)

```bash
just act   # Simulates GitHub Actions locally (requires --privileged for buildah)
```

### 3. Self-Hosted Runner (Distrobox)

To keep the host clean, run the runner in a container:

1. `distrobox-create --name gha-runner --image fedora:43 --init`.
2. `distrobox-enter gha-runner`.
3. Install dependencies (`git`, `podman`, `curl`) and configure the runner manually.
4. Use `sudo ./svc.sh install/start` to run as a service inside the container.

---

## 🧠 System State & Lifecycle

Use `rpm-ostree status` to identify your current deployment:

- **● Signed**: Production state (rebased from `ghcr.io/nklowns/bazzite-dx-silver-goggles`).
- **● Unverified**: Local testing state (rebased from `localhost/`).
- **LocalPackages**: Active Hot-Swap on top of base image.
