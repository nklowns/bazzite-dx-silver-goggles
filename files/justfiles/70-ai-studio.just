# 🎨 AI Studio (ComfyUI Diffusion Studio, LoRAs & Model Pipelines)

# Iniciar o ComfyUI AI Studio (Geração de Imagens & Vídeo com GPU NVIDIA)
[group('AI Studio')]
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
[group('AI Studio')]
comfyui-down:
    #!/usr/bin/env bash
    set -uo pipefail
    systemctl --user stop comfyui.service
    echo "🛑 ComfyUI AI Studio desativado. VRAM liberada para a GPU."

# 📊 Diagnóstico do ComfyUI e status de VRAM
[group('AI Studio')]
comfyui-status:
    #!/usr/bin/env bash
    set -uo pipefail
    echo "== ComfyUI Container Status =="
    systemctl --user status comfyui.service --no-pager -l || true
    echo ""
    echo "== NVIDIA RTX 3060 VRAM Status =="
    if command -v nvidia-smi >/dev/null 2>&1; then
        nvidia-smi --query-gpu=name,memory.total,memory.used,memory.free,utilization.gpu --format=csv
    fi

# 🔒 Expor o ComfyUI de forma privada e segura no tailnet via Tailscale Serve (:61384)
[group('AI Studio')]
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
