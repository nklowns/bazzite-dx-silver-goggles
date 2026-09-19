# Bazzite-DX-Silver-Goggles — Core Agent Contract

**Repository Context**: Developer Experience (DX) image layer targeting Dell G15 5520 (i7-12700H, RTX 3060, KDE/NVIDIA) on Fedora 44 via BlueBuild.
**Upstream Base**: `ghcr.io/ublue-os/bazzite-nvidia` | **Entry Point**: `recipes/recipe.yml`
**Detailed Architecture & Hardware Reference**: See [`AGENTS.md`](./AGENTS.md) for deep specs, port mappings, and thermal controls.

## 🛠️ Essential Commands
- `just check`: Validate syntax, run BlueBuild schema validation, and ShellCheck.
- `just build`: Compile the OCI image locally via BlueBuild (podman/docker).
- `just rebase-local`: Apply built image to the host (requires reboot).
- `just lint` / `just format`: Run ShellCheck and shfmt on in-tree scripts.
- `just status` / `just g15-status`: Check image state and Dell G15 hardware health.

## 🚨 Inviolable Guardrails (Always Enforce)
1. **Generated Recipe File**: Never manually edit `recipes/build-recipe.yml` — it is dynamically generated at CI time by `scripts/generate-recipe.sh`.
2. **Localhost Binding & Tailnet Ports**: DX services must bind strictly to `127.0.0.1` (never `0.0.0.0`) in the reserved port range `61300-61399`. Expose remotely only via `tailscale serve` / `ujust remote-*-setup`.
3. **No Boot-Enabled Background Daemons**: This is a gaming/dev machine. Services (NOMAD, Ollama, code-server) are on-demand. Do NOT add `systemd: enabled:` blocks in `nomad.yml` or `casting.yml`. User units in `ujust` recipes must use `systemctl --user start`, never `enable` (due to user lingering).
4. **Shell Script Rigor**: Every script in `files/system/` must start with `set -euo pipefail`, pass ShellCheck, and handle atomic replacements cleanly.
