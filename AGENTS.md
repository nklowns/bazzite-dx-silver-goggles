# Bazzite-DX-Silver-Goggles Copilot Instructions

This repository is a **personal customization** of Bazzite DX. It uses the [ublue-os/image-template](https://github.com/ublue-os/image-template) structure.

## Repository Purpose

- **Personal Use**: Specifically tailored for the user's hardware (Dell G15 5520).
- **Customization Layer**: Used to apply personal configurations on top of the `bazzite-dx` base image.

## MCP Context7 Libraries

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

## Technology Stack

- **Build Engine**: [BlueBuild](https://blue-build.org/).
- **Structure**: Based on the uBlue image-template.
- **Base Image**: `ghcr.io/ublue-os/bazzite-dx-nvidia`.

## Repository Structure

- `Containerfile`: Standard uBlue template containerfile.
- `Justfile`: Common uBlue recipes.
- `build_files/`: Logic for custom modifications.
- `disk_config/`: Custom disk layouts if applicable.

## Interaction Rules

1. **User-Specific**: Always consider that this image is for personal use and specific hardware.
2. **Pattern Reference**: Refer to the BlueBuild libraries in Context7 for documentation.
3. **No Support constraints**: This project does not aim for general public support, only user functionality.

## Build Commands

```bash
# Validate template syntax
just check

# Local image build
just build
```

## Working with Forks & Branch Overrides

This project follows the "Personal Customization" role. If you are developing features in a fork of `bazzite-dx` and want to test them here:

1. **Override Base Image**: Pass the `BASE_IMAGE` build argument during build.
   ```bash
   just build --build-arg BASE_IMAGE=ghcr.io/YOUR_USER/bazzite-dx-nvidia:YOUR_BRANCH
   ```
2. **Automated Fork Build**: Use the `build-fork` recipe (added in Justfile):
   ```bash
   just build-fork github_user branch_name
   ```

### 3. Local-Only Base Image Testing

If you are making changes to a local clone of `bazzite-dx` but haven't pushed it to GHCR yet:

1. **Build base**: `podman build -t localhost/bazzite-dx:dev .` (inside `bazzite-dx` folder)
2. **Build downstream**: `BASE_IMAGE=localhost/bazzite-dx:dev just build` (inside this folder)

_This ensures your changes to core uBlue logic are correctly inherited by the Silver Goggles layer before any remote pushing._

## Enterprise Development Lifecycle

To maintain enterprise-grade quality, follow this **Build -> Apply** pattern:

1. **Step 1: Build your variant**
   - **Standard**: `just build`
   - **Component (Dev AWCC)**: `AWCC_SPEC=awcc.dev.spec just build`
   - **Full Integration (Fork + Dev AWCC)**: `just build-dev <user> <branch> awcc.dev.spec`

2. **Step 2: Apply Changes**
   - Run `just rebase-local` to apply your built image.
   - Use `just hot-swap-awcc <path>` for immediate AWCC testing.

## Justfile Architecture

To maintain clarity, recipes are split between development and system-wide usage:

- **Root Justfile** ([Justfile](file:///home/cloud/dev/linux/uBlueOs/bazzite-dx-silver-goggles/Justfile)): Used for **development tasks** (building, rebasing, linting). These recipes run in your dev context.
- **System Justfile** ([60-custom.just](file:///home/cloud/dev/linux/uBlueOs/bazzite-dx-silver-goggles/system_files/usr/share/ublue-os/just/60-custom.just)): Copied to `/usr/share/ublue-os/just/60-custom.just`. These recipes are what you see when running `ujust` on the host.

## Local Source & Hot Swap (Rapid Iteration)

To avoid frequent reboots when testing specific changes, use these local-first patterns:

### 1. Testing Base Image Forks (Source Only)

If you have a local source fork of `bazzite-dx` (no GHCR image):

1. **Inside `bazzite-dx` folder**:
   ```bash
   podman build -t localhost/bazzite-dx:dev .
   ```
2. **Inside `silver-goggles` folder**:
   ```bash
   BASE_IMAGE=localhost/bazzite-dx:dev just build
   just rebase-local
   ```

### 2. Hot Swapping Components (AWCC)

To test local changes in `dell_related/AWCC` without rebuilding the whole image or rebooting:

1. **Build & Apply Live**:
   ```bash
   just hot-swap-awcc /path/to/AWCC/source
   ```
   _This will build an RPM from your local source using a container and install it live on the host system._

## Safety & Reversal (Rollback)

In case a test build or hot-swap causes issues, use these commands to revert:

1. **Undo System Rebase**:

   ```bash
   just rollback-local
   ```

   _This returns your system to the previous deployment state. Requires a reboot._

2. **Return to Official Signed Image**:

   ```bash
   just rebase-official
   ```

   _The ultimate safety recipe: switches back to the GHCR production image._

3. **Undo AWCC Hot-Swap**:
   ```bash
   just uninstall-awcc
   ```
   _This removes the live installed AWCC RPM immediately._

## System State & Lifecycle

Use `rpm-ostree status` to identify where you are in the lifecycle.

### 1. State Identification

- **● Signed (GHCR)**: `ostree-image-signed:docker://ghcr.io/...`. This is the target "Production" state.
- **● Unverified (Local)**: `ostree-unverified-image:oci-archive:...`. You are testing a full image build locally via `just rebase-local`.
- **Layered/Local Packages**: If `awcc` appears in `LocalPackages`, you have an active **Hot-Swap** on top of the base image.
- **Inactive Overrides Note**: Due to the OCI-native build nature of this image (using `dnf` in the Containerfile), `rpm-ostree db list` may appear empty on the host. This makes standard `override replace` commands appear as "Inactive". For development, always use the `just install-awcc` recipe which bypasses this via `usroverlay`.

### 2. Transition to Production

Once local tests pass:

1. **Push Code**: `git push` to trigger GitHub Actions.
2. **Revert Local State**:
   - If using a local image: `just rollback-local` (reboot).
   - If using hot-swap: `just uninstall-awcc` (live).
   - For the ultimate reversal: `just rebase-official` (reboot).
3. **Upgrade**: Once the GHCR build finishes, run `ujust update` or `rpm-ostree upgrade` to pull the final signed image.

## Local Development & Runner Strategy

### 1. Local GHA Testing (`act`)

To test GitHub Actions workflows without pushing to the cloud:

1. Install `act` via Homebrew: `brew install act`
2. Run local build simulation:
   ```bash
   # Use the 'full' image variant to include dependencies like skopeo
   just act
   ```
   _Note: `act` requires the `--privileged` flag (handled by `just act`) to allow `buildah` to create user namespaces._
   _Note: `act` can be heavy and may require high disk space. For Containerfile testing, prefer `just build`._

### 2. Self-Hosted Runner (Distrobox)

To keep the atomic host clean, run the GitHub runner inside an isolated container:

1. **Create Runner Environment**:
   `distrobox-create --name gha-runner --image fedora:43 --init`
   _(Note: `--init` allows running the runner as a systemd service internally)_
2. **Setup Runner**:
   `distrobox-enter gha-runner`
   _(Inside container)_:
   `sudo dnf install -y git podman curl`
   `mkdir ~/actions-runner && cd ~/actions-runner`
   `curl -o actions-runner-linux-x64-2.321.0.tar.gz -L https://github.com/actions/runner/releases/download/v2.321.0/actions-runner-linux-x64-2.321.0.tar.gz`
   `tar xzf ./actions-runner-linux-x64-2.321.0.tar.gz`
   `./config.sh --url https://github.com/nklowns/bazzite-dx-silver-goggles --token <TOKEN>`
   `./run.sh`
   _(Optional: Use `sudo ./svc.sh install` and `sudo ./svc.sh start` to run as a service inside Distrobox)_
