# vim: set ft=make :
# ==============================================================================
# GROUP: Visual Studio (ComfyUI Diffusion Studio, Video DiT, LoRAs & LivePortrait)
#
# The stack runs as a ROOTLESS PODMAN QUADLET unit, not docker compose. The unit lives in
# /etc/containers/systemd/users/aistudio-visual.container (and ~/.config/containers/systemd/) and the
# systemd generator turns it into aistudio-visual.service (listening on 127.0.0.1:61384).
#
# START, NOT ENABLE — respecting the Boot Impact Policy:
# Lingering is on, which means an enabled user unit starts at boot without login and keeps
# occupying VRAM. Every recipe below therefore starts and stops on demand.
#
# MEMORY & HARDWARE ARCHITECTURE (DELL G15 RTX 3060 6GB + 64GB DDR5):
# - `--cache-classic`: Pins diffusion weights & text encoders in the 64GB DDR5 system RAM,
#   eliminating repetitive NVMe disk reloads on every generation (2x speedup).
# - `--reserve-vram 1.5`: Hard reserve to guarantee zero CUDA Out-Of-Memory crashes.
# - PERSISTENT PYTHON STORAGE: All packages live in /var/srv/comfyui/site-packages on SSD.
#   Sub-second startup with ZERO runtime pip installs.
# - User deliverables strictly follow XDG specifications:
#   - Visual (Imagens & Vídeos): $XDG_PICTURES_DIR/AI_Studio/
#   - Audio (Vozes & Músicas): $XDG_MUSIC_DIR/AI_Studio/
# ==============================================================================

# 🚀 Iniciar a suíte completa do AI Studio (Visual + Audio)
[group('AI Studio')]
aistudio-up:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "🎨 Iniciando AI Studio Visual..."
    just comfyui-up
    echo "🎙️ Iniciando AI Studio Audio..."
    just tts-up
    echo "✅ Suíte AI Studio (Visual + Audio) ativa."

# 🛑 Parar a suíte completa do AI Studio (Visual + Audio)
[group('AI Studio')]
aistudio-down:
    #!/usr/bin/env bash
    set -uo pipefail
    just comfyui-down
    just tts-down
    echo "🛑 Suíte AI Studio desativada. Recursos 100% liberados."

# 📊 Diagnóstico consolidado da suíte AI Studio (Visual + Audio + GPU)
[group('AI Studio')]
aistudio-status:
    #!/usr/bin/env bash
    set -uo pipefail
    echo "=== 🎨 AI STUDIO VISUAL ==="
    just comfyui-status
    echo ""
    echo "=== 🎙️ AI STUDIO AUDIO ==="
    just tts-status

# 📥 Baixar modelos para a suíte completa do AI Studio
[group('AI Studio')]
aistudio-pull-models:
    #!/usr/bin/env bash
    set -euo pipefail
    just comfyui-pull-models
    just tts-pull-models
    echo "✅ Todos os modelos da suíte AI Studio sincronizados."

alias aistudio := aistudio-status

# 🎨 Iniciar o AI Studio Visual (ComfyUI :61384)
[group('AI Studio Visual')]
comfyui-up:
    #!/usr/bin/env bash
    set -euo pipefail
    # Verify declarative storage existence
    if [[ ! -d /var/srv/comfyui ]]; then
        echo "❌ /var/srv/comfyui não existe — o provisionamento declarativo não rodou."
        echo "   Verifique: systemctl status bazzite-dx-groups.service"
        exit 1
    fi
    # Check GPU gates
    if ! systemctl is-active --quiet nvidia-persistenced.service; then
        echo "⚠️  nvidia-persistenced parado — a injeção CDI vai falhar."
    fi
    if [[ "$(getsebool container_use_devices 2>/dev/null || echo '--> off')" == *off ]]; then
        echo "⚠️  container_use_devices=off — o container vai receber os devices e levar Permission denied."
    fi
    systemctl --user daemon-reload
    systemctl --user start aistudio-visual.service
    echo "✅ AI Studio Visual ativo em http://localhost:61384"
    echo "   Para acessar remotamente via Tailscale com TLS: ujust remote-comfyui-setup"
    echo "   Não sobe sozinho no próximo boot — rode 'ujust comfyui-up' de novo."

alias aistudio-visual-up := comfyui-up

# 🛑 Parar o AI Studio Visual e liberar 100% da VRAM da GPU
[group('AI Studio Visual')]
comfyui-down:
    #!/usr/bin/env bash
    set -uo pipefail
    systemctl --user stop aistudio-visual.service
    echo "🛑 AI Studio Visual desativado. VRAM liberada para jogos e desktop."

alias aistudio-visual-down := comfyui-down

# 📊 Diagnóstico detalhado do AI Studio Visual, uso de VRAM na RTX 3060 e volumes
[group('AI Studio Visual')]
comfyui-status:
    #!/usr/bin/env bash
    set -uo pipefail
    echo "--- Units ---"
    printf '%-16s %s\n' "aistudio-visual" "$(systemctl --user is-active aistudio-visual.service 2>/dev/null || true)"
    echo "--- Containers ---"
    podman ps --filter name=aistudio_visual --format 'table {{{{.Names}}\t{{{{.Status}}\t{{{{.Ports}}' 2>/dev/null || true
    echo "--- API & Versões do ComfyUI ---"
    if curl -s -f http://localhost:61384/system_stats >/dev/null 2>&1; then
        curl -s http://localhost:61384/system_stats | jq '{comfyui_version: .system.comfyui_version, frontend_version: .system.required_frontend_version, pytorch: .system.pytorch_version, python: .system.python_version}' 2>/dev/null || true
    else
        echo "    (ComfyUI API não está respondendo em http://localhost:61384)"
    fi
    echo "--- GPU (NVIDIA RTX 3060) ---"
    if command -v nvidia-smi >/dev/null 2>&1; then
        nvidia-smi --query-gpu=name,memory.total,memory.used,memory.free,utilization.gpu --format=csv
    fi
    echo "--- Disco /var/srv/comfyui ---"
    du -sh /var/srv/comfyui/* 2>/dev/null || true
    echo "--- arquivos inalcançáveis pelos containers rootless ---"
    SUB_START=$(awk -F: -v u="$USER" '$1==u {print $2; exit}' /etc/subuid 2>/dev/null)
    SUB_LEN=$(awk -F: -v u="$USER" '$1==u {print $3; exit}' /etc/subuid 2>/dev/null)
    if [[ -n "${SUB_START:-}" && -n "${SUB_LEN:-}" ]]; then
        BAD=$(find /var/srv/comfyui -printf '%U %p\n' 2>/dev/null |
            awk -v me="$(id -u)" -v s="$SUB_START" -v e="$((SUB_START + SUB_LEN - 1))" \
                '$1 != me && ($1 < s || $1 > e)')
        if [[ -n "$BAD" ]]; then
            echo "$BAD" | sed 's/^/    ⚠️  uid /'
            echo "    Corrija com: sudo chown $(id -u):$(id -g) <arquivo>"
        else
            echo "    (nenhum — todos dentro de {$(id -u)} ∪ [$SUB_START, $((SUB_START + SUB_LEN - 1))])"
        fi
    fi

alias aistudio-visual-status := comfyui-status

# 📜 Visualizar logs em tempo real do AI Studio Visual
[group('AI Studio Visual')]
comfyui-logs:
    journalctl --user -u aistudio-visual.service -f --no-hostname -o cat

alias aistudio-visual-logs := comfyui-logs

# 🔄 Sincronizar o ambiente Python persistente com os toolkits declarativos
[group('AI Studio Visual')]
comfyui-sync:
    #!/usr/bin/env bash
    set -euo pipefail
    REQ_FILE="/usr/share/bazzite-dx/aistudio-visual/requirements.txt"
    if [[ ! -f "$REQ_FILE" ]]; then
        REQ_FILE="/var/srv/comfyui/requirements.txt"
    fi
    echo "📦 Sincronizando pacotes do Visual Studio para /var/srv/comfyui/site-packages..."
    mkdir -p /var/srv/comfyui/site-packages
    podman run --rm \
        -v /var/srv/comfyui/site-packages:/target:Z \
        -v "$REQ_FILE":/requirements.txt:ro,Z \
        docker.io/yanwk/comfyui-boot:cu124-slim@sha256:ea9d4add90a53ee8e4496d1281b47111e558e61eb1ee6b599888d8e776e80961 \
        pip install -q --no-warn-script-location --target /target -r /requirements.txt
    # Limpa overrides acidentais de torch para manter a aceleração CUDA da imagem base
    rm -rf /var/srv/comfyui/site-packages/torch* /var/srv/comfyui/site-packages/nvidia* /var/srv/comfyui/site-packages/functorch* /var/srv/comfyui/site-packages/cuda*
    if systemctl --user is-active --quiet aistudio-visual.service; then
        echo "🔄 Reiniciando aistudio-visual.service..."
        systemctl --user restart aistudio-visual.service
    fi
    echo "✅ Sincronização concluída com sucesso."

# ➕ Instalar ou atualizar um pacote Python no ambiente persistente do ComfyUI sem reboot
[group('AI Studio Visual')]
comfyui-install package:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "📦 Instalando {{ package }} em /var/srv/comfyui/site-packages..."
    mkdir -p /var/srv/comfyui/site-packages
    podman run --rm \
        -v /var/srv/comfyui/site-packages:/target:Z \
        docker.io/yanwk/comfyui-boot:cu124-slim@sha256:ea9d4add90a53ee8e4496d1281b47111e558e61eb1ee6b599888d8e776e80961 \
        pip install -q --no-warn-script-location --target /target "{{ package }}"
    rm -rf /var/srv/comfyui/site-packages/torch* /var/srv/comfyui/site-packages/nvidia* /var/srv/comfyui/site-packages/functorch* /var/srv/comfyui/site-packages/cuda*
    if systemctl --user is-active --quiet aistudio-visual.service; then
        systemctl --user restart aistudio-visual.service
    fi
    echo "✅ Pacote {{ package }} instalado com sucesso."

# 💻 Abrir terminal interativo diretamente no container do AI Studio Visual
[group('AI Studio Visual')]
comfyui-container-shell:
    #!/usr/bin/env bash
    set -euo pipefail
    if ! systemctl --user is-active --quiet aistudio-visual.service; then
        echo "Iniciando AI Studio Visual..."
        systemctl --user start aistudio-visual.service
    fi
    podman exec -it aistudio_visual bash

# 🎬 Animar retrato/avatar com fala e movimento facial neural via LivePortrait
[group('AI Studio Visual')]
comfyui-animate-avatar image audio output="":
    #!/usr/bin/env bash
    set -euo pipefail
    VISUAL_DIR="${XDG_PICTURES_DIR:-$HOME/Pictures}/AI_Studio"
    mkdir -p "$VISUAL_DIR"
    OUT_FILE="${output:-$VISUAL_DIR/Avatar_Animado_$(date +%s).mp4}"

    if ! systemctl --user is-active --quiet aistudio-visual.service; then
        systemctl --user start aistudio-visual.service
    fi

    echo "🎬 Executando LivePortrait na RTX 3060..."
    podman exec aistudio_visual python3 /root/user-scripts/animate_avatar.py \
        "{{ image }}" \
        "/root/ComfyUI/output/temp_animated_export.mp4" \
        "{{ audio }}"

    cp /var/srv/comfyui/ComfyUI/output/temp_animated_export.mp4 "$OUT_FILE"
    echo "✅ Vídeo animado com fala salvo em: $OUT_FILE"

alias aistudio-visual-animate := comfyui-animate-avatar

# 🔄 Atualizar o ComfyUI Core para o lançamento mais recente do Comfy-Org
[group('AI Studio Visual')]
comfyui-update:
    #!/usr/bin/env bash
    set -euo pipefail
    TARGET_DIR="/var/srv/comfyui/ComfyUI"
    if [ ! -d "$TARGET_DIR/.git" ]; then
        echo "❌ Diretório git do ComfyUI não encontrado em $TARGET_DIR"
        exit 1
    fi
    echo "📡 Buscando versões mais recentes em Comfy-Org/ComfyUI..."
    git -C "$TARGET_DIR" fetch --tags origin
    LATEST_TAG=$(git -C "$TARGET_DIR" tag --sort=-v:refname | grep -E '^v[0-9]+\.[0-9]+' | head -n 1)
    echo "→ Atualizando para a tag estável mais recente: $LATEST_TAG"
    git -C "$TARGET_DIR" checkout "$LATEST_TAG"
    if systemctl --user is-active --quiet aistudio-visual.service; then
        echo "🔄 Reiniciando serviço aistudio-visual.service..."
        systemctl --user restart aistudio-visual.service
    fi
    echo "✅ ComfyUI atualizado para $LATEST_TAG com sucesso."

# 📥 Baixar modelos recomendados dimensionados para 6 GB VRAM
[group('AI Studio Visual')]
comfyui-pull-models:
    #!/usr/bin/env bash
    set -euo pipefail
    TARGET_DIR="/var/srv/comfyui/models/checkpoints"
    mkdir -p "$TARGET_DIR"

    download_model() {
        local name="$1"
        local url="$2"
        local dest="$TARGET_DIR/$name"
        if [ -f "$dest" ] && [ "$(stat -c%s "$dest" 2>/dev/null || echo 0)" -gt 100000000 ]; then
            echo "✔ $name já está baixado."
        else
            echo "📥 Baixando $name..."
            curl -L --progress-bar "$url" -o "$dest"
            echo "✅ $name baixado com sucesso."
        fi
    }

    # 1. CyberRealistic V9 (Fotorrealismo Uncensored SOTA, 2.1 GB)
    download_model "CyberRealistic_V9_FP16.safetensors" "https://huggingface.co/cyberdelia/CyberRealistic/resolve/main/CyberRealistic_V9_FP16.safetensors"
    # 2. SD 1.5 Baseline (Padrão 2.1 GB)
    download_model "v1-5-pruned-emaonly-fp16.safetensors" "https://huggingface.co/Comfy-Org/stable-diffusion-v1-5-archive/resolve/main/v1-5-pruned-emaonly-fp16.safetensors"

    echo ""
    echo "✅ Modelos do AI Studio sincronizados em $TARGET_DIR."

alias aistudio-visual-pull-models := comfyui-pull-models

# 🧹 Purgar a VRAM imediatamente (descarrega modelos residentes da GPU)
[group('AI Studio Visual')]
comfyui-vram-purge:
    #!/usr/bin/env bash
    set -euo pipefail
    if systemctl --user is-active --quiet aistudio-visual.service; then
        systemctl --user restart aistudio-visual.service
        echo "🧹 VRAM purgada com sucesso. Nenhum modelo residente na GPU."
    else
        echo "AI Studio Visual já está inativo."
    fi

alias aistudio-visual-purge := comfyui-vram-purge

# 🗂️ Shell no namespace rootless para manipular arquivos do AI Studio
[group('AI Studio Visual')]
comfyui-shell:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "Namespace de usuário do podman para manipular /var/srv/comfyui. Saia com 'exit'."
    podman unshare bash

# 🔒 Expor o ComfyUI de forma privada e segura no tailnet via Tailscale Serve (:61384)
[group('AI Studio Visual')]
remote-comfyui-setup:
    #!/usr/bin/env bash
    set -euo pipefail
    if ! systemctl --user is-active --quiet aistudio-visual.service; then
        echo "❌ AI Studio Visual não está rodando. Rode 'ujust comfyui-up' primeiro."
        exit 1
    fi
    /usr/libexec/bazzite-dx-serve ensure 61384
    DNS_NAME=$(tailscale status --self --json | jq -r '.Self.DNSName' | sed 's/\.$//')
alias remote-ai-setup := remote-comfyui-setup
alias remote-aistudio-visual-setup := remote-comfyui-setup
alias remote-visual-setup := remote-comfyui-setup

# --- Domain & Namespace Aliases (aistudio-* / visual-*) ---
alias aistudio-visual := comfyui-status
alias aistudio-visual-sync := comfyui-sync
alias aistudio-visual-install := comfyui-install
alias aistudio-visual-update := comfyui-update
alias aistudio-visual-shell := comfyui-shell
alias aistudio-visual-container-shell := comfyui-container-shell

alias visual := comfyui-status
alias visual-up := comfyui-up
alias visual-down := comfyui-down
alias visual-status := comfyui-status
alias visual-logs := comfyui-logs
alias visual-pull-models := comfyui-pull-models
alias visual-sync := comfyui-sync
alias visual-install := comfyui-install
alias visual-update := comfyui-update
alias visual-purge := comfyui-vram-purge
alias visual-shell := comfyui-shell
alias visual-container-shell := comfyui-container-shell
alias visual-animate := comfyui-animate-avatar
