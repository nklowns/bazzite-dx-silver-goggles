# vim: set ft=make :
# ==============================================================================
# GROUP: services — AI Studio Visual (ComfyUI :61384, LivePortrait)
#
# Common lifecycle delegates to /usr/libexec/dx-svc. Domain-specific actions
# (Python site-packages sync, ComfyUI core update, models, LivePortrait) live here.
# ==============================================================================

# Gerenciar AI Studio Visual (ComfyUI :61384). Opções: status | up | down | restart | logs | remote | boot | prefetch | sync | pkg-sync | update | install | versions | pull-models | animate | purge | fix-perms | shell | container-shell | audio-nodes
[group('services')]
visual ACTION="" *ARGS:
    #!/usr/bin/env bash
    set -euo pipefail
    DX_SVC="/usr/libexec/dx-svc"
    [[ -x "$DX_SVC" ]] || DX_SVC="{{ justfile_directory() }}/../system/usr/libexec/dx-svc"
    QUADLET="/etc/containers/systemd/users/aistudio-visual.container"
    [[ -f "$QUADLET" ]] || QUADLET="{{ justfile_directory() }}/../system/etc/containers/systemd/users/aistudio-visual.container"
    COMFY_IMAGE="$(grep -m1 '^Image=' "$QUADLET" | cut -d= -f2-)"

    OPT="{{ ACTION }}"
    if [[ -z "$OPT" ]]; then
        if [[ -t 0 && -t 1 ]] && command -v ugum >/dev/null 2>&1; then
            "$DX_SVC" status visual
            echo
            OPT="$(ugum choose --header "AI Studio Visual (ComfyUI :61384):" \
                "status" "up" "down" "restart" "logs" "remote" "boot" "prefetch" \
                "sync" "pkg-sync" "update" "versions" "pull-models" "purge" \
                "fix-perms" "shell" "container-shell" "audio-nodes")" || exit 0
        else
            OPT="status"
        fi
    fi

    case "$OPT" in
    status) "$DX_SVC" status visual ;;
    up) "$DX_SVC" up visual {{ ARGS }} ;;
    down) "$DX_SVC" down visual ;;
    restart) "$DX_SVC" restart visual ;;
    logs) exec "$DX_SVC" logs visual ;;
    prefetch) "$DX_SVC" prefetch visual ;;
    remote)
        sub="${1:-status}"
        "$DX_SVC" remote "$sub" visual
        ;;
    boot)
        sub="${1:-status}"
        "$DX_SVC" boot "$sub" visual
        ;;
    purge)
        if systemctl --user is-active --quiet aistudio-visual.service; then
            systemctl --user restart aistudio-visual.service
            echo "🧹 VRAM purgada com sucesso."
        else
            echo "AI Studio Visual já está inativo."
        fi
        ;;
    fix-perms)
        sudo chown -R 1000:1000 /var/srv/visual
        echo "✔ Permissões restauradas para UID 1000 em /var/srv/visual."
        ;;
    sync)
        REQ=/usr/share/bazzite-dx/aistudio-visual/requirements.txt
        [[ -f "$REQ" ]] || REQ="{{ justfile_directory() }}/../system/usr/share/bazzite-dx/aistudio-visual/requirements.txt"
        [[ -f "$REQ" ]] || { echo "✖ requirements.txt do AI Studio Visual não encontrado." >&2; exit 1; }
        CONSTRAINTS=/usr/share/bazzite-dx/aistudio-visual/constraints.txt
        [[ -f "$CONSTRAINTS" ]] || CONSTRAINTS="{{ justfile_directory() }}/../system/usr/share/bazzite-dx/aistudio-visual/constraints.txt"
        PIP_ARGS=(-r /requirements.txt)
        MOUNT=()
        if [[ -f "$CONSTRAINTS" ]]; then
            MOUNT+=(-v "$CONSTRAINTS":/constraints.txt:ro)
            PIP_ARGS+=(--constraints /constraints.txt)
        fi
        if [[ -f /var/srv/visual/ComfyUI/requirements.txt ]]; then
            MOUNT+=(-v /var/srv/visual/ComfyUI/requirements.txt:/comfyui-requirements.txt:ro)
            PIP_ARGS+=(-r /comfyui-requirements.txt)
        fi
        if [[ -f /var/srv/visual/requirements.local.txt ]]; then
            MOUNT+=(-v /var/srv/visual/requirements.local.txt:/requirements.local.txt:ro)
            PIP_ARGS+=(-r /requirements.local.txt)
        fi
        mkdir -p /var/srv/visual/site-packages-py313
        podman run --rm \
            --security-opt label=disable \
            -v /var/srv/visual/site-packages-py313:/target:Z \
            -v "$REQ":/requirements.txt:ro \
            "${MOUNT[@]}" \
            "$COMFY_IMAGE" \
            uv pip install --python /usr/bin/python3.13 --target /target --upgrade --quiet "${PIP_ARGS[@]}"
        rm -rf /var/srv/visual/site-packages-py313/{torch,torch-*,torchgen,torchvision*,torchaudio*,nvidia*,functorch*,cuda*,numpy*,triton*}
        if systemctl --user is-active --quiet aistudio-visual.service; then
            systemctl --user restart aistudio-visual.service
        fi
        echo "✅ Sincronização concluída."
        ;;
    pkg-sync)
        SITE_PKG="/var/srv/visual/site-packages-py313"
        CONSTRAINTS=/usr/share/bazzite-dx/aistudio-visual/constraints.txt
        [[ -f "$CONSTRAINTS" ]] || CONSTRAINTS="{{ justfile_directory() }}/../system/usr/share/bazzite-dx/aistudio-visual/constraints.txt"
        mapfile -t PKGS < <(find "${SITE_PKG}" -maxdepth 1 -name "comfy_*-*.dist-info" -printf "%f\n" | sed 's/-[0-9].*//' | sort -u)
        if (( ${#PKGS[@]} == 0 )); then
            echo "⚠  Nenhum pacote comfy_* encontrado em ${SITE_PKG}."
            exit 0
        fi
        MOUNT=()
        UV_ARGS=()
        if [[ -f "$CONSTRAINTS" ]]; then
            MOUNT+=(-v "$CONSTRAINTS":/constraints.txt:ro)
            UV_ARGS+=(--constraints /constraints.txt)
        fi
        podman run --rm \
            --security-opt label=disable \
            --volume "${SITE_PKG}:/target:Z" \
            "${MOUNT[@]}" \
            "$COMFY_IMAGE" \
            uv pip install --python /usr/bin/python3.13 --target /target --upgrade --quiet \
                "${UV_ARGS[@]}" "${PKGS[@]}"
        rm -rf "${SITE_PKG}"/{torch,torch-*,torchgen,torchvision*,torchaudio*,nvidia*,functorch*,cuda*,numpy*,triton*}
        echo "✅ pkg-sync concluído: ${PKGS[*]}"
        ;;
    update)
        podman run --rm -v /var/srv/visual/ComfyUI:/root/ComfyUI:z "$COMFY_IMAGE" \
            bash -c "cd /root/ComfyUI && git pull --ff-only"
        ujust visual pkg-sync
        ujust visual sync
        echo "✅ ComfyUI Core atualizado."
        ;;
    install)
        pkg="{{ ARGS }}"
        [[ -n "$pkg" ]] || { echo "Uso: ujust visual install <pacote>" >&2; exit 2; }
        CONSTRAINTS=/usr/share/bazzite-dx/aistudio-visual/constraints.txt
        [[ -f "$CONSTRAINTS" ]] || CONSTRAINTS="{{ justfile_directory() }}/../system/usr/share/bazzite-dx/aistudio-visual/constraints.txt"
        MOUNT=()
        UV_ARGS=()
        if [[ -f "$CONSTRAINTS" ]]; then
            MOUNT+=(-v "$CONSTRAINTS":/constraints.txt:ro)
            UV_ARGS+=(--constraints /constraints.txt)
        fi
        mkdir -p /var/srv/visual/site-packages-py313
        # shellcheck disable=SC2086
        podman run --rm \
            --security-opt label=disable \
            -v /var/srv/visual/site-packages-py313:/target:Z \
            "${MOUNT[@]}" \
            "$COMFY_IMAGE" \
            uv pip install --python /usr/bin/python3.13 --target /target --quiet "${UV_ARGS[@]}" $pkg
        rm -rf /var/srv/visual/site-packages-py313/{torch,torch-*,torchgen,torchvision*,torchaudio*,nvidia*,functorch*,cuda*,numpy*,triton*}
        if systemctl --user is-active --quiet aistudio-visual.service; then
            systemctl --user restart aistudio-visual.service
        fi
        echo "✅ Pacote(s) instalado(s): $pkg"
        ;;
    versions)
        echo "Imagem base: $COMFY_IMAGE"
        if [[ -d /var/srv/visual/ComfyUI/.git ]]; then
            echo "ComfyUI instalado: $(git -C /var/srv/visual/ComfyUI describe --tags --always)"
        fi
        if command -v gh >/dev/null 2>&1; then
            echo "ComfyUI upstream:  $(gh release view -R comfyanonymous/ComfyUI --json tagName -q .tagName 2>/dev/null || echo '?')"
        fi
        for p in comfy_kitchen comfy_aimdo comfyui_frontend_package huggingface_hub; do
            v="$(find /var/srv/visual/site-packages-py313 -maxdepth 1 -name "${p}-*.dist-info" -printf '%f\n' 2>/dev/null | sed -E 's|^[^-]+-([^/]+)\.dist-info|\1|' | sort -V | tail -1)"
            echo "$p instalado: ${v:-?}"
        done
        ;;
    pull-models)
        MODELS_DIR="/var/srv/visual/ComfyUI/models"
        mkdir -p "$MODELS_DIR"/{checkpoints,unet,clip,vae,loras,upscale_models}
        download_file() {
            local url="$1" dest="$2"
            if [[ -s "$dest" ]]; then echo "✔ Já presente: $(basename "$dest")"; return 0; fi
            if command -v aria2c >/dev/null 2>&1; then
                aria2c -c -x 8 -s 8 -d "$(dirname "$dest")" -o "$(basename "$dest")" "$url"
            else
                curl -C - -L -o "$dest" "$url"
            fi
        }
        download_file "https://huggingface.co/lokCX/4x-Ultrasharp/resolve/main/4x-UltraSharp.pth" "$MODELS_DIR/upscale_models/4x-UltraSharp.pth"
        download_file "https://huggingface.co/ByteDance/SDXL-Lightning/resolve/main/sdxl_lightning_4step.safetensors" "$MODELS_DIR/checkpoints/sdxl_lightning_4step.safetensors"
        echo "✅ Modelos sincronizados em $MODELS_DIR."
        ;;
    animate)
        set -- {{ ARGS }}
        img="${1:-}"; aud="${2:-}"; drv="${3:-}"; out="${4:-}"
        [[ -n "$img" ]] || { echo "Uso: ujust visual animate <image> [audio] [driving_video] [output]" >&2; exit 2; }
        VISUAL_DIR="${XDG_PICTURES_DIR:-$HOME/Pictures}/AI_Studio"
        mkdir -p "$VISUAL_DIR"
        OUT_FILE="${out:-$VISUAL_DIR/Avatar_Animado_$(date +%s).mp4}"
        systemctl --user is-active --quiet aistudio-visual.service || "$DX_SVC" up visual
        podman exec aistudio_visual python3.13 /root/user-scripts/animate_avatar.py \
            "$img" "/root/ComfyUI/output/temp_animated_export.mp4" "$aud" "$drv"
        if [[ -f "$VISUAL_DIR/temp_animated_export.mp4" && "$OUT_FILE" != "$VISUAL_DIR/temp_animated_export.mp4" ]]; then
            mv "$VISUAL_DIR/temp_animated_export.mp4" "$OUT_FILE"
        elif [[ -f /var/srv/visual/ComfyUI/output/temp_animated_export.mp4 ]]; then
            cp /var/srv/visual/ComfyUI/output/temp_animated_export.mp4 "$OUT_FILE"
        fi
        echo "✅ Vídeo salvo em: $OUT_FILE"
        ;;
    shell)
        echo "Namespace rootless do podman (/var/srv/visual). Saia com 'exit'."
        podman unshare bash
        ;;
    container-shell)
        systemctl --user is-active --quiet aistudio-visual.service || "$DX_SVC" up visual
        podman exec -it aistudio_visual bash
        ;;
    audio-nodes)
        NODES_DIR="/var/srv/visual/ComfyUI/custom_nodes"
        mkdir -p "$NODES_DIR"
        sync_repo() {
            local url="$1" target="$NODES_DIR/$2"
            if [[ -d "$target/.git" ]]; then git -C "$target" pull --quiet || true; else git clone --quiet --depth 1 "$url" "$target"; fi
        }
        sync_repo "https://github.com/diodiogod/TTS-Audio-Suite.git" "TTS-Audio-Suite"
        sync_repo "https://github.com/billwuhao/ComfyUI_ACE-Step.git" "ComfyUI_ACE-Step"
        sync_repo "https://github.com/christian-byrne/audio-separation-nodes-comfyui.git" "audio-separation-nodes"
        ujust visual install "soundfile librosa pydub conformer vocos"
        ;;
    build-sdcpp)
        SDCPP_DIR="/var/srv/visual/sdcpp/stable-diffusion.cpp"
        mkdir -p /var/srv/visual/sdcpp
        if [[ -d "$SDCPP_DIR/.git" ]]; then
            git -C "$SDCPP_DIR" pull --ff-only
            git -C "$SDCPP_DIR" submodule update --init --recursive
        else
            git clone --recursive https://github.com/leejet/stable-diffusion.cpp "$SDCPP_DIR"
        fi
        podman run --rm \
            -v "$SDCPP_DIR:/src:z" \
            docker.io/yanwk/comfyui-boot:base-cu130-devel \
            bash -c 'set -euo pipefail; dnf install -y -q cmake make >/dev/null; cmake -S /src -B /src/build -DCMAKE_BUILD_TYPE=Release -DCMAKE_CUDA_ARCHITECTURES=86 -DSD_CUDA=ON -DGGML_CUDA_FA=ON && cmake --build /src/build --config Release -j"$(nproc)" --target sd-cli'
        echo "✅ sd-cli (CUDA 13 / sm_86) compilado em $SDCPP_DIR/build/bin/sd-cli"
        ;;
    help | -h | --help)
        echo "Uso: ujust visual <status|up|down|restart|logs|remote <on|off|status>|boot <on|off|status>|prefetch|sync|pkg-sync|update|install <pkg>|versions|pull-models|build-sdcpp|animate|purge|fix-perms|shell|container-shell|audio-nodes>"
        ;;
    *)
        echo "❌ Ação desconhecida para visual: '$OPT'" >&2
        exit 2
        ;;
    esac
