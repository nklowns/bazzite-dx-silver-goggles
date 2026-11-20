# vim: set ft=make :
# ==============================================================================
# GROUP: services — AI Studio Audio (VoiceStudio :61386, OpenAI Audio API)
#
# Common lifecycle delegates to /usr/libexec/dx-svc. Domain-specific actions
# (portal, purge, pull-models, shell) live here.
# ==============================================================================

# Gerenciar AI Studio Audio (VoiceStudio :61386). Opções: status | up | down | restart | logs | remote | boot | prefetch | purge | portal | pull-models | shell
[group('services')]
audio ACTION="" *ARGS:
    #!/usr/bin/env bash
    set -euo pipefail
    DX_SVC="/usr/libexec/dx-svc"
    [[ -x "$DX_SVC" ]] || DX_SVC="{{ justfile_directory() }}/../system/usr/libexec/dx-svc"
    OPT="{{ ACTION }}"
    if [[ -z "$OPT" ]]; then
        if [[ -t 0 && -t 1 ]] && command -v ugum >/dev/null 2>&1; then
            "$DX_SVC" status audio
            echo
            OPT="$(ugum choose --header "AI Studio Audio (VoiceStudio :61386):" \
                "status" "up" "down" "restart" "logs" "remote" "boot" "prefetch" \
                "portal" "purge" "pull-models" "shell")" || exit 0
        else
            OPT="status"
        fi
    fi

    case "$OPT" in
    status) "$DX_SVC" status audio ;;
    up) "$DX_SVC" up audio {{ ARGS }} ;;
    down) "$DX_SVC" down audio ;;
    restart) "$DX_SVC" restart audio ;;
    logs) exec "$DX_SVC" logs audio ;;
    prefetch) "$DX_SVC" prefetch audio ;;
    remote)
        sub="${1:-status}"
        "$DX_SVC" remote "$sub" audio
        ;;
    boot)
        sub="${1:-status}"
        "$DX_SVC" boot "$sub" audio
        ;;
    purge)
        if systemctl --user is-active --quiet aistudio-audio.service; then
            systemctl --user restart aistudio-audio.service
            echo "🧹 VRAM purgada com sucesso."
        else
            echo "AI Studio Audio já está inativo."
        fi
        ;;
    pull-models)
        mkdir -p /var/srv/audio/data/huggingface
        systemctl --user is-active --quiet aistudio-audio.service || "$DX_SVC" up audio
        echo "✅ VoiceStudio ativo. Modelos sob demanda são gerenciados via Web UI (:61386)."
        ;;
    portal)
        systemctl --user is-active --quiet aistudio-audio.service || "$DX_SVC" up audio
        echo "✔ VoiceStudio Web UI: http://127.0.0.1:61386"
        echo "  Swagger API:        http://127.0.0.1:61386/docs"
        SERVE_STATE="$(/usr/libexec/bazzite-dx-serve status 61386 61386 http 2>/dev/null || echo "absent")"
        if [[ "$SERVE_STATE" == "ok" ]]; then
            DNS_NAME="$(tailscale status --self --json 2>/dev/null | jq -r '.Self.DNSName' | sed 's/\.$//' || true)"
            echo "  Tailnet HTTPS:      https://${DNS_NAME:-localhost}:61386"
        else
            echo "  Para expor no Tailscale: ujust audio remote on"
        fi
        ;;
    shell)
        echo "Namespace rootless do podman (/var/srv/audio). Saia com 'exit'."
        podman unshare bash
        ;;
    help | -h | --help)
        echo "Uso: ujust audio <status|up|down|restart|logs|remote <on|off|status>|boot <on|off|status>|prefetch|purge|portal|pull-models|shell>"
        ;;
    *)
        echo "❌ Ação desconhecida para audio: '$OPT'" >&2
        exit 2
        ;;
    esac
