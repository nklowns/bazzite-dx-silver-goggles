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
# - `--reserve-vram 1.0`: Balanced headroom protecting against HDMI/desktop scanout overhead.
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
    systemctl --user restart aistudio-visual.service
    echo "⚡ AI Studio Visual configurado para iniciar automaticamente com a sessão do usuário."

alias comfyui-enable-boot := visual-enable-boot

# 🔌 Desabilitar o AI Studio Visual do boot
[group('AI Studio Visual')]
visual-disable-boot:
    #!/usr/bin/env bash
    set -uo pipefail
    rm -f "$HOME/.config/containers/systemd/aistudio-visual.container.d/10-autostart.conf"
    rmdir "$HOME/.config/containers/systemd/aistudio-visual.container.d" 2>/dev/null || true
    systemctl --user daemon-reload
    echo "🔌 AI Studio Visual removido da inicialização automática."

alias comfyui-disable-boot := visual-disable-boot

# 📊 Diagnóstico das units e portas do AI Studio Visual
[group('AI Studio Visual')]
visual-status:
    #!/usr/bin/env bash
    set -uo pipefail
    echo "=== AI Studio Visual ==="
    STATE=$(systemctl --user is-active aistudio-visual.service 2>/dev/null || true)
    if [[ -f "$HOME/.config/containers/systemd/aistudio-visual.container.d/10-autostart.conf" ]]; then
        BOOT="enabled"
    else
        BOOT="disabled"
    fi
    printf '%-16s %s (boot: %s)\n' "aistudio-visual" "${STATE:-inactive}" "$BOOT"
    echo
    echo "--- Portas locais ---"
    for port in 61384; do
        if ss -tlnp 2>/dev/null | grep -q ":${port} "; then
            printf '  :%-5d ABERTA\n' "$port"
        else
            printf '  :%-5d fechada\n' "$port"
        fi
    done
    echo
    echo "--- Disco /var/srv/visual ---"
    du -sh /var/srv/visual/* 2>/dev/null || true
    echo
    echo "--- Permissões ---"
    if [[ -d /var/srv/visual ]]; then
        BAD=$(find /var/srv/visual -printf '%U %p\n' 2>/dev/null |
            awk -v uid="$UID" '$1 != uid && $1 != 0 { count++ } END { print count+0 }')
        if (( BAD > 0 )); then
            echo "  ⚠️  ${BAD} arquivo(s) em /var/srv/visual não pertencem ao seu UID ou ao container."
            echo "     Isso pode quebrar o ComfyUI. Corrija com: ujust visual-fix-perms"
        else
            echo "  ✔ UID ownership íntegra em /var/srv/visual."
        fi
    fi
    echo
    echo "--- Tailscale Serve (Visual) ---"
    if command -v tailscale >/dev/null 2>&1; then
        tailscale serve status 2>&1 | grep -E "61384|comfyui|visual" || echo "  (nenhum endpoint ativo)"
    else
        echo "  tailscale não encontrado no host"
    fi

alias comfyui-status := visual-status
alias aistudio-visual-status := visual-status

# 📜 Acompanhar os logs do AI Studio Visual em tempo real
[group('AI Studio Visual')]
visual-logs:
    journalctl --user -u aistudio-visual.service -f --no-hostname -o cat

alias comfyui-logs := visual-logs

# 🔧 Reparar permissões de arquivos em /var/srv/visual
[group('AI Studio Visual')]
visual-fix-perms:
    #!/usr/bin/env bash
    set -euo pipefail
    sudo chown -R 1000:1000 /var/srv/visual
    echo "✔ Permissões restauradas para UID 1000 em /var/srv/visual."

alias comfyui-fix-perms := visual-fix-perms

# 🔄 Sincronizar o ambiente Python persistente com os toolkits declarativos
[group('AI Studio Visual')]
visual-sync:
    #!/usr/bin/env bash
    set -euo pipefail
    REQ_FILE="/usr/share/bazzite-dx/aistudio-visual/requirements.txt"
    if [[ -f "./files/system/usr/share/bazzite-dx/aistudio-visual/requirements.txt" ]]; then
        REQ_FILE="./files/system/usr/share/bazzite-dx/aistudio-visual/requirements.txt"
    elif [[ ! -f "$REQ_FILE" ]]; then
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
    # Remove resíduos de NumPy 2.x e garante integridade do NumPy 1.x
    rm -rf /var/srv/visual/site-packages/numpy-2* /var/srv/visual/site-packages/numpy/_core 2>/dev/null || true
    # Patch defensivo para custom_op infer_schema em comfy_kitchen na.py se necessário
    if [[ -f /var/srv/visual/site-packages/comfy_kitchen/backends/eager/na.py ]]; then
        sed -i 's/kernel_size: list\[int\]/kernel_size: List\[int\]/g; s/is_causal: list\[bool\]/is_causal: List\[bool\]/g; s/scale: float | None/scale: Optional[float]/g' /var/srv/visual/site-packages/comfy_kitchen/backends/eager/na.py 2>/dev/null || true
        grep -q 'from typing import' /var/srv/visual/site-packages/comfy_kitchen/backends/eager/na.py || sed -i 's/from comfy_kitchen.registry import registry/from typing import List, Optional\nfrom comfy_kitchen.registry import registry/' /var/srv/visual/site-packages/comfy_kitchen/backends/eager/na.py 2>/dev/null || true
    fi
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
    MODELS_DIR="/var/srv/visual/ComfyUI/models"
    mkdir -p "$MODELS_DIR/checkpoints" "$MODELS_DIR/unet" "$MODELS_DIR/clip" "$MODELS_DIR/vae" "$MODELS_DIR/loras" "$MODELS_DIR/upscale_models"
    echo "📥 Verificando e baixando modelos do AI Studio Visual (RTX 3060 6GB)..."

    download_file() {
        local url="$1"
        local dest="$2"
        if [[ -s "$dest" ]]; then
            echo "✔ Já presente: $(basename "$dest")"
            return 0
        fi
        echo "→ Baixando: $(basename "$dest")..."
        if command -v aria2c >/dev/null 2>&1; then
            aria2c -c -x 8 -s 8 -d "$(dirname "$dest")" -o "$(basename "$dest")" "$url"
        else
            curl -C - -L -o "$dest" "$url"
        fi
    }

    echo "1. Upscaler 4K UltraSharp (65 MB)..."
    download_file "https://huggingface.co/lokCX/4x-Ultrasharp/resolve/main/4x-UltraSharp.pth" "$MODELS_DIR/upscale_models/4x-UltraSharp.pth"

    echo "2. Checkpoint SDXL Lightning 4-Step (6.5 GB)..."
    download_file "https://huggingface.co/ByteDance/SDXL-Lightning/resolve/main/sdxl_lightning_4step.safetensors" "$MODELS_DIR/checkpoints/sdxl_lightning_4step.safetensors"

    echo "✅ Modelos do AI Studio Visual sincronizados em $MODELS_DIR."

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
