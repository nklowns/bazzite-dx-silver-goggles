#!/usr/bin/env sh
# ==============================================================================
# Bazzite-DX: Global Developer Privacy & Telemetry Opt-Out
# Applies to all interactive and login shell sessions (Bash, Zsh).
# ==============================================================================

# Console Do Not Track standard (https://consoledonottrack.com)
export DO_NOT_TRACK=1

# Homebrew Analytics Opt-Out
export HOMEBREW_NO_ANALYTICS=1

# Go Toolchain Telemetry Opt-Out (Go 1.22+)
export GOTELEMETRY=off

# Microsoft .NET CLI Telemetry Opt-Out
export DOTNET_CLI_TELEMETRY_OPTOUT=1

# Node.js & Frontend Frameworks Telemetry Opt-Out
export NEXT_TELEMETRY_DISABLED=1
export ASTRO_TELEMETRY_DISABLED=1
export GATSBY_TELEMETRY_DISABLED=1
export STORYBOOK_DISABLE_TELEMETRY=1

# Python & AI Ecosystem Telemetry Opt-Out
export HF_HUB_DISABLE_TELEMETRY=1
export SCARF_NO_ANALYTICS=true

# Cloud, Infrastructure & Automation Tools Opt-Out
export CHECKPOINT_DISABLE=1
export VAGRANT_CHECKPOINT_DISABLE=1
export SAM_CLI_TELEMETRY=0
export PULUMI_SKIP_UPDATE_CHECK=true

# Additional Developer CLI & Frameworks Opt-Out
export POWERSHELL_TELEMETRY_OPTOUT=1
export TURBO_TELEMETRY_DISABLED=1
export NUXT_TELEMETRY_DISABLED=1
export STRIPE_CLI_TELEMETRY_OPTOUT=1
export AUTOMODE_TELEMETRY_DISABLED=1
