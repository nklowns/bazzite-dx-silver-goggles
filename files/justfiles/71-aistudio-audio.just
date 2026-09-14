# vim: set ft=make :
# ==============================================================================
# GROUP: Audio Studio (VoiceStudio / OmniVoice: TTS, STT Whisper, Voice Cloning & Music)
#
# The stack runs as a ROOTLESS PODMAN QUADLET unit, not docker compose. The unit lives in
# /etc/containers/systemd/users/aistudio-audio.container (and ~/.config/containers/systemd/) and
# the systemd generator turns it into aistudio-audio.service (listening on 127.0.0.1:61386).
#
# START, NOT ENABLE — respecting the Boot Impact Policy:
# Lingering is on, which means an enabled user unit starts at boot without login.
# Every recipe below therefore starts and stops on demand; nothing enables automatically.
#
# MEMORY & HARDWARE ARCHITECTURE (DELL G15 RTX 3060 6GB + 64GB DDR5):
# - Accelerated via NVIDIA CUDA on RTX 3060 Mobile GPU (CDI).
# - Smart memory offloading to the 64GB DDR5 system RAM for large language models.
# - Provides standard OpenAI-compatible endpoints:
#   - /v1/audio/speech (16 TTS engines)
#   - /v1/audio/transcriptions (11 ASR Whisper engines)
# - Storage lives in /var/srv/audio with CACHEDIR.TAG and container_file_t SELinux label.
# - User deliverables strictly follow XDG specifications:
#   - Audio: $XDG_MUSIC_DIR/AI_Studio/ (mounted directly as /app/omnivoice_data/output)
#   - Visual: $XDG_PICTURES_DIR/AI_Studio/
# ==============================================================================

# 🎙️ Iniciar o AI Studio Audio (VoiceStudio & OpenAI API, :61386) sob demanda
[group('AI Studio Audio')]
audio-up:
    #!/usr/bin/env bash
    set -euo pipefail
    # Verify declarative storage existence
    if [[ ! -d /var/srv/audio/data ]]; then
        echo "❌ /var/srv/audio/data não existe — o provisionamento declarativo não rodou."
        echo "   Verifique: systemctl status bazzite-dx-groups.service"
        exit 1
    fi
    # Ensure user deliverables directory exists
    MUSIC_DIR="${XDG_MUSIC_DIR:-$HOME/Music}/AI_Studio"
    mkdir -p "$MUSIC_DIR"

    # Check GPU gates
    if ! systemctl is-active --quiet nvidia-persistenced.service; then
        echo "⚠️  nvidia-persistenced parado — a injeção CDI vai falhar."
    fi
    if [[ "$(getsebool container_use_devices 2>/dev/null || echo '--> off')" == *off ]]; then
        echo "⚠️  container_use_devices=off — o container vai receber os devices e levar Permission denied."
    fi

    systemctl --user daemon-reload
    systemctl --user start aistudio-audio.service
    echo "✅ AI Studio Audio (VoiceStudio) ativo em http://localhost:61386"
    echo "   Web Studio & DAW: http://localhost:61386"
    echo "   API Swagger: http://localhost:61386/docs"
    echo "   Endpoints OpenAI: /v1/audio/speech | /v1/audio/transcriptions"
    echo "   Deliverables salvos em: $MUSIC_DIR"
    echo "   Para expor no Tailscale com TLS: ujust remote-audio-setup"
    echo "   Não sobe sozinho no próximo boot — rode 'ujust audio-up' de novo."

alias tts-up := audio-up

# 🛑 Parar o AI Studio Audio e liberar VRAM da GPU
[group('AI Studio Audio')]
audio-down:
    #!/usr/bin/env bash
    set -uo pipefail
    systemctl --user stop aistudio-audio.service
    echo "🛑 AI Studio Audio (VoiceStudio) desativado. VRAM liberada para jogos e desktop."

alias tts-down := audio-down

# 🧹 Purgar modelos da GPU e liberar 100% da VRAM sem manter pesos residentes
[group('AI Studio Audio')]
audio-purge:
    #!/usr/bin/env bash
    set -euo pipefail
    if systemctl --user is-active --quiet aistudio-audio.service; then
        systemctl --user restart aistudio-audio.service
        echo "🧹 VRAM do VoiceStudio purgada com sucesso. Nenhum modelo residente na GPU."
    else
        echo "AI Studio Audio já está inativo."
    fi

alias tts-vram-purge := audio-purge

# ⚡ Habilitar o AI Studio Audio para iniciar automaticamente no boot (Ative e esqueça)
[group('AI Studio Audio')]
audio-enable-boot:
    #!/usr/bin/env bash
    set -euo pipefail
    DROPIN_DIR="$HOME/.config/containers/systemd/aistudio-audio.container.d"
    mkdir -p "$DROPIN_DIR"
    printf "[Install]\nWantedBy=default.target\n" > "$DROPIN_DIR/10-autostart.conf"
    systemctl --user daemon-reload
    just audio-up
    echo "⚡ AI Studio Audio habilitado para iniciar automaticamente no boot!"

alias tts-enable-boot := audio-enable-boot

# 🔌 Desabilitar o AI Studio Audio da inicialização automática do boot
[group('AI Studio Audio')]
audio-disable-boot:
    #!/usr/bin/env bash
    set -uo pipefail
    rm -f "$HOME/.config/containers/systemd/aistudio-audio.container.d/10-autostart.conf"
    rmdir "$HOME/.config/containers/systemd/aistudio-audio.container.d" 2>/dev/null || true
    systemctl --user daemon-reload
    echo "🔌 AI Studio Audio removido do boot automático. Use 'ujust audio-up' quando precisar."

alias tts-disable-boot := audio-disable-boot

# 📊 Diagnóstico do serviço de Áudio, endpoints OpenAI e volumes
[group('AI Studio Audio')]
audio-status:
    #!/usr/bin/env bash
    set -uo pipefail
    echo "--- Units ---"
    STATE=$(systemctl --user is-active aistudio-audio.service 2>/dev/null || true)
    if [[ -f "$HOME/.config/containers/systemd/aistudio-audio.container.d/10-autostart.conf" ]]; then
        BOOT="enabled"
    else
        BOOT="disabled"
    fi
    printf '%-16s %s (boot: %s)\n' "aistudio-audio" "${STATE:-inactive}" "$BOOT"
    echo "--- Containers ---"
    podman ps --filter name=aistudio_audio --format 'table {{{{.Names}}\t{{{{.Status}}\t{{{{.Ports}}' 2>/dev/null || true
    echo "--- Portas & Tailscale Serve ---"
    if ss -tln 2>/dev/null | grep -q ':61386 '; then
        echo "  Porta 61386: ABERTA (http://127.0.0.1:61386)"
    else
        echo "  Porta 61386: fechada"
    fi
    SERVE_STATE=$(/usr/libexec/bazzite-dx-serve status 61386 61386 http 2>/dev/null || echo "absent")
    printf '  %-14s %s\n' "tailscale serve:" "$SERVE_STATE"
    if [[ "$SERVE_STATE" == "ok" ]]; then
        DNS_NAME=$(tailscale status --self --json 2>/dev/null | jq -r '.Self.DNSName' | sed 's/\.$//' || true)
        echo "  URL Remota:    https://${DNS_NAME:-localhost}:61386"
    fi
    echo "--- Endpoints & Modelos OpenAI ---"
    if curl -s -f http://localhost:61386/health >/dev/null 2>&1; then
        echo "✔ VoiceStudio API Online em http://localhost:61386"
        DEVICE=$(curl -s http://localhost:61386/health | jq -r '.device // "unknown"')
        VERSION=$(curl -s http://localhost:61386/health | jq -r '.version // "unknown"')
        echo "  Dispositivo: $DEVICE | Versão: $VERSION"
        curl -s http://localhost:61386/v1/audio/voices | jq -r '.voices[]? | "  - \(.name) (\(.voice_id))"' 2>/dev/null | head -n 8 || true
    else
        echo "    (VoiceStudio API não está respondendo em http://localhost:61386)"
    fi
    echo "--- Disco /var/srv/audio ---"
    du -sh /var/srv/audio/* 2>/dev/null || true
    echo "--- Disco XDG Deliverables (${XDG_MUSIC_DIR:-$HOME/Music}/AI_Studio) ---"
    du -sh "${XDG_MUSIC_DIR:-$HOME/Music}/AI_Studio" 2>/dev/null || true
    echo "--- arquivos inalcançáveis pelos containers rootless ---"
    SUB_START=$(awk -F: -v u="$USER" '$1==u {print $2; exit}' /etc/subuid 2>/dev/null)
    SUB_LEN=$(awk -F: -v u="$USER" '$1==u {print $3; exit}' /etc/subuid 2>/dev/null)
    if [[ -n "${SUB_START:-}" && -n "${SUB_LEN:-}" ]]; then
        BAD=$(find /var/srv/audio -printf '%U %p\n' 2>/dev/null |
            awk -v me="$(id -u)" -v s="$SUB_START" -v e="$((SUB_START + SUB_LEN - 1))" \
                '$1 != me && ($1 < s || $1 > e)')
        if [[ -n "$BAD" ]]; then
            echo "$BAD" | sed 's/^/    ⚠️  uid /'
            echo "    Corrija com: sudo chown $(id -u):$(id -g) <arquivo>"
        else
            echo "    (nenhum — todos dentro de {$(id -u)} ∪ [$SUB_START, $((SUB_START + SUB_LEN - 1))])"
        fi
    fi

alias tts-status := audio-status

# 📜 Visualizar logs em tempo real do VoiceStudio
[group('AI Studio Audio')]
audio-logs:
    journalctl --user -u aistudio-audio.service -f --no-hostname -o cat

alias tts-logs := audio-logs

# 📥 Baixar modelos de voz e áudio para cache local
[group('AI Studio Audio')]
audio-pull-models:
    #!/usr/bin/env bash
    set -euo pipefail
    CACHE_DIR="/var/srv/audio/data/huggingface"
    mkdir -p "$CACHE_DIR"
    echo "📥 Verificando e aquecendo modelos de áudio do VoiceStudio..."
    if ! systemctl --user is-active --quiet aistudio-audio.service; then
        echo "Iniciando AI Studio Audio..."
        systemctl --user start aistudio-audio.service
        sleep 3
    fi
    echo "✅ VoiceStudio ativo. Modelos sob demanda são gerenciados via Web UI (:61386)."

alias tts-pull-models := audio-pull-models

# 🗂️ Shell no namespace rootless para manipular arquivos do Audio Studio
[group('AI Studio Audio')]
audio-shell:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "Namespace de usuário do podman para manipular /var/srv/audio. Saia com 'exit'."
    podman unshare bash

# 🔒 Expor o VoiceStudio no tailnet via Tailscale Serve (:61386)
[group('AI Studio Audio')]
remote-audio-setup:
    #!/usr/bin/env bash
    set -euo pipefail
    if ! systemctl --user is-active --quiet aistudio-audio.service; then
        echo "❌ AI Studio Audio não está rodando. Rode 'ujust audio-up' primeiro."
        exit 1
    fi
    /usr/libexec/bazzite-dx-serve ensure 61386
    DNS_NAME=$(tailscale status --self --json 2>/dev/null | jq -r '.Self.DNSName' | sed 's/\.$//' || true)
    echo "✅ VoiceStudio pronto no Tailscale: https://${DNS_NAME}:61386"

# 🔓 Remover o VoiceStudio do Tailscale Serve
[group('AI Studio Audio')]
remote-audio-teardown:
    #!/usr/bin/env bash
    set -uo pipefail
    /usr/libexec/bazzite-dx-serve off 61386 || true
    echo "🔓 VoiceStudio removido do Tailscale Serve."

# 🌐 Exibir status de acesso do VoiceStudio e endpoints da API (:61386)
[group('AI Studio Audio')]
audio-portal:
    #!/usr/bin/env bash
    set -euo pipefail
    if ! systemctl --user is-active --quiet aistudio-audio.service; then
        echo "Iniciando AI Studio Audio..."
        systemctl --user start aistudio-audio.service
        sleep 2
    fi
    echo "✔ VoiceStudio Web UI disponível em: http://localhost:61386"
    echo "  Docs & Swagger API: http://localhost:61386/docs"
    SERVE_STATE=$(/usr/libexec/bazzite-dx-serve status 61386 61386 http 2>/dev/null || echo "absent")
    if [[ "$SERVE_STATE" == "ok" ]]; then
        DNS_NAME=$(tailscale status --self --json 2>/dev/null | jq -r '.Self.DNSName' | sed 's/\.$//' || true)
        echo "  Acesso Remoto Seguro: https://${DNS_NAME:-localhost}:61386"
    else
        echo "  Para acessar remotamente via Tailscale com TLS: ujust remote-audio-setup"
    fi

alias tts-portal := audio-portal
alias audio-open := audio-portal
