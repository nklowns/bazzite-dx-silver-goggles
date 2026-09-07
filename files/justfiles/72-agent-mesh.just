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
    echo "   Para expor remotamente no Tailscale com TLS: ujust remote-searxng-setup"

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
        echo "  Porta 61387: ABERTA (http://127.0.0.1:61387)"
    else
        echo "  Porta 61387: fechada"
    fi
    SERVE_STATE=$(/usr/libexec/bazzite-dx-serve status 61387 61387 http 2>/dev/null || echo "absent")
    printf '  %-14s %s\n' "tailscale serve:" "$SERVE_STATE"
    if [[ "$SERVE_STATE" == "ok" ]]; then
        DNS_NAME=$(tailscale status --self --json 2>/dev/null | jq -r '.Self.DNSName' | sed 's/\.$//' || true)
        echo "  URL Remota:    https://${DNS_NAME:-localhost}:61387"
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

# 🔒 Expor o SearXNG com TLS via Tailscale Serve (:61387)
[group('Agent Mesh')]
remote-searxng-setup:
    #!/usr/bin/env bash
    set -euo pipefail
    if ! systemctl --user is-active --quiet nomad-searxng.service; then
        echo "❌ SearXNG não está rodando. Rode 'ujust searxng-up' primeiro."
        exit 1
    fi
    /usr/libexec/bazzite-dx-serve ensure 61387
    DNS_NAME=$(tailscale status --self --json 2>/dev/null | jq -r '.Self.DNSName' | sed 's/\.$//')
    echo "✅ SearXNG remoto pronto em: https://${DNS_NAME}:61387"
    echo "   API JSON: https://${DNS_NAME}:61387/search?q=query&format=json"

# 🔓 Remover o SearXNG do Tailscale Serve
[group('Agent Mesh')]
remote-searxng-teardown:
    #!/usr/bin/env bash
    set -uo pipefail
    /usr/libexec/bazzite-dx-serve off 61387 || true
    echo "🔓 SearXNG removido do Tailscale Serve."

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
        echo "  Porta 61385: ABERTA (http://127.0.0.1:61385)"
    else
        echo "  Porta 61385: fechada"
    fi
    SERVE_STATE=$(/usr/libexec/bazzite-dx-serve status 61385 61385 http 2>/dev/null || echo "absent")
    printf '  %-14s %s\n' "tailscale serve:" "$SERVE_STATE"
    if [[ "$SERVE_STATE" == "ok" ]]; then
        DNS_NAME=$(tailscale status --self --json 2>/dev/null | jq -r '.Self.DNSName' | sed 's/\.$//' || true)
        echo "  URL Remota:    https://${DNS_NAME:-localhost}:61385"
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

# 🧅 Iniciar o Tor SOCKS5 Proxy (:9050)
[group('Agent Mesh')]
tor-up:
    #!/usr/bin/env bash
    set -euo pipefail
    systemctl --user daemon-reload
    systemctl --user start nomad-tor.service
    echo "✅ Tor SOCKS5 Proxy ativo em 127.0.0.1:9050"

# 🛑 Parar o Tor SOCKS5 Proxy
[group('Agent Mesh')]
tor-down:
    #!/usr/bin/env bash
    set -uo pipefail
    systemctl --user stop nomad-tor.service
    echo "🛑 Tor SOCKS5 Proxy desativado."

# 📊 Diagnóstico do Tor SOCKS5 Proxy
[group('Agent Mesh')]
tor-status:
    #!/usr/bin/env bash
    set -uo pipefail
    STATE=$(systemctl --user is-active nomad-tor.service 2>/dev/null || true)
    printf '%-16s %s\n' "tor-proxy:" "${STATE:-inactive}"
    if ss -tln 2>/dev/null | grep -q ':9050 '; then
        echo "  Porta 9050: ABERTA (socks5://127.0.0.1:9050)"
    else
        echo "  Porta 9050: fechada"
    fi

# 🕸️ Iniciar o nó local YaCy P2P (:8090)
[group('Agent Mesh')]
yacy-up:
    #!/usr/bin/env bash
    set -euo pipefail
    mkdir -p /var/srv/yacy/DATA
    systemctl --user daemon-reload
    systemctl --user start nomad-yacy.service
    echo "✅ YaCy P2P local node ativo em http://localhost:8090"

# 🛑 Parar o nó local YaCy P2P
[group('Agent Mesh')]
yacy-down:
    #!/usr/bin/env bash
    set -uo pipefail
    systemctl --user stop nomad-yacy.service
    echo "🛑 YaCy P2P local node desativado."

# 📊 Diagnóstico do nó local YaCy P2P
[group('Agent Mesh')]
yacy-status:
    #!/usr/bin/env bash
    set -uo pipefail
    STATE=$(systemctl --user is-active nomad-yacy.service 2>/dev/null || true)
    printf '%-16s %s\n' "yacy-node:" "${STATE:-inactive}"
    if ss -tln 2>/dev/null | grep -q ':8090 '; then
        echo "  Porta 8090: ABERTA (http://127.0.0.1:8090)"
    else
        echo "  Porta 8090: fechada"
    fi

# 🚀 Iniciar a suíte completa da Agent Mesh (SearXNG + Vane + Lightpanda)
[group('Agent Mesh')]
agent-mesh-up:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "🔍 Iniciando SearXNG..."
    ujust searxng-up
    echo "🧠 Iniciando Vane..."
    ujust vane-up
    echo "🐼 Iniciando Lightpanda CDP..."
    ujust lightpanda-up
    echo "✅ Suíte Agent Mesh ativa."

# 🛑 Parar a suíte completa da Agent Mesh
[group('Agent Mesh')]
agent-mesh-down:
    #!/usr/bin/env bash
    set -uo pipefail
    ujust vane-down
    ujust searxng-down
    ujust lightpanda-down
    echo "🛑 Suíte Agent Mesh desativada."

# 🔒 Expor a suíte Agent Mesh com TLS via Tailscale Serve (SearXNG :61387 + Vane :61385)
[group('Agent Mesh')]
remote-agent-mesh-setup:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "🔒 Configurando acesso remoto via Tailscale para SearXNG (:61387)..."
    ujust remote-searxng-setup
    echo "🔒 Configurando acesso remoto via Tailscale para Vane (:61385)..."
    ujust remote-vane-setup
    DNS_NAME=$(tailscale status --self --json 2>/dev/null | jq -r '.Self.DNSName' | sed 's/\.$//' || true)
    echo "═══════════════════════════════════════════════════════════════════"
    echo "✅ Agent Mesh Remota pronta (Tailscale HTTPS):"
    echo "   SearXNG Metasearch : https://${DNS_NAME:-localhost}:61387"
    echo "   Vane AI Research   : https://${DNS_NAME:-localhost}:61385"
    echo "═══════════════════════════════════════════════════════════════════"

# 🔓 Remover a suíte Agent Mesh do Tailscale Serve
[group('Agent Mesh')]
remote-agent-mesh-teardown:
    #!/usr/bin/env bash
    set -uo pipefail
    ujust remote-searxng-teardown
    ujust remote-vane-teardown
    echo "🔓 Agent Mesh removida do Tailscale Serve."

# 📊 Diagnóstico consolidado da Agent Mesh (Serviços + CDP Matrix + Tailscale)
[group('Agent Mesh')]
agent-mesh-status:
    #!/usr/bin/env bash
    set -uo pipefail
    echo "=== 🌐 AGENT MESH SERVICES STATUS ==="
    ujust searxng-status
    echo
    ujust tor-status
    echo
    ujust yacy-status
    echo
    ujust vane-status
    echo
    ujust lightpanda-status
    echo
    ujust cdp-matrix-status

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
