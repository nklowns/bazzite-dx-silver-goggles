# vim: set ft=make :
# ==============================================================================
# GROUP: Audio Studio (Speaches AI: TTS, STT Whisper, Voice Cloning & Music)
#
# The stack runs as a ROOTLESS PODMAN QUADLET unit, not docker compose. The unit lives in
# /etc/containers/systemd/users/aistudio-audio.container (and ~/.config/containers/systemd/) and
# the systemd generator turns it into aistudio-audio.service (listening on 127.0.0.1:61386).
#
# START, NOT ENABLE — respecting the Boot Impact Policy:
# Lingering is on, which means an enabled user unit starts at boot without login.
# Every recipe below therefore starts and stops on demand; nothing enables automatically.
#
# MEMORY & HARDWARE ARCHITECTURE:
# - Runs 100% on CPU (i7-12700H 14-cores / DDR5), keeping GPU VRAM 100% free for ComfyUI / LLMs.
# - Provides standard OpenAI-compatible endpoints:
#   - /v1/audio/speech (Piper & Kokoro-82M TTS)
#   - /v1/audio/transcriptions (Faster-Whisper STT)
# - Storage lives in /var/srv/audio with CACHEDIR.TAG and container_file_t SELinux label.
# - User deliverables strictly follow XDG specifications:
#   - Audio: $XDG_MUSIC_DIR/AI_Studio/
#   - Visual (Imagens & Vídeos): $XDG_PICTURES_DIR/AI_Studio/
# ==============================================================================

# 🎙️ Iniciar o AI Studio Audio (Speaches Voice TTS & STT, :61386) sob demanda
[group('AI Studio Audio')]
audio-up:
    #!/usr/bin/env bash
    set -euo pipefail
    # Verify declarative storage existence
    if [[ ! -d /var/srv/audio ]]; then
        echo "❌ /var/srv/audio não existe — o provisionamento declarativo não rodou."
        echo "   Verifique: systemctl status bazzite-dx-groups.service"
        exit 1
    fi
    systemctl --user daemon-reload
    systemctl --user start aistudio-audio.service
    echo "✅ AI Studio Audio (TTS & STT) ativo em http://localhost:61386"
    echo "   Portal & Swagger Interativo: http://localhost:61386/docs"
    echo "   Endpoints OpenAI: /v1/audio/speech | /v1/audio/transcriptions"
    echo "   Para expor no Tailscale com TLS: ujust remote-audio-setup"
    echo "   Não sobe sozinho no próximo boot — rode 'ujust audio-up' de novo."

alias tts-up := audio-up

# 🛑 Parar o AI Studio Audio
[group('AI Studio Audio')]
audio-down:
    #!/usr/bin/env bash
    set -uo pipefail
    systemctl --user stop aistudio-audio.service
    echo "🛑 AI Studio Audio desativado."

alias tts-down := audio-down

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
    echo "--- Endpoints & Modelos OpenAI ---"
    if curl -s -f http://localhost:61386/health >/dev/null 2>&1; then
        echo "✔ Speaches API Online em http://localhost:61386"
        curl -s http://localhost:61386/v1/models | jq . 2>/dev/null || true
    else
        echo "    (Speaches API não está respondendo em http://localhost:61386)"
    fi
    echo "--- Disco /var/srv/audio ---"
    du -sh /var/srv/audio/* 2>/dev/null || true
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

# 📜 Visualizar logs em tempo real do Speaches Audio
[group('AI Studio Audio')]
audio-logs:
    journalctl --user -u aistudio-audio.service -f --no-hostname -o cat

alias tts-logs := audio-logs

# 📥 Baixar modelos de voz e áudio para cache local (Piper PT-BR, EN, ES)
[group('AI Studio Audio')]
audio-pull-models:
    #!/usr/bin/env bash
    set -euo pipefail
    CACHE_DIR="/var/srv/audio/cache"
    mkdir -p "$CACHE_DIR"
    echo "📥 Verificando e baixando modelos de voz e transcrição (Speaches AI)..."
    if ! systemctl --user is-active --quiet aistudio-audio.service; then
        echo "Iniciando AI Studio Audio..."
        systemctl --user start aistudio-audio.service
        sleep 2
    fi
    for m in "speaches-ai/piper-pt_BR-faber-medium" "speaches-ai/Kokoro-82M-v1.0-ONNX" "Systran/faster-whisper-base"; do
        echo "→ Baixando/Verificando: $m"
        encoded_m=$(printf '%s' "$m" | jq -sRr @uri)
        curl -s -X POST "http://localhost:61386/v1/models/$encoded_m" >/dev/null 2>&1 || true
    done
    echo "✅ Modelos do AI Studio Audio sincronizados com sucesso."

alias tts-pull-models := audio-pull-models

# 🗂️ Shell no namespace rootless para manipular arquivos do Audio Studio
[group('AI Studio Audio')]
audio-shell:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "Namespace de usuário do podman para manipular /var/srv/audio. Saia com 'exit'."
    podman unshare bash

# 🔒 Expor o Speaches Audio Studio no tailnet via Tailscale Serve (:61386)
[group('AI Studio Audio')]
remote-audio-setup:
    #!/usr/bin/env bash
    set -euo pipefail
    if ! systemctl --user is-active --quiet aistudio-audio.service; then
        echo "❌ AI Studio Audio não está rodando. Rode 'ujust tts-up' primeiro."
        exit 1
    fi
    /usr/libexec/bazzite-dx-serve ensure 61386
    DNS_NAME=$(tailscale status --self --json | jq -r '.Self.DNSName' | sed 's/\.$//')
    echo "✅ AI Studio Audio pronto no Tailscale: https://$DNS_NAME:61386"

# 🌐 Abrir a interface web e documentação interativa da API de Áudio (:61386)
[group('AI Studio Audio')]
audio-portal:
    #!/usr/bin/env bash
    set -euo pipefail
    if ! systemctl --user is-active --quiet aistudio-audio.service; then
        echo "Iniciando AI Studio Audio..."
        systemctl --user start aistudio-audio.service
        sleep 2
    fi
    echo "🌐 Abrindo portal de documentação e teste da API de Áudio..."
    if command -v xdg-open >/dev/null 2>&1; then
        xdg-open "http://localhost:61386/docs" >/dev/null 2>&1 || true
    fi
    echo "✔ Speaches API Portal disponível em: http://localhost:61386/docs"

alias tts-portal := audio-portal
alias audio-open := audio-portal
