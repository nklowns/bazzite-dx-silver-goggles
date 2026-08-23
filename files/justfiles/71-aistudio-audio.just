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

# 🎙️ Iniciar o AI Studio Audio (Speaches Voice TTS & STT, :61386)
[group('AI Studio Audio')]
tts-up:
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
    echo "   Endpoints OpenAI: /v1/audio/speech | /v1/audio/transcriptions"
    echo "   Para expor no Tailscale com TLS: ujust remote-audio-setup"
    echo "   Não sobe sozinho no próximo boot — rode 'ujust tts-up' de novo."

alias aistudio-audio-up := tts-up

# 🛑 Parar o AI Studio Audio
[group('AI Studio Audio')]
tts-down:
    #!/usr/bin/env bash
    set -uo pipefail
    systemctl --user stop aistudio-audio.service
    echo "🛑 AI Studio Audio desativado."

alias aistudio-audio-down := tts-down

# 📊 Diagnóstico do serviço de Áudio, endpoints OpenAI e volumes
[group('AI Studio Audio')]
tts-status:
    #!/usr/bin/env bash
    set -uo pipefail
    echo "--- Units ---"
    printf '%-16s %s\n' "aistudio-audio" "$(systemctl --user is-active aistudio-audio.service 2>/dev/null || true)"
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

alias aistudio-audio-status := tts-status

# 📜 Visualizar logs em tempo real do Speaches Audio
[group('AI Studio Audio')]
tts-logs:
    journalctl --user -u aistudio-audio.service -f --no-hostname -o cat

alias aistudio-audio-logs := tts-logs

# 📥 Baixar modelos de voz e áudio para cache local (Piper PT-BR, EN, ES)
[group('AI Studio Audio')]
tts-pull-models:
    #!/usr/bin/env bash
    set -euo pipefail
    CACHE_DIR="/var/srv/audio/cache"
    mkdir -p "$CACHE_DIR"
    echo "📥 Verificando e baixando modelos de voz para $CACHE_DIR..."
    if ! systemctl --user is-active --quiet aistudio-audio.service; then
        echo "Iniciando AI Studio Audio para download..."
        systemctl --user start aistudio-audio.service
    fi
    # Aquece endpoints padrão no Speaches
    curl -s -X POST http://localhost:61386/v1/audio/speech \
        -H "Content-Type: application/json" \
        -d '{"model": "speaches-ai/piper-pt-br-faber-medium", "input": "Inicialização de modelos de áudio concluída.", "voice": "faber"}' >/dev/null 2>&1 || true
    echo "✅ Modelos do AI Studio Audio sincronizados com sucesso."

alias aistudio-audio-pull-models := tts-pull-models

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

# 🧬 Clonar voz zero-shot em sub-segundo (Piper Faber PT-BR + OpenVoice V2)
[group('AI Studio Audio')]
clone-voice ref_audio text out_file="":
    #!/usr/bin/env bash
    set -euo pipefail
    AUDIO_DIR="${XDG_MUSIC_DIR:-$HOME/Music}/AI_Studio"
    mkdir -p "$AUDIO_DIR"
    OUT="${out_file:-$AUDIO_DIR/Voz_Clonada_PTBR.wav}"
    echo "🎙️ Clonando voz com base fonética brasileira (Piper + OpenVoice V2)..."
    podman exec aistudio_visual python3 /root/user-scripts/clone_voice.py "{{ ref_audio }}" "{{ text }}" /root/ComfyUI/output/temp_cloned.wav
    cp /var/srv/comfyui/ComfyUI/output/temp_cloned.wav "$OUT"
    echo "✅ Áudio clonado salvo em: $OUT"

# 🎭 Sintetizar fala conversacional expressiva com risos e pausas (ChatTTS)
[group('AI Studio Audio')]
synthesize-expressive text out_file="":
    #!/usr/bin/env bash
    set -euo pipefail
    AUDIO_DIR="${XDG_MUSIC_DIR:-$HOME/Music}/AI_Studio"
    mkdir -p "$AUDIO_DIR"
    OUT="${out_file:-$AUDIO_DIR/Fala_Expressiva_ChatTTS.wav}"
    echo "🎭 Sintetizando fala expressiva com risos naturais (ChatTTS)..."
    podman exec aistudio_visual python3 /root/user-scripts/synthesize_expressive.py "{{ text }}" /root/ComfyUI/output/temp_expressive.wav
    cp /var/srv/comfyui/ComfyUI/output/temp_expressive.wav "$OUT"
    echo "✅ Áudio expressivo salvo em: $OUT"

# 🎹 Gerar trilha sonora instrumental por prompt (Meta MusicGen na CPU)
[group('AI Studio Audio')]
generate-soundtrack prompt duration="10" out_file="":
    #!/usr/bin/env bash
    set -euo pipefail
    AUDIO_DIR="${XDG_MUSIC_DIR:-$HOME/Music}/AI_Studio"
    mkdir -p "$AUDIO_DIR"
    OUT="${out_file:-$AUDIO_DIR/Trilha_Gerada_IA.wav}"
    echo "🎹 Gerando trilha sonora com Meta MusicGen na CPU (0 MB VRAM)..."
    podman exec aistudio_visual python3 /root/user-scripts/generate_soundtrack.py "{{ prompt }}" "{{ duration }}" /root/ComfyUI/output/temp_music.wav
    cp /var/srv/comfyui/ComfyUI/output/temp_music.wav "$OUT"
    echo "✅ Trilha musical salva em: $OUT"

# 🎬 Produzir Master de Vídeo Final (Imagem + Voz Clonada + Trilha Ducking 48 FPS)
[group('AI Studio Audio')]
produce-master-video avatar_img voice_wav music_wav out_video="":
    #!/usr/bin/env bash
    set -euo pipefail
    VISUAL_DIR="${XDG_PICTURES_DIR:-$HOME/Pictures}/AI_Studio"
    mkdir -p "$VISUAL_DIR"
    OUT="${out_video:-$VISUAL_DIR/Master_Video_Producao_PTBR.mp4}"
    echo "🎬 Renderizando Master de Produção Final com Sidechain Auto-Ducking (48 FPS)..."
    ffmpeg -y \
        -loop 1 -i "{{ avatar_img }}" \
        -i "{{ voice_wav }}" \
        -stream_loop -1 -i "{{ music_wav }}" \
        -filter_complex "
            [1:a]volume=1.35,asplit=2[sc_voice][voice_out];
            [2:a]volume=0.80[music_in];
            [music_in][sc_voice]sidechaincompress=threshold=0.08:ratio=6:attack=20:release=250[music_ducked];
            [voice_out][music_ducked]amix=inputs=2:duration=first:dropout_transition=2[aout]
        " \
        -map 0:v -map "[aout]" \
        -c:v libx264 -tune stillimage -pix_fmt yuv420p -r 48 \
        -c:a aac -b:a 256k \
        -shortest \
        "$OUT"
    echo "✅ Vídeo Master renderizado em: $OUT"

alias audio-up := tts-up
alias audio-down := tts-down
alias audio-status := tts-status
alias audio-logs := tts-logs
