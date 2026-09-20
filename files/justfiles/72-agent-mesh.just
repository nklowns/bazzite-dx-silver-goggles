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
# BROWSER AUTOMATION CDP MATRIX (fixed port convention, bring-your-own runners):
# - chrome-cdp:  127.0.0.1:9222 (~/.config/google-chrome-cdp)
# - edge-cdp:    127.0.0.1:9223 (~/.config/microsoft-edge-cdp)
# - firefox-cdp: 127.0.0.1:9224 (~/.mozilla/firefox-cdp)
# - lightpanda:  127.0.0.1:9225 (Zig headless CDP server, zero VRAM, <30MB RAM)
# ==============================================================================

# 🔍 Iniciar o SearXNG (Metapesquisa Privada na porta :61387)
[group('Agent Mesh')]
searxng-up:
    #!/usr/bin/env bash
    set -euo pipefail
    /usr/libexec/agent-mesh-bootstrap-env
    systemctl --user daemon-reload
    systemctl --user start mesh-searxng.service
    echo "✅ SearXNG ativo em http://localhost:61387"
    echo "   API JSON: http://localhost:61387/search?q=query&format=json"
    echo "   Para expor remotamente no Tailscale com TLS: ujust remote-searxng-setup"

# 🛑 Parar o SearXNG
[group('Agent Mesh')]
searxng-down:
    #!/usr/bin/env bash
    set -uo pipefail
    systemctl --user stop mesh-searxng.service
    echo "🛑 SearXNG desativado."

# 📊 Diagnóstico do SearXNG
[group('Agent Mesh')]
searxng-status:
    #!/usr/bin/env bash
    set -uo pipefail
    STATE=$(systemctl --user is-active mesh-searxng.service 2>/dev/null || true)
    if [[ -f "$HOME/.config/containers/systemd/mesh-searxng.container.d/10-autostart.conf" ]]; then
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
    DROPIN_DIR="$HOME/.config/containers/systemd/mesh-searxng.container.d"
    mkdir -p "$DROPIN_DIR"
    printf "[Install]\nWantedBy=default.target\n" > "$DROPIN_DIR/10-autostart.conf"
    systemctl --user daemon-reload
    systemctl --user restart mesh-searxng.service
    echo "⚡ SearXNG configurado para iniciar automaticamente no boot."

# 🔌 Desabilitar SearXNG do boot
[group('Agent Mesh')]
searxng-disable-boot:
    #!/usr/bin/env bash
    set -uo pipefail
    rm -f "$HOME/.config/containers/systemd/mesh-searxng.container.d/10-autostart.conf"
    rmdir "$HOME/.config/containers/systemd/mesh-searxng.container.d" 2>/dev/null || true
    systemctl --user daemon-reload
    echo "🔌 SearXNG removido do boot automático."

# 🔒 Expor o SearXNG com TLS via Tailscale Serve (:61387)
[group('Agent Mesh')]
remote-searxng-setup:
    #!/usr/bin/env bash
    set -euo pipefail
    if ! systemctl --user is-active --quiet mesh-searxng.service; then
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
    if ! systemctl --user is-active --quiet mesh-searxng.service; then
        echo "Iniciando dependência de pesquisa (SearXNG)..."
        systemctl --user start mesh-searxng.service
    fi
    # Se o Ollama GPU não estiver ativo, avisa e inicia
    if ! systemctl --user is-active --quiet nomad-ollama.service; then
        echo "Iniciando dependência de inferência LLM (Ollama GPU)..."
        systemctl --user start nomad-ollama.service
    fi
    systemctl --user daemon-reload
    systemctl --user start mesh-vane.service
    echo "✅ Vane ativo em http://localhost:61385"
    echo "   Para expor remotamente no Tailscale com TLS: ujust remote-vane-setup"

alias perplexica-up := vane-up

# 🛑 Parar o Vane
[group('Agent Mesh')]
vane-down:
    #!/usr/bin/env bash
    set -uo pipefail
    systemctl --user stop mesh-vane.service
    echo "🛑 Vane desativado."
    if systemctl --user is-active --quiet nomad-ollama.service 2>/dev/null; then
        echo "💡 Ollama GPU ainda está ativo segurando VRAM da NVIDIA. Para liberar memória de vídeo: ujust ollama-down"
    fi

alias perplexica-down := vane-down

# 📊 Diagnóstico do Vane
[group('Agent Mesh')]
vane-status:
    #!/usr/bin/env bash
    set -uo pipefail
    STATE=$(systemctl --user is-active mesh-vane.service 2>/dev/null || true)
    if [[ -f "$HOME/.config/containers/systemd/mesh-vane.container.d/10-autostart.conf" ]]; then
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
    DROPIN_DIR="$HOME/.config/containers/systemd/mesh-vane.container.d"
    mkdir -p "$DROPIN_DIR"
    printf "[Install]\nWantedBy=default.target\n" > "$DROPIN_DIR/10-autostart.conf"
    systemctl --user daemon-reload
    systemctl --user restart mesh-vane.service
    echo "⚡ Vane configurado para iniciar automaticamente no boot."

# 🔌 Desabilitar Vane do boot
[group('Agent Mesh')]
vane-disable-boot:
    #!/usr/bin/env bash
    set -uo pipefail
    rm -f "$HOME/.config/containers/systemd/mesh-vane.container.d/10-autostart.conf"
    rmdir "$HOME/.config/containers/systemd/mesh-vane.container.d" 2>/dev/null || true
    systemctl --user daemon-reload
    echo "🔌 Vane removido do boot automático."

# 🔒 Expor o Vane com TLS via Tailscale Serve (:61385)
[group('Agent Mesh')]
remote-vane-setup:
    #!/usr/bin/env bash
    set -euo pipefail
    if ! systemctl --user is-active --quiet mesh-vane.service; then
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
    systemctl --user start mesh-tor.service
    echo "✅ Tor SOCKS5 Proxy ativo em 127.0.0.1:9050"

# 🛑 Parar o Tor SOCKS5 Proxy
[group('Agent Mesh')]
tor-down:
    #!/usr/bin/env bash
    set -uo pipefail
    systemctl --user stop mesh-tor.service
    echo "🛑 Tor SOCKS5 Proxy desativado."

# 📊 Diagnóstico do Tor SOCKS5 Proxy
[group('Agent Mesh')]
tor-status:
    #!/usr/bin/env bash
    set -uo pipefail
    STATE=$(systemctl --user is-active mesh-tor.service 2>/dev/null || true)
    printf '%-16s %s\n' "tor-proxy:" "${STATE:-inactive}"
    if ss -tln 2>/dev/null | grep -q ':9050 '; then
        echo "  Porta 9050: ABERTA (socks5://127.0.0.1:9050)"
    else
        echo "  Porta 9050: fechada"
    fi

# 🟣 Iniciar o daemon I2P (i2pd) e Proxy (:4444 / :4447 / :7070)
[group('Agent Mesh')]
i2p-up:
    #!/usr/bin/env bash
    set -euo pipefail
    mkdir -p /var/srv/i2pd/data
    systemctl --user daemon-reload
    systemctl --user start mesh-i2pd.service
    echo "✅ I2P Client Daemon ativo."
    echo "   Proxy HTTP (Eepsites): http://127.0.0.1:4444"
    echo "   Proxy SOCKS5:          socks5://127.0.0.1:4447"
    echo "   Web Console:           http://127.0.0.1:7070"

# 🛑 Parar o daemon I2P (i2pd)
[group('Agent Mesh')]
i2p-down:
    #!/usr/bin/env bash
    set -uo pipefail
    systemctl --user stop mesh-i2pd.service
    echo "🛑 I2P Client Daemon desativado."

# 📊 Diagnóstico do daemon I2P (i2pd)
[group('Agent Mesh')]
i2p-status:
    #!/usr/bin/env bash
    set -uo pipefail
    STATE=$(systemctl --user is-active mesh-i2pd.service 2>/dev/null || true)
    printf '%-16s %s\n' "i2p-daemon:" "${STATE:-inactive}"
    if ss -tln 2>/dev/null | grep -q ':4444 '; then
        echo "  Porta 4444 (HTTP Proxy): ABERTA"
    else
        echo "  Porta 4444 (HTTP Proxy): fechada"
    fi
    if ss -tln 2>/dev/null | grep -q ':4447 '; then
        echo "  Porta 4447 (SOCKS Proxy): ABERTA"
    else
        echo "  Porta 4447 (SOCKS Proxy): fechada"
    fi
    if ss -tln 2>/dev/null | grep -q ':7070 '; then
        echo "  Porta 7070 (Web Console): ABERTA (http://127.0.0.1:7070)"
    else
        echo "  Porta 7070 (Web Console): fechada"
    fi

# 📜 Visualizar logs do daemon I2P
[group('Agent Mesh')]
i2p-logs:
    journalctl --user -u mesh-i2pd.service -f

# 🪝 Iniciar o motor Trawl Anti-Captcha & Scraper (:8191 / :8192)
[group('Agent Mesh')]
trawl-up:
    #!/usr/bin/env bash
    set -euo pipefail
    mkdir -p /var/srv/trawl/ca 2>/dev/null || true
    systemctl --user daemon-reload
    systemctl --user start mesh-trawl.service
    echo "✅ Trawl Anti-Captcha & Scraper ativo em http://127.0.0.1:8191 (Proxy MITM :8192)"

# 🛑 Parar o motor Trawl Anti-Captcha & Scraper
[group('Agent Mesh')]
trawl-down:
    #!/usr/bin/env bash
    set -uo pipefail
    systemctl --user stop mesh-trawl.service
    echo "🛑 Trawl Anti-Captcha & Scraper desativado."

# 📊 Diagnóstico do motor Trawl
[group('Agent Mesh')]
trawl-status:
    #!/usr/bin/env bash
    set -uo pipefail
    STATE=$(systemctl --user is-active mesh-trawl.service 2>/dev/null || true)
    printf '%-16s %s\n' "trawl-engine:" "${STATE:-inactive}"
    if ss -tln 2>/dev/null | grep -q ':8191 '; then
        echo "  Porta 8191 (API): ABERTA"
    else
        echo "  Porta 8191 (API): fechada"
    fi
    if ss -tln 2>/dev/null | grep -q ':8192 '; then
        echo "  Porta 8192 (MITM Proxy): ABERTA"
    else
        echo "  Porta 8192 (MITM Proxy): fechada"
    fi

# 📜 Visualizar logs do motor Trawl
[group('Agent Mesh')]
trawl-logs:
    journalctl --user -u mesh-trawl.service -f

# 🚀 Iniciar a suíte completa da Agent Mesh (Tor + I2P + Trawl + SearXNG + Recoll + Vane + Lightpanda)
[group('Agent Mesh')]
agent-mesh-up:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "🧅 [1/7] Iniciando Tor Proxy (:9050)..."
    ujust tor-up
    echo "🌌 [2/7] Iniciando I2P Daemon (:4444)..."
    ujust i2p-up
    echo "🪝 [3/7] Iniciando Trawl Anti-Bot Solver (:8191)..."
    ujust trawl-up
    echo "🔍 [4/7] Iniciando SearXNG Metasearch (:61387)..."
    ujust searxng-up
    echo "📁 [5/7] Iniciando Recoll Workspace Search (:61389)..."
    ujust recoll-up
    echo "🧠 [6/7] Iniciando Vane AI Research (:61385)..."
    ujust vane-up
    echo "🐼 [7/7] Iniciando Lightpanda CDP Server (:9225)..."
    ujust lightpanda-up
    echo "═══════════════════════════════════════════════════════════════════"
    echo "✅ Toda a infraestrutura Agent Mesh está ativa e sincronizada."
    echo "═══════════════════════════════════════════════════════════════════"

# 🛑 Parar a suíte completa da Agent Mesh
[group('Agent Mesh')]
agent-mesh-down:
    #!/usr/bin/env bash
    set -uo pipefail
    echo "Parando toda a suíte Agent Mesh..."
    ujust vane-down
    ujust recoll-down
    ujust searxng-down
    ujust trawl-down
    ujust i2p-down
    ujust tor-down
    ujust lightpanda-down
    echo "═══════════════════════════════════════════════════════════════════"
    echo "🛑 Toda a infraestrutura Agent Mesh foi desativada."
    echo "═══════════════════════════════════════════════════════════════════"

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
    ujust remote-recoll-teardown 2>/dev/null || true
    echo "🔓 Agent Mesh removida do Tailscale Serve."

# 📁 Iniciar o Recoll WebUI (:61389)
[group('Agent Mesh')]
recoll-up:
    #!/usr/bin/env bash
    set -euo pipefail
    if [[ ! -d /var/srv/recoll/xapiandb ]]; then
        echo "❌ /var/srv/recoll/xapiandb não existe — o provisionamento declarativo não rodou."
        echo "   Verifique: systemctl status bazzite-dx-groups.service"
        exit 1
    fi
    # Ensure recoll.conf exists before Quadlet starts (prevents Podman directory creation bug)
    if [[ ! -f "$HOME/.config/recoll/recoll.conf" ]]; then
        mkdir -p "$HOME/.config/recoll"
        TEMPLATE="/usr/share/recoll/recoll.conf.template"
        if [[ ! -f "$TEMPLATE" ]]; then
            TEMPLATE="{{ justfile_directory() }}/../system/usr/share/recoll/recoll.conf.template"
        fi
        if [[ -f "$TEMPLATE" ]]; then
            cp "$TEMPLATE" "$HOME/.config/recoll/recoll.conf"
            echo "📄 Arquivo ~/.config/recoll/recoll.conf inicializado a partir do template."
        fi
    fi
    systemctl --user daemon-reload
    systemctl --user start mesh-recoll.service
    echo "✅ Recoll WebUI ativo em http://localhost:61389"
    echo "   Para expor remotamente no Tailscale com TLS: ujust remote-recoll-setup"

# 🛑 Parar o Recoll WebUI
[group('Agent Mesh')]
recoll-down:
    #!/usr/bin/env bash
    set -uo pipefail
    systemctl --user stop mesh-recoll.service
    echo "🛑 Recoll WebUI desativado."

# 🔄 Executar indexação incremental sob demanda
[group('Agent Mesh')]
recoll-index *args:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "🔍 Executando indexação incremental do workspace via Recoll..."
    INDEXER="/usr/libexec/bazzite-dx-recoll-index"
    if [[ ! -x "$INDEXER" ]]; then
        INDEXER="{{ justfile_directory() }}/../system/usr/libexec/bazzite-dx-recoll-index"
    fi
    if [[ -x "$INDEXER" ]]; then
        "$INDEXER" {{ args }}
    else
        echo "❌ Indexador não encontrado: $INDEXER"
        exit 1
    fi
    echo "✅ Indexação incremental concluída."

# 📊 Diagnóstico do Recoll
[group('Agent Mesh')]
recoll-status:
    #!/usr/bin/env bash
    set -uo pipefail
    STATE=$(systemctl --user is-active mesh-recoll.service 2>/dev/null | head -n1 || true)
    TIMER_STATE=$(systemctl --user is-active mesh-recoll-index.timer 2>/dev/null | head -n1 || true)
    printf '%-16s %s (timer noturno: %s)\n' "recoll-webui:" "${STATE:-inactive}" "${TIMER_STATE:-inactive}"
    if ss -tln 2>/dev/null | grep -q ':61389 '; then
        echo "  Porta 61389 (WebUI / JSON): ABERTA (http://127.0.0.1:61389)"
    else
        echo "  Porta 61389 (WebUI / JSON): fechada"
    fi
    if [ -d /var/srv/recoll/xapiandb ]; then
        DB_SIZE=$(du -sh /var/srv/recoll/xapiandb 2>/dev/null | cut -f1 || echo "0")
        echo "  Tamanho do Índice:          $DB_SIZE (/var/srv/recoll/xapiandb)"
    fi
    SERVE_STATE=$(/usr/libexec/bazzite-dx-serve status 61389 61389 http 2>/dev/null || echo "absent")
    printf '  %-14s %s\n' "tailscale serve:" "$SERVE_STATE"
    if [[ "$SERVE_STATE" == "ok" ]]; then
        DNS_NAME=$(tailscale status --self --json 2>/dev/null | jq -r '.Self.DNSName' | sed 's/\.$//' || true)
        echo "  URL Remota:    https://${DNS_NAME:-localhost}:61389"
    fi

# 📜 Visualizar logs do Recoll
[group('Agent Mesh')]
recoll-logs:
    journalctl --user -u mesh-recoll.service -f

# 🔒 Expor o Recoll WebUI com TLS via Tailscale Serve (:61389)
[group('Agent Mesh')]
remote-recoll-setup:
    #!/usr/bin/env bash
    set -euo pipefail
    if ! systemctl --user is-active --quiet mesh-recoll.service; then
        echo "❌ Recoll WebUI não está rodando. Rode 'ujust recoll-up' primeiro."
        exit 1
    fi
    /usr/libexec/bazzite-dx-serve ensure 61389
    DNS_NAME=$(tailscale status --self --json 2>/dev/null | jq -r '.Self.DNSName' | sed 's/\.$//')
    echo "✅ Recoll remoto pronto em: https://${DNS_NAME}:61389"

# 🔓 Remover o Recoll do Tailscale Serve
[group('Agent Mesh')]
remote-recoll-teardown:
    #!/usr/bin/env bash
    set -uo pipefail
    /usr/libexec/bazzite-dx-serve off 61389 || true
    echo "🔓 Recoll removido do Tailscale Serve."

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
    ujust i2p-status
    echo
    ujust recoll-status
    echo
    ujust vane-status
    echo
    ujust lightpanda-status
    echo
    ujust trawl-status
    echo
    ujust cdp-matrix-status

alias mesh-status := agent-mesh-status

# 🐤 Testar conectividade individual dos motores upstream no SearXNG via curl
[group('Agent Mesh')]
searxng-canary:
    #!/usr/bin/env bash
    set -uo pipefail
    SEARXNG_URL="http://127.0.0.1:61387"
    if ! curl -sf "$SEARXNG_URL/healthz" >/dev/null 2>&1; then
        echo "❌ SearXNG não está respondendo em $SEARXNG_URL. Execute 'ujust searxng-up'."
        exit 1
    fi
    echo "=== 🐤 SEARXNG ENGINES CANARY TEST ==="
    printf "%-18s | %-10s | %-8s | %s\n" "MOTOR" "STATUS" "TEMPO" "RESULTADOS"
    echo "-----------------------------------------------------------------"
    test_engine() {
        local name="$1"
        local query="${2:-linux kernel}"
        local start_ts
        start_ts=$(date +%s%3N)
        local resp
        resp=$(curl -s -m 12 -G "$SEARXNG_URL/search" --data-urlencode "q=${query}" -d "format=json" -d "engines=${name}" 2>/dev/null || echo "{}")
        local end_ts
        end_ts=$(date +%s%3N)
        local elapsed=$(( end_ts - start_ts ))
        local count
        count=$(echo "$resp" | jq -r '((.results // []) | length) + ((.infoboxes // []) | length)' 2>/dev/null || echo "0")
        local unresp
        unresp=$(echo "$resp" | jq -r 'if .unresponsive_engines then (.unresponsive_engines | map(.[0]) | join(",")) else "" end' 2>/dev/null || echo "")

        if [[ "$count" -gt 0 ]]; then
            printf "%-18s | \033[32m%-10s\033[0m | %-6dms | %d resultados\n" "$name" "OK" "$elapsed" "$count"
        elif [[ "$unresp" == *"$name"* ]]; then
            printf "%-18s | \033[31m%-10s\033[0m | %-6dms | BLOQUEADO / ERRO\n" "$name" "FALHA" "$elapsed"
        else
            printf "%-18s | \033[33m%-10s\033[0m | %-6dms | 0 resultados (vazio)\n" "$name" "AVISO" "$elapsed"
        fi
    }

    test_engine "brave"
    test_engine "google cse"
    test_engine "duckduckgo"
    test_engine "mojeek"
    test_engine "wikipedia"
    test_engine "github" "antigravity"
    test_engine "arxiv" "quantum computing"
    test_engine "openalex" "quantum computing"
    test_engine "hackernews" "antigravity"
    test_engine "lemmy posts" "linux"
    test_engine "marginalia" "personal computers"
    test_engine "mwmbl" "open source"
    echo "-----------------------------------------------------------------"
    echo "Teste canário concluído."

alias mesh-canary := searxng-canary

# 📊 Status consolidado da Matriz CDP
[group('Agent Mesh')]
cdp-matrix-status:
    #!/usr/bin/env bash
    set -uo pipefail
    echo "=== 🌐 BROWSER AUTOMATION CDP MATRIX ==="
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
    echo "Dica: Conecte seu cliente de automação, Playwright ou agente de IA via CDP: http://127.0.0.1:<porta>"
