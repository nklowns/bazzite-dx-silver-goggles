# vim: set ft=make :
# ==============================================================================
# GROUP: Agent Mesh & Deep Search (SearXNG, Vane, Lightpanda & CDP Matrix)
#
# The stack runs as ROOTLESS PODMAN QUADLET units on project-nomad_default.network.
#
# START, NOT ENABLE — respecting the Boot Impact Policy:
# Lingering is on, so an enabled user unit starts at BOOT without login.
# Every recipe below therefore starts and stops on demand.
#
# BROWSER AUTOMATION CDP MATRIX (os-fedora-silverblue.md §8):
# - Chrome:     127.0.0.1:9222 (~/.config/google-chrome-cdp)
# - Edge:       127.0.0.1:9223 (~/.config/microsoft-edge-cdp)
# - Firefox:    127.0.0.1:9224 (~/.mozilla/firefox-cdp)
# - Lightpanda: 127.0.0.1:9225 (Zig headless CDP server, zero VRAM, <30MB RAM)
# ==============================================================================

# 🔍 Iniciar o SearXNG (Metapesquisa Privada na porta :61387)
[group('Agent Mesh')]
searxng-up:
    #!/usr/bin/env bash
    set -euo pipefail
    /usr/libexec/agent-mesh-bootstrap-env
    systemctl --user daemon-reload
    systemctl --user start nomad-searxng.service
    echo "✅ SearXNG ativo em http://localhost:61387"
    echo "   API JSON: http://localhost:61387/search?q=query&format=json"

# 🛑 Parar o SearXNG
[group('Agent Mesh')]
searxng-down:
    #!/usr/bin/env bash
    set -uo pipefail
    systemctl --user stop nomad-searxng.service
    echo "🛑 SearXNG desativado."

# 📊 Diagnóstico do SearXNG
[group('Agent Mesh')]
searxng-status:
    #!/usr/bin/env bash
    set -uo pipefail
    STATE=$(systemctl --user is-active nomad-searxng.service 2>/dev/null || true)
    if [[ -f "$HOME/.config/containers/systemd/nomad-searxng.container.d/10-autostart.conf" ]]; then
        BOOT="enabled"
    else
        BOOT="disabled"
    fi
    printf '%-16s %s (boot: %s)\n' "searxng:" "${STATE:-inactive}" "$BOOT"
    if ss -tln 2>/dev/null | grep -q ':61387 '; then
        echo "  Porta 61387: ABERTA"
    else
        echo "  Porta 61387: fechada"
    fi

# ⚡ Habilitar SearXNG no boot
[group('Agent Mesh')]
searxng-enable-boot:
    #!/usr/bin/env bash
    set -euo pipefail
    DROPIN_DIR="$HOME/.config/containers/systemd/nomad-searxng.container.d"
    mkdir -p "$DROPIN_DIR"
    printf "[Install]\nWantedBy=default.target\n" > "$DROPIN_DIR/10-autostart.conf"
    systemctl --user daemon-reload
    systemctl --user restart nomad-searxng.service
    echo "⚡ SearXNG configurado para iniciar automaticamente no boot."

# 🔌 Desabilitar SearXNG do boot
[group('Agent Mesh')]
searxng-disable-boot:
    #!/usr/bin/env bash
    set -uo pipefail
    rm -f "$HOME/.config/containers/systemd/nomad-searxng.container.d/10-autostart.conf"
    rmdir "$HOME/.config/containers/systemd/nomad-searxng.container.d" 2>/dev/null || true
    systemctl --user daemon-reload
    echo "🔌 SearXNG removido do boot automático."

# 🧠 Iniciar o Vane / Perplexica (Deep Research & IA Search na porta :61385)
[group('Agent Mesh')]
vane-up:
    #!/usr/bin/env bash
    set -euo pipefail
    /usr/libexec/agent-mesh-bootstrap-env
    # Se o SearXNG não estiver ativo, avisa e inicia
    if ! systemctl --user is-active --quiet nomad-searxng.service; then
        echo "Iniciando dependência de pesquisa (SearXNG)..."
        systemctl --user start nomad-searxng.service
    fi
    systemctl --user daemon-reload
    systemctl --user start nomad-vane.service
    echo "✅ Vane ativo em http://localhost:61385"
    echo "   Para expor remotamente no Tailscale com TLS: ujust remote-vane-setup"

alias perplexica-up := vane-up

# 🛑 Parar o Vane
[group('Agent Mesh')]
vane-down:
    #!/usr/bin/env bash
    set -uo pipefail
    systemctl --user stop nomad-vane.service
    echo "🛑 Vane desativado."

alias perplexica-down := vane-down

# 📊 Diagnóstico do Vane
[group('Agent Mesh')]
vane-status:
    #!/usr/bin/env bash
    set -uo pipefail
    STATE=$(systemctl --user is-active nomad-vane.service 2>/dev/null || true)
    if [[ -f "$HOME/.config/containers/systemd/nomad-vane.container.d/10-autostart.conf" ]]; then
        BOOT="enabled"
    else
        BOOT="disabled"
    fi
    printf '%-16s %s (boot: %s)\n' "vane:" "${STATE:-inactive}" "$BOOT"
    if ss -tln 2>/dev/null | grep -q ':61385 '; then
        echo "  Porta 61385: ABERTA"
    else
        echo "  Porta 61385: fechada"
    fi

alias perplexica-status := vane-status

# ⚡ Habilitar Vane no boot
[group('Agent Mesh')]
vane-enable-boot:
    #!/usr/bin/env bash
    set -euo pipefail
    DROPIN_DIR="$HOME/.config/containers/systemd/nomad-vane.container.d"
    mkdir -p "$DROPIN_DIR"
    printf "[Install]\nWantedBy=default.target\n" > "$DROPIN_DIR/10-autostart.conf"
    systemctl --user daemon-reload
    systemctl --user restart nomad-vane.service
    echo "⚡ Vane configurado para iniciar automaticamente no boot."

# 🔌 Desabilitar Vane do boot
[group('Agent Mesh')]
vane-disable-boot:
    #!/usr/bin/env bash
    set -uo pipefail
    rm -f "$HOME/.config/containers/systemd/nomad-vane.container.d/10-autostart.conf"
    rmdir "$HOME/.config/containers/systemd/nomad-vane.container.d" 2>/dev/null || true
    systemctl --user daemon-reload
    echo "🔌 Vane removido do boot automático."

# 🔒 Expor o Vane com TLS via Tailscale Serve (:61385)
[group('Agent Mesh')]
remote-vane-setup:
    #!/usr/bin/env bash
    set -euo pipefail
    if ! systemctl --user is-active --quiet nomad-vane.service; then
        echo "❌ Vane não está rodando. Rode 'ujust vane-up' primeiro."
        exit 1
    fi
    /usr/libexec/bazzite-dx-serve ensure 61385
    DNS_NAME=$(tailscale status --self --json 2>/dev/null | jq -r '.Self.DNSName' | sed 's/\.$//')
    echo "✅ Vane remoto pronto em: https://${DNS_NAME}:61385"

# 🔓 Remover o Vane do Tailscale Serve
[group('Agent Mesh')]
remote-vane-teardown:
    #!/usr/bin/env bash
    set -uo pipefail
    /usr/libexec/bazzite-dx-serve off 61385 || true
    echo "🔓 Vane removido do Tailscale Serve."

# 🐼 Iniciar o Lightpanda CDP Headless Browser (:9225)
[group('Agent Mesh')]
lightpanda-up:
    #!/usr/bin/env bash
    set -euo pipefail
    systemctl --user daemon-reload
    systemctl --user start lightpanda.service
    echo "✅ Lightpanda CDP server ativo em ws://127.0.0.1:9225"
    echo "   Endpoint de versão: http://127.0.0.1:9225/json/version"

# 🛑 Parar o Lightpanda CDP
[group('Agent Mesh')]
lightpanda-down:
    #!/usr/bin/env bash
    set -uo pipefail
    systemctl --user stop lightpanda.service
    echo "🛑 Lightpanda CDP server parado."

# 📊 Diagnóstico do Lightpanda
[group('Agent Mesh')]
lightpanda-status:
    #!/usr/bin/env bash
    set -uo pipefail
    STATE=$(systemctl --user is-active lightpanda.service 2>/dev/null || true)
    if [[ -f "$HOME/.config/containers/systemd/lightpanda.container.d/10-autostart.conf" ]]; then
        BOOT="enabled"
    else
        BOOT="disabled"
    fi
    printf '%-16s %s (boot: %s)\n' "lightpanda:" "${STATE:-inactive}" "$BOOT"
    if ss -tln 2>/dev/null | grep -q ':9225 '; then
        echo "  Porta 9225: ABERTA (ws://127.0.0.1:9225)"
    else
        echo "  Porta 9225: fechada"
    fi

# 🚀 Iniciar a suíte completa da Agent Mesh (SearXNG + Vane + Lightpanda)
[group('Agent Mesh')]
agent-mesh-up:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "🔍 Iniciando SearXNG..."
    just searxng-up
    echo "🧠 Iniciando Vane..."
    just vane-up
    echo "🐼 Iniciando Lightpanda CDP..."
    just lightpanda-up
    echo "✅ Suíte Agent Mesh ativa."

# 🛑 Parar a suíte completa da Agent Mesh
[group('Agent Mesh')]
agent-mesh-down:
    #!/usr/bin/env bash
    set -uo pipefail
    just vane-down
    just searxng-down
    just lightpanda-down
    echo "🛑 Suíte Agent Mesh desativada."

# 📊 Status consolidado da Matriz CDP (os-fedora-silverblue.md §8)
[group('Agent Mesh')]
cdp-matrix-status:
    #!/usr/bin/env bash
    set -uo pipefail
    echo "=== 🌐 BROWSER AUTOMATION CDP MATRIX (Contract §8) ==="
    check_port() {
        local name="$1"
        local port="$2"
        local profile="$3"
        if ss -tln 2>/dev/null | grep -q ":${port} "; then
            printf '  [✔] %-14s :%-5d ATIVO    (%s)\n' "$name" "$port" "$profile"
        else
            printf '  [ ] %-14s :%-5d inativo  (%s)\n' "$name" "$port" "$profile"
        fi
    }
    check_port "Google Chrome" 9222 "~/.config/google-chrome-cdp"
    check_port "Microsoft Edge" 9223 "~/.config/microsoft-edge-cdp"
    check_port "Mozilla Firefox" 9224 "~/.mozilla/firefox-cdp (--no-remote)"
    check_port "Lightpanda" 9225 "In-Memory Zig Headless (zero profile)"
    echo
    echo "Dica: Para agentes em 'global-harness', use 'agent-browser --cdp <porta>'."
