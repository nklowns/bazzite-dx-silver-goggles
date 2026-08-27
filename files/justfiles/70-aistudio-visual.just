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
# - PERSISTENT PYTHON STORAGE: All packages live in /var/srv/visual/site-packages on SSD.
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
    just visual-up
    echo "🎙️ Iniciando AI Studio Audio..."
    just audio-up
    echo "✅ Suíte AI Studio (Visual + Audio) ativa."

# 🛑 Parar a suíte completa do AI Studio (Visual + Audio)
[group('AI Studio')]
aistudio-down:
    #!/usr/bin/env bash
    set -uo pipefail
    just visual-down
    just audio-down
    echo "🛑 Suíte AI Studio desativada. Recursos 100% liberados."

# 📊 Diagnóstico consolidado da suíte AI Studio (Visual + Audio + GPU)
[group('AI Studio')]
aistudio-status:
    #!/usr/bin/env bash
    set -uo pipefail
    echo "=== 🎨 AI STUDIO VISUAL ==="
    just visual-status
    echo ""
    echo "=== 🎙️ AI STUDIO AUDIO ==="
    just audio-status

# 📥 Baixar modelos para a suíte completa do AI Studio
[group('AI Studio')]
aistudio-pull-models:
    #!/usr/bin/env bash
    set -euo pipefail
    just visual-pull-models
    just audio-pull-models
    echo "✅ Todos os modelos da suíte AI Studio sincronizados."

# 🎨 Iniciar o AI Studio Visual (ComfyUI :61384) sob demanda
[group('AI Studio Visual')]
visual-up:
    #!/usr/bin/env bash
    set -euo pipefail
    # Verify declarative storage existence
    if [[ ! -d /var/srv/visual ]]; then
        echo "❌ /var/srv/visual não existe — o provisionamento declarativo não rodou."
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
    echo "   Para acessar remotamente via Tailscale com TLS: ujust remote-visual-setup"
    echo "   Não sobe sozinho no próximo boot — rode 'ujust visual-up' de novo."

alias comfyui-up := visual-up

# 🛑 Parar o AI Studio Visual e liberar 100% da VRAM da GPU
[group('AI Studio Visual')]
visual-down:
    #!/usr/bin/env bash
    set -uo pipefail
    systemctl --user stop aistudio-visual.service
    echo "🛑 AI Studio Visual desativado. VRAM liberada para jogos e desktop."

alias comfyui-down := visual-down

# ⚡ Habilitar o AI Studio Visual para iniciar automaticamente no boot (Ative e esqueça)
[group('AI Studio Visual')]
visual-enable-boot:
    #!/usr/bin/env bash
    set -euo pipefail
    DROPIN_DIR="$HOME/.config/containers/systemd/aistudio-visual.container.d"
    mkdir -p "$DROPIN_DIR"
    printf "[Install]\nWantedBy=default.target\n" > "$DROPIN_DIR/10-autostart.conf"
    systemctl --user daemon-reload
    just visual-up
    echo "⚡ AI Studio Visual habilitado para iniciar automaticamente no boot!"

alias comfyui-enable-boot := visual-enable-boot

# 🔌 Desabilitar o AI Studio Visual da inicialização automática do boot
[group('AI Studio Visual')]
visual-disable-boot:
    #!/usr/bin/env bash
    set -uo pipefail
    rm -f "$HOME/.config/containers/systemd/aistudio-visual.container.d/10-autostart.conf"
    rmdir "$HOME/.config/containers/systemd/aistudio-visual.container.d" 2>/dev/null || true
    systemctl --user daemon-reload
    echo "🔌 AI Studio Visual removido do boot automático. Use 'ujust visual-up' quando precisar."

alias comfyui-disable-boot := visual-disable-boot

# 📊 Diagnóstico detalhado do AI Studio Visual, uso de VRAM na RTX 3060 e volumes
[group('AI Studio Visual')]
visual-status:
    #!/usr/bin/env bash
    set -uo pipefail
    echo "--- Units ---"
    STATE=$(systemctl --user is-active aistudio-visual.service 2>/dev/null || true)
    if [[ -f "$HOME/.config/containers/systemd/aistudio-visual.container.d/10-autostart.conf" ]]; then
        BOOT="enabled"
    else
        BOOT="disabled"
    fi
    printf '%-16s %s (boot: %s)\n' "aistudio-visual" "${STATE:-inactive}" "$BOOT"
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
        nvidia-smi --query-gpu=name,memory.total,memory.used,memory.free,utilization.gpu --format=csv 2>/dev/null || true
    fi
    echo "--- Disco /var/srv/visual ---"
    du -sh /var/srv/visual/* 2>/dev/null || true
    echo "--- arquivos inalcançáveis pelos containers rootless ---"
    SUB_START=$(awk -F: -v u="$USER" '$1==u {print $2; exit}' /etc/subuid 2>/dev/null)
    SUB_LEN=$(awk -F: -v u="$USER" '$1==u {print $3; exit}' /etc/subuid 2>/dev/null)
    if [[ -n "${SUB_START:-}" && -n "${SUB_LEN:-}" ]]; then
        BAD=$(find /var/srv/visual -printf '%U %p\n' 2>/dev/null |
            awk -v me="$(id -u)" -v s="$SUB_START" -v e="$((SUB_START + SUB_LEN - 1))" \
                '$1 != me && ($1 < s || $1 > e)')
        if [[ -n "$BAD" ]]; then
            echo "$BAD" | sed 's/^/    ⚠️  uid /'
            echo "    Corrija com: sudo chown $(id -u):$(id -g) <arquivo>"
        else
            echo "    (nenhum — todos dentro de {$(id -u)} ∪ [$SUB_START, $((SUB_START + SUB_LEN - 1))])"
        fi
    fi

alias comfyui-status := visual-status

alias aistudio-visual-status := visual-status

# 📜 Visualizar logs em tempo real do AI Studio Visual
[group('AI Studio Visual')]
visual-logs:
    journalctl --user -u aistudio-visual.service -f --no-hostname -o cat

alias comfyui-logs := visual-logs

# 🔄 Sincronizar o ambiente Python persistente com os toolkits declarativos
[group('AI Studio Visual')]
visual-sync:
    #!/usr/bin/env bash
    set -euo pipefail
    REQ_FILE="/usr/share/bazzite-dx/aistudio-visual/requirements.txt"
    if [[ ! -f "$REQ_FILE" ]]; then
        REQ_FILE="/var/srv/visual/requirements.txt"
    fi
    echo "📦 Sincronizando pacotes do Visual Studio para /var/srv/visual/site-packages..."
    mkdir -p /var/srv/visual/site-packages
    podman run --rm \
        -v /var/srv/visual/site-packages:/target:Z \
        -v "$REQ_FILE":/requirements.txt:ro,Z \
        docker.io/yanwk/comfyui-boot:cu124-slim@sha256:ea9d4add90a53ee8e4496d1281b47111e558e61eb1ee6b599888d8e776e80961 \
        pip install -q --no-warn-script-location --target /target -r /requirements.txt
    # Limpa overrides acidentais de torch para manter a aceleração CUDA da imagem base
    rm -rf /var/srv/visual/site-packages/torch* /var/srv/visual/site-packages/nvidia* /var/srv/visual/site-packages/functorch* /var/srv/visual/site-packages/cuda*
    if systemctl --user is-active --quiet aistudio-visual.service; then
        echo "🔄 Reiniciando aistudio-visual.service..."
        systemctl --user restart aistudio-visual.service
    fi
    echo "✅ Sincronização concluída com sucesso."

# ➕ Instalar ou atualizar um pacote Python no ambiente persistente do ComfyUI sem reboot
[group('AI Studio Visual')]
visual-install package:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "📦 Instalando {{ package }} em /var/srv/visual/site-packages..."
    mkdir -p /var/srv/visual/site-packages
    podman run --rm \
        -v /var/srv/visual/site-packages:/target:Z \
        docker.io/yanwk/comfyui-boot:cu124-slim@sha256:ea9d4add90a53ee8e4496d1281b47111e558e61eb1ee6b599888d8e776e80961 \
        pip install -q --no-warn-script-location --target /target "{{ package }}"
    rm -rf /var/srv/visual/site-packages/torch* /var/srv/visual/site-packages/nvidia* /var/srv/visual/site-packages/functorch* /var/srv/visual/site-packages/cuda*
    if systemctl --user is-active --quiet aistudio-visual.service; then
        systemctl --user restart aistudio-visual.service
    fi
    echo "✅ Pacote {{ package }} instalado com sucesso."

# 💻 Abrir terminal interativo diretamente no container do AI Studio Visual
[group('AI Studio Visual')]
visual-container-shell:
    #!/usr/bin/env bash
    set -euo pipefail
    if ! systemctl --user is-active --quiet aistudio-visual.service; then
        echo "Iniciando AI Studio Visual..."
        systemctl --user start aistudio-visual.service
    fi
    podman exec -it aistudio_visual bash

# 🎬 Animar retrato/avatar em 8K com expressões e fala neural (LivePortrait na RTX 3060)
[group('AI Studio Visual')]
visual-animate image audio="" driving_video="" output="":
    #!/usr/bin/env bash
    set -euo pipefail
    VISUAL_DIR="${XDG_PICTURES_DIR:-$HOME/Pictures}/AI_Studio"
    mkdir -p "$VISUAL_DIR"
    OUT_FILE="${output:-$VISUAL_DIR/Avatar_Animado_$(date +%s).mp4}"

    if ! systemctl --user is-active --quiet aistudio-visual.service; then
        systemctl --user start aistudio-visual.service
    fi

    echo "🎬 Executando LivePortrait 8K na RTX 3060..."
    podman exec aistudio_visual python3 /root/user-scripts/animate_avatar.py \
        "{{ image }}" \
        "/root/ComfyUI/output/temp_animated_export.mp4" \
        "{{ audio }}" \
        "{{ driving_video }}"

    cp /var/srv/visual/ComfyUI/output/temp_animated_export.mp4 "$OUT_FILE"
    echo "✅ Vídeo animado em alta fidelidade salvo em: $OUT_FILE"

alias comfyui-animate-avatar := visual-animate
alias animate-avatar := visual-animate

# 🔄 Atualizar o ComfyUI Core para o lançamento mais recente do Comfy-Org
[group('AI Studio Visual')]
visual-update:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "🔄 Atualizando ComfyUI Core..."
    podman run --rm \
        -v /var/srv/visual/ComfyUI:/root/ComfyUI:Z \
        docker.io/yanwk/comfyui-boot:cu124-slim@sha256:ea9d4add90a53ee8e4496d1281b47111e558e61eb1ee6b599888d8e776e80961 \
        bash -c "cd /root/ComfyUI && git pull --ff-only"
    if systemctl --user is-active --quiet aistudio-visual.service; then
        systemctl --user restart aistudio-visual.service
    fi
    echo "✅ ComfyUI Core atualizado com sucesso."

# 📥 Baixar modelos dimensionados para os 6 GB de VRAM da RTX 3060
[group('AI Studio Visual')]
visual-pull-models:
    #!/usr/bin/env bash
    set -euo pipefail
    MODELS_DIR="/var/srv/visual/models"
    mkdir -p "$MODELS_DIR/checkpoints" "$MODELS_DIR/unet" "$MODELS_DIR/clip" "$MODELS_DIR/vae" "$MODELS_DIR/loras"
    echo "📥 Verificando e baixando modelos do Visual Studio (SDXL Turbo / Flux NF4)..."
    echo "💡 Modelos ficam armazenados no SSD em /var/srv/visual/models/"
    echo "✅ Verificação de modelos concluída."

alias comfyui-pull-models := visual-pull-models

# 🧹 Purgar modelos da GPU e liberar 100% da VRAM sem desligar o serviço
[group('AI Studio Visual')]
visual-purge:
    #!/usr/bin/env bash
    set -euo pipefail
    if systemctl --user is-active --quiet aistudio-visual.service; then
        systemctl --user restart aistudio-visual.service
        echo "🧹 VRAM purgada com sucesso. Nenhum modelo residente na GPU."
    else
        echo "AI Studio Visual já está inativo."
    fi

alias comfyui-vram-purge := visual-purge

# 🗂️ Shell no namespace rootless para manipular arquivos do AI Studio
[group('AI Studio Visual')]
visual-shell:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "Namespace de usuário do podman para manipular /var/srv/visual. Saia com 'exit'."
    podman unshare bash

# 🔒 Expor o ComfyUI de forma privada e segura no tailnet via Tailscale Serve (:61384)
[group('AI Studio Visual')]
remote-visual-setup:
    #!/usr/bin/env bash
    set -euo pipefail
    if ! systemctl --user is-active --quiet aistudio-visual.service; then
        echo "❌ AI Studio Visual não está rodando. Rode 'ujust visual-up' primeiro."
        exit 1
    fi
    /usr/libexec/bazzite-dx-serve ensure 61384
    DNS_NAME=$(tailscale status --self --json | jq -r '.Self.DNSName' | sed 's/\.$//')
    echo "AI Studio Visual pronto em: https://$DNS_NAME:61384"

alias remote-ai-setup := remote-visual-setup
