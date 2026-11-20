# vim: set ft=make :
# ==============================================================================
# GROUP: services — Project NOMAD & nomad-llama (llama-swap + llama.cpp CUDA)
#
# Common lifecycle (up/down/restart/status/logs/remote/boot/prefetch) delegates
# to /usr/libexec/dx-svc. Domain-specific actions live here.
# ==============================================================================

# Gerenciar Project NOMAD. Opções: status | up | down | restart | logs | remote | boot | prefetch | update | loopback-apps | shell | firewall-on | firewall-off
[group('services')]
nomad ACTION="" *ARGS:
    #!/usr/bin/env bash
    set -euo pipefail
    DX_SVC="/usr/libexec/dx-svc"
    [[ -x "$DX_SVC" ]] || DX_SVC="{{ justfile_directory() }}/../system/usr/libexec/dx-svc"
    OPT="{{ ACTION }}"
    if [[ -z "$OPT" ]]; then
        if [[ -t 0 && -t 1 ]] && command -v ugum >/dev/null 2>&1; then
            "$DX_SVC" status nomad
            echo
            OPT="$(ugum choose --header "Project NOMAD:" \
                "status" "up" "down" "restart" "logs" "remote" "boot" "prefetch" \
                "update" "loopback-apps" "shell" "firewall-on" "firewall-off")" || exit 0
        else
            OPT="status"
        fi
    fi

    case "$OPT" in
    status) "$DX_SVC" status nomad ;;
    up) "$DX_SVC" up nomad {{ ARGS }} ;;
    down) "$DX_SVC" down nomad ;;
    restart) "$DX_SVC" restart nomad ;;
    logs) exec "$DX_SVC" logs nomad ;;
    prefetch) "$DX_SVC" prefetch nomad ;;
    remote)
        sub="${1:-status}"
        "$DX_SVC" remote "$sub" nomad
        ;;
    boot)
        sub="${1:-status}"
        "$DX_SVC" boot "$sub" nomad
        ;;
    update)
        "$DX_SVC" prefetch nomad
        "$DX_SVC" prefetch mysql
        "$DX_SVC" prefetch redis
        systemctl --user restart nomad-admin.service
        echo "✅ Project NOMAD atualizado."
        ;;
    loopback-apps)
        if ! systemctl --user is-active --quiet nomad-admin.service; then
            echo "❌ Command Center parado. Rode 'ujust nomad up' primeiro." >&2
            exit 1
        fi
        /usr/libexec/project-nomad-loopback-apps --recreate
        echo "--- containers do NOMAD e seus binds:"
        podman ps --format '{{{{.Names}}}} {{{{.Ports}}}}' | awk '$1 ~ /^nomad_/'
        ;;
    shell)
        echo "Namespace de usuário do podman (/var/srv/nomad). Saia com 'exit'."
        podman unshare bash
        ;;
    firewall-on)
        if ! command -v firewall-cmd >/dev/null 2>&1; then
            echo "❌ firewall-cmd não encontrado." >&2
            exit 1
        fi
        sudo firewall-cmd --add-service=project-nomad --permanent
        sudo firewall-cmd --reload
        echo "✅ Porta 61380 liberada na rede local."
        ;;
    firewall-off)
        if ! command -v firewall-cmd >/dev/null 2>&1; then
            echo "❌ firewall-cmd não encontrado." >&2
            exit 1
        fi
        sudo firewall-cmd --remove-service=project-nomad --permanent || true
        sudo firewall-cmd --reload
        echo "🧯 Portas do NOMAD fechadas na rede local."
        ;;
    help | -h | --help)
        echo "Uso: ujust nomad <status|up|down|restart|logs|remote <on|off|status>|boot <on|off|status>|prefetch|update|loopback-apps|shell|firewall-on|firewall-off>"
        ;;
    *)
        echo "❌ Ação desconhecida para nomad: '$OPT'" >&2
        exit 2
        ;;
    esac

# Gerenciar nomad-llama (CUDA OpenAI API :61383). Opções: status | up | down | restart | logs | boot | prefetch | unload | models-fetch | fit | which | advisor
[group('services')]
llama ACTION="" *ARGS:
    #!/usr/bin/env bash
    set -euo pipefail
    DX_SVC="/usr/libexec/dx-svc"
    [[ -x "$DX_SVC" ]] || DX_SVC="{{ justfile_directory() }}/../system/usr/libexec/dx-svc"
    OPT="{{ ACTION }}"
    if [[ -z "$OPT" ]]; then
        if [[ -t 0 && -t 1 ]] && command -v ugum >/dev/null 2>&1; then
            "$DX_SVC" status llama
            echo
            OPT="$(ugum choose --header "nomad-llama (RTX 3060 6GB):" \
                "status" "up" "down" "restart" "unload" "logs" "boot" "prefetch" \
                "models-fetch" "fit" "which" "advisor")" || exit 0
        else
            OPT="status"
        fi
    fi

    case "$OPT" in
    status)
        "$DX_SVC" status llama
        CFG="$HOME/.config/llama-swap/config.yaml"
        printf '%-14s %s\n' "config:" "$([[ -e "$CFG" ]] && readlink -f "$CFG" || echo 'ausente (ujust llama up cria)')"
        if systemctl --user is-active --quiet nomad-llama.service 2>/dev/null; then
            curl -s -m 5 http://127.0.0.1:61383/v1/models | jq -r '"modelos:       " + ([.data[].id] | join(", "))' 2>/dev/null || true
            curl -s -m 5 http://127.0.0.1:61383/running | jq -r '"carregado:     " + ([.running[]? | "\(.model) (\(.state))"] | join(", ") | if . == "" then "nenhum" else . end)' 2>/dev/null || true
        fi
        llama-models-fetch --list 2>/dev/null | sed 's/^/pesos:         /' || true
        ;;
    up)
        "$DX_SVC" up llama {{ ARGS }}
        curl -s -m 5 http://127.0.0.1:61383/v1/models | jq -r '"   modelos: " + ([.data[].id] | join(", "))' 2>/dev/null || true
        ;;
    down) "$DX_SVC" down llama ;;
    restart) "$DX_SVC" restart llama ;;
    logs) exec "$DX_SVC" logs llama ;;
    prefetch) "$DX_SVC" prefetch llama ;;
    boot)
        sub="${1:-status}"
        "$DX_SVC" boot "$sub" llama
        ;;
    unload | vram-purge)
        if systemctl --user is-active --quiet nomad-llama.service 2>/dev/null; then
            curl -s -m 30 -X POST http://127.0.0.1:61383/api/models/unload -o /dev/null && echo "🧹 nomad-llama: modelos descarregados."
        else
            echo "ℹ️  nomad-llama já está parado."
        fi
        nvidia-smi --query-gpu=memory.used,memory.total --format=csv,noheader 2>/dev/null | sed 's/^/   VRAM: /' || true
        ;;
    models-fetch)
        llama-models-fetch {{ ARGS }}
        ;;
    fit)
        if command -v llmfit >/dev/null 2>&1; then
            llmfit {{ ARGS }}
        elif command -v uvx >/dev/null 2>&1; then
            uvx llmfit {{ ARGS }}
        else
            echo "❌ Nem llmfit nem uvx encontrados." >&2
            exit 1
        fi
        ;;
    which)
        if command -v whichllm >/dev/null 2>&1; then
            whichllm {{ ARGS }}
        elif command -v uvx >/dev/null 2>&1; then
            uvx whichllm@latest {{ ARGS }}
        else
            echo "❌ Nem whichllm nem uvx encontrados." >&2
            exit 1
        fi
        ;;
    advisor)
        cat <<'EOF'
        ================================================================================
        🧠 DIRETRIZES DE LLM: DELL G15 5520 (RTX 3060 6GB + 64GB DDR5 + i7-12700H)
        Backend: nomad-llama (llama-swap + llama.cpp CUDA) — ujust llama up
        ================================================================================
        • 4B híbrido denso (Qwen3.5-4B Q4_K_M): tudo na VRAM, ~80-114 tok/s, 48k ctx.
        • 35B MoE experts na CPU (Qwen3.6-35B-A3B Q4_K): --n-cpu-moe 40, KV q8_0 na GPU,
          128k ctx (~114k efetivo), ~5.1 GiB VRAM.
        • Regras: CUDA (não Vulkan), KV q8_0 + -fa on, -t 6 -C 0x555, -np 1 explícito.
        • Ferramentas: ujust llama fit | ujust llama which | ujust llama models-fetch
        ================================================================================
        EOF
        ;;
    help | -h | --help)
        echo "Uso: ujust llama <status|up|down|restart|logs|boot <on|off|status>|prefetch|unload|models-fetch|fit|which|advisor>"
        ;;
    *)
        echo "❌ Ação desconhecida para llama: '$OPT'" >&2
        exit 2
        ;;
    esac
