# ==============================================================================
# Bazzite-DX: Global Developer Privacy & Telemetry Opt-Out for Fish
# ==============================================================================

# Console Do Not Track standard (https://consoledonottrack.com)
set -gx DO_NOT_TRACK 1

# Homebrew Analytics Opt-Out
set -gx HOMEBREW_NO_ANALYTICS 1

# Go Toolchain Telemetry Opt-Out (Go 1.22+)
set -gx GOTELEMETRY off

# Microsoft .NET CLI Telemetry Opt-Out
set -gx DOTNET_CLI_TELEMETRY_OPTOUT 1

# Node.js & Frontend Frameworks Telemetry Opt-Out
set -gx NEXT_TELEMETRY_DISABLED 1
set -gx ASTRO_TELEMETRY_DISABLED 1
set -gx GATSBY_TELEMETRY_DISABLED 1
set -gx STORYBOOK_DISABLE_TELEMETRY 1

# Python & AI Ecosystem Telemetry Opt-Out
set -gx HF_HUB_DISABLE_TELEMETRY 1
set -gx SCARF_NO_ANALYTICS true

# Cloud, Infrastructure & Automation Tools Opt-Out
set -gx CHECKPOINT_DISABLE 1
set -gx VAGRANT_CHECKPOINT_DISABLE 1
set -gx SAM_CLI_TELEMETRY 0
set -gx PULUMI_SKIP_UPDATE_CHECK true

# Additional Developer CLI & Frameworks Opt-Out
set -gx POWERSHELL_TELEMETRY_OPTOUT 1
set -gx TURBO_TELEMETRY_DISABLED 1
set -gx NUXT_TELEMETRY_DISABLED 1
set -gx STRIPE_CLI_TELEMETRY_OPTOUT 1
set -gx AUTOMODE_TELEMETRY_DISABLED 1
