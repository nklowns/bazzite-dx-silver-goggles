# Bazzite-DX-Silver-Goggles Copilot Instructions

This repository is a **personal customization** of Bazzite DX. It uses the [ublue-os/image-template](https://github.com/ublue-os/image-template) structure.

## Repository Purpose

- **Personal Use**: Specifically tailored for the user's hardware (Dell G15 5521).
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
- **Base Image**: `ghcr.io/ublue-os/bazzite-dx`.

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

## Local Development & Runner Strategy

### 1. Local GHA Testing (`act`)
To test GitHub Actions workflows without pushing to the cloud:
1. Install `act` via Homebrew: `brew install act`
2. Run local build simulation:
   ```bash
   # Use the 'full' image variant to include dependencies like skopeo
   act -j build_push -P ubuntu-24.04=catthehacker/ubuntu:full-24.04
   ```
   *Note: `act` can be heavy and may require high disk space. For Containerfile testing, prefer `just build`.*

### 2. Self-Hosted Runner (Distrobox)
To keep the atomic host clean, run the GitHub runner inside an isolated container:
1. **Create Runner Environment**:
   `distrobox-create --name gha-runner --image fedora:43 --init` 
   *(Note: `--init` allows running the runner as a systemd service internally)*
2. **Setup Runner**:
   `distrobox-enter gha-runner`
   *(Inside container)*:
   `sudo dnf install -y git podman curl`
   `mkdir ~/actions-runner && cd ~/actions-runner`
   `curl -o actions-runner-linux-x64-2.321.0.tar.gz -L https://github.com/actions/runner/releases/download/v2.321.0/actions-runner-linux-x64-2.321.0.tar.gz`
   `tar xzf ./actions-runner-linux-x64-2.321.0.tar.gz`
   `./config.sh --url https://github.com/nklowns/bazzite-dx-silver-goggles --token <TOKEN>`
   `./run.sh`
   *(Optional: Use `sudo ./svc.sh install` and `sudo ./svc.sh start` to run as a service inside Distrobox)*
