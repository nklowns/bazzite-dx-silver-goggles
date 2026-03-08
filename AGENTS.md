# Bazzite-DX-Silver-Goggles Copilot Instructions

This repository is a **personal customization** of Bazzite DX. It uses the [ublue-os/image-template](https://github.com/ublue-os/image-template) structure.

## Repository Purpose

- **Personal Use**: Specifically tailored for the user's hardware (Dell G15 5521).
- **Customization Layer**: Used to apply personal configurations on top of the `bazzite-dx` base image.

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

1. **User-Specific**: Always consider that this image is for personal use.
2. **Pattern Reference**: Refer to `/websites/blue-build_reference` in Context7 for documentation.
3. **No Support constraints**: This project does not aim for general public support, only user functionality.

## Build Commands

```bash
# Validate template syntax
just check
```
