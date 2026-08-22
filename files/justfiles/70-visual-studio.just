# 🎨 AI Studio (ComfyUI Diffusion Studio, LoRAs & Model Pipelines)

# Iniciar o ComfyUI AI Studio (Geração de Imagens & Vídeo com GPU NVIDIA)
[group('Visual Studio')]
comfyui-up:
    #!/usr/bin/env bash
    set -euo pipefail
    if ! systemctl is-active --quiet nvidia-persistenced.service; then
        echo "⚠️  nvidia-persistenced parado — a injeção CDI vai falhar."
    fi
    if [[ "$(getsebool container_use_devices 2>/dev/null || echo '--> off')" == *off ]]; then
        echo "⚠️  container_use_devices=off — o container vai receber os devices e levar Permission denied."
    fi
    systemctl --user daemon-reload
    systemctl --user start comfyui.service
    echo "✅ ComfyUI AI Studio ativo. Endpoint no host: http://localhost:61384"
    echo "   Para acessar remotamente via Tailscale com TLS: ujust remote-comfyui-setup"

# 🛑 Parar o ComfyUI AI Studio e liberar 100% da VRAM para a GPU
[group('Visual Studio')]
comfyui-down:
    #!/usr/bin/env bash
    set -uo pipefail
    systemctl --user stop comfyui.service
    echo "🛑 ComfyUI AI Studio desativado. VRAM liberada para a GPU."

# 📊 Diagnóstico do ComfyUI e status de VRAM
[group('Visual Studio')]
comfyui-status:
    #!/usr/bin/env bash
    set -uo pipefail
    echo "== ComfyUI Container Status =="
    systemctl --user status comfyui.service --no-pager -l || true
    echo ""
    echo "== Versões e Diagnóstico da API =="
    if curl -s -f http://localhost:61384/system_stats >/dev/null 2>&1; then
        curl -s http://localhost:61384/system_stats | jq '{comfyui_version: .system.comfyui_version, frontend_version: .system.required_frontend_version, pytorch: .system.pytorch_version, python: .system.python_version}' 2>/dev/null || true
    else
        echo "ComfyUI API não está respondendo em http://localhost:61384"
    fi
    echo ""
    echo "== NVIDIA RTX 3060 VRAM Status =="
    if command -v nvidia-smi >/dev/null 2>&1; then
        nvidia-smi --query-gpu=name,memory.total,memory.used,memory.free,utilization.gpu --format=csv
    fi

# 🔄 Atualizar o ComfyUI Core para o lançamento mais recente do Comfy-Org
[group('Visual Studio')]
comfyui-update:
    #!/usr/bin/env bash
    set -euo pipefail
    TARGET_DIR="/var/srv/comfyui/ComfyUI"
    [ -d "$TARGET_DIR" ] || TARGET_DIR="/var/srv/nomad/comfyui/ComfyUI"
    if [ ! -d "$TARGET_DIR/.git" ]; then
        echo "❌ Diretório git do ComfyUI não encontrado em $TARGET_DIR"
        exit 1
    fi
    echo "📡 Buscando versões mais recentes em Comfy-Org/ComfyUI..."
    git -C "$TARGET_DIR" fetch --tags origin
    LATEST_TAG=$(git -C "$TARGET_DIR" tag --sort=-v:refname | grep -E '^v[0-9]+\.[0-9]+' | head -n 1)
    echo "→ Atualizando para a tag estável mais recente: $LATEST_TAG"
    git -C "$TARGET_DIR" checkout "$LATEST_TAG"
    if systemctl --user is-active --quiet comfyui.service; then
        echo "🔄 Reiniciando serviço comfyui.service..."
        systemctl --user restart comfyui.service
    fi
    echo "✅ ComfyUI atualizado para $LATEST_TAG com sucesso."

# 📥 Baixar modelos dimensionados para os 6 GB de VRAM da RTX 3060
[group('Visual Studio')]
comfyui-pull-models:
    #!/usr/bin/env bash
    set -euo pipefail
    TARGET_DIR="/var/srv/comfyui/models/checkpoints"
    [ -d "$TARGET_DIR" ] || TARGET_DIR="/var/srv/nomad/comfyui/ComfyUI/models/checkpoints"
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

# 🧹 Purgar a VRAM imediatamente (descarrega modelos residentes da GPU)
[group('Visual Studio')]
comfyui-vram-purge:
    #!/usr/bin/env bash
    set -euo pipefail
    if systemctl --user is-active --quiet comfyui.service; then
        systemctl --user restart comfyui.service
        echo "🧹 VRAM purgada com sucesso. Nenhum modelo residente na GPU."
    else
        echo "ComfyUI já está inativo."
    fi

# 🗂️ Shell no namespace rootless para manipular arquivos do AI Studio
[group('Visual Studio')]
comfyui-shell:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "Namespace de usuário do podman para manipular /var/srv/comfyui. Saia com 'exit'."
    podman unshare bash

# 🔒 Expor o ComfyUI de forma privada e segura no tailnet via Tailscale Serve (:61384)
[group('Visual Studio')]
remote-comfyui-setup:
    #!/usr/bin/env bash
    set -euo pipefail
    if ! systemctl --user is-active --quiet comfyui.service; then
        echo "❌ ComfyUI não está rodando. Rode 'ujust comfyui-up' primeiro."
        exit 1
    fi
    /usr/libexec/bazzite-dx-serve ensure 61384
    DNS_NAME=$(tailscale status --self --json | jq -r '.Self.DNSName' | sed 's/\.$//')
    echo "✅ ComfyUI AI Studio pronto em: https://$DNS_NAME:61384"
