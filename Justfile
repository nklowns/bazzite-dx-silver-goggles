# ==============================================================================
# Bazzite-DX Silver Goggles: Main Justfile
# ==============================================================================
# Global Exports & Configuration

export image_name := env("IMAGE_NAME", "bazzite-dx-silver-goggles")
export default_tag := env("DEFAULT_TAG", "latest")
export bib_image := env("BIB_IMAGE", "quay.io/centos-bootc/bootc-image-builder:latest")
export PODMAN := if path_exists("/usr/bin/podman") == "true" { env("PODMAN", "/usr/bin/podman") } else if path_exists("/usr/bin/docker") == "true" { env("PODMAN", "docker") } else { env("PODMAN", "exit 1 ; ") }
export PULL_POLICY := if PODMAN =~ "docker" { "missing" } else { "newer" }

# Aliases

alias build-vm := build-qcow2
alias rebuild-vm := rebuild-qcow2
alias run-vm := run-vm-qcow2

[private]
default:
    @just --list

# ------------------------------------------------------------------------------
# Modules
# ------------------------------------------------------------------------------

import 'just/maint.just'
import 'just/build.just'
import 'just/dev.just'
import 'just/status.just'
