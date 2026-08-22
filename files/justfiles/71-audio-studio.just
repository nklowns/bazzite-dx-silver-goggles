# 🎙️ AI Audio Studio (TTS, Multi-Language Voice Cloning, MusicGen & Faster-Whisper)

# Iniciar o serviço de Voz / TTS e Clonagem (:61386)
[group('Audio Studio')]
tts-up:
    #!/usr/bin/env bash
    set -euo pipefail
    [ -x /usr/libexec/audio-studio-bootstrap-env ] && /usr/libexec/audio-studio-bootstrap-env
    systemctl --user daemon-reload
    systemctl --user start voice-tts.service
    echo "✅ AI Voice & TTS Service ativo. Endpoint local: http://localhost:61386"
    echo "   Para expor no Tailscale com TLS: ujust remote-audio-setup"

# 🛑 Parar o serviço de Voz / TTS
[group('Audio Studio')]
tts-down:
    #!/usr/bin/env bash
    set -uo pipefail
    systemctl --user stop voice-tts.service
    echo "🛑 AI Voice & TTS Service desativado."

# 📊 Diagnóstico do serviço de Voz / TTS
[group('Audio Studio')]
tts-status:
    #!/usr/bin/env bash
    set -uo pipefail
    echo "== Voice & TTS Service Status =="
    systemctl --user status voice-tts.service --no-pager -l || true
    echo ""
    if curl -s -f http://localhost:61386/health >/dev/null 2>&1; then
        curl -s http://localhost:61386/health | jq . 2>/dev/null || curl -s http://localhost:61386/health
    else
        echo "Voice API não está respondendo em http://localhost:61386"
    fi

# Iniciar o serviço de Música & Stems (:61387)
[group('Audio Studio')]
music-up:
    #!/usr/bin/env bash
    set -euo pipefail
    [ -x /usr/libexec/audio-studio-bootstrap-env ] && /usr/libexec/audio-studio-bootstrap-env
    systemctl --user daemon-reload
    systemctl --user start audio-music.service
    echo "✅ AI Music & Stems Service ativo. Endpoint local: http://localhost:61387"

# 🛑 Parar o serviço de Música & Stems
[group('Audio Studio')]
music-down:
    #!/usr/bin/env bash
    set -uo pipefail
    systemctl --user stop audio-music.service
    echo "🛑 AI Music & Stems Service desativado."

# 📊 Diagnóstico do serviço de Música
[group('Audio Studio')]
music-status:
    #!/usr/bin/env bash
    set -uo pipefail
    systemctl --user status audio-music.service --no-pager -l || true

# Iniciar o serviço de Transcrição / Faster-Whisper (:61388)
[group('Audio Studio')]
whisper-up:
    #!/usr/bin/env bash
    set -euo pipefail
    [ -x /usr/libexec/audio-studio-bootstrap-env ] && /usr/libexec/audio-studio-bootstrap-env
    systemctl --user daemon-reload
    systemctl --user start voice-stt.service
    echo "✅ Faster-Whisper STT Service ativo. Endpoint local: http://localhost:61388"

# 🛑 Parar o serviço de Transcrição / Faster-Whisper
[group('Audio Studio')]
whisper-down:
    #!/usr/bin/env bash
    set -uo pipefail
    systemctl --user stop voice-stt.service
    echo "🛑 Faster-Whisper STT Service desativado."

# 📊 Diagnóstico do serviço de Transcrição
[group('Audio Studio')]
whisper-status:
    #!/usr/bin/env bash
    set -uo pipefail
    systemctl --user status voice-stt.service --no-pager -l || true

# 🚀 Iniciar todos os 3 microserviços de Áudio simultaneamente
[group('Audio Studio')]
audio-all-up:
    #!/usr/bin/env bash
    set -euo pipefail
    [ -x /usr/libexec/audio-studio-bootstrap-env ] && /usr/libexec/audio-studio-bootstrap-env
    systemctl --user daemon-reload
    systemctl --user start voice-tts.service audio-music.service voice-stt.service
    echo "✅ Todos os 3 microserviços de Áudio estão ativos:"
    echo "   - 🗣️ TTS & Clonagem: http://localhost:61386"
    echo "   - 🎵 MusicGen & Stems: http://localhost:61387"
    echo "   - 👂 Faster-Whisper: http://localhost:61388"

# 🛑 Parar todos os 3 microserviços de Áudio
[group('Audio Studio')]
audio-all-down:
    #!/usr/bin/env bash
    set -uo pipefail
    systemctl --user stop voice-tts.service audio-music.service voice-stt.service
    echo "🛑 Todos os serviços de Áudio foram desativados."

# 🗣️ Iniciar chat conversacional por voz com o modelo MoE (Microfone -> MoE -> Alto-falante)
[group('Audio Studio')]
voice-chat *args:
    #!/usr/bin/env bash
    set -euo pipefail
    TARGET="/var/srv/audio/app/voice_chat.py"
    [ -f "$TARGET" ] || TARGET="/var/srv/comfyui/audio/app/voice_chat.py"
    [ -f "$TARGET" ] || TARGET="/usr/share/bazzite-dx/audio/voice_chat.py"
    python3 "$TARGET" {{ args }}

# 🔒 Expor toda a pilha de Áudio no tailnet via Tailscale Serve
[group('Audio Studio')]
remote-audio-setup:
    #!/usr/bin/env bash
    set -euo pipefail
    /usr/libexec/bazzite-dx-serve ensure 61386
    /usr/libexec/bazzite-dx-serve ensure 61387
    /usr/libexec/bazzite-dx-serve ensure 61388
    DNS_NAME=$(tailscale status --self --json | jq -r '.Self.DNSName' | sed 's/\.$//')
    echo "✅ AI Audio Studio pronto no Tailscale:"
    echo "   - 🗣️ TTS / Clonagem: https://$DNS_NAME:61386"
    echo "   - 🎵 Música / Stems: https://$DNS_NAME:61387"
    echo "   - 👂 Transcrição: https://$DNS_NAME:61388"
