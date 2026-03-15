#!/bin/bash
set -ouex pipefail

echo "Installing declarative packages..."

# Install custom RPMs
dnf5 install -y \
  smbios-utils-python \
  tmux
