# vim: set ft=make :
# ==============================================================================
# GROUP: services — Agent Mesh (SearXNG, Vane, Recoll, Tor, I2P, Trawl, Lightpanda)
#
# Common lifecycle delegates to /usr/libexec/dx-svc. Domain-specific actions
# (canary, recoll-index, vane-llama-sync, cdp-matrix) live here.
# ==============================================================================

# Gerenciar Agent Mesh. Opções: status | up [svc] | down [svc] | logs <svc> | remote <on|off|status> [svc] | boot <on|off|status> <svc> | prefetch [svc] | canary | recoll-index | vane-llama-sync | cdp-matrix
[group('services')]
mesh ACTION="" *ARGS:
    #!/usr/bin/env bash
    set -euo pipefail
    DX_SVC="/usr/libexec/dx-svc"
    [[ -x "$DX_SVC" ]] || DX_SVC="{{ justfile_directory() }}/../system/usr/libexec/dx-svc"
    OPT="{{ ACTION }}"
    if [[ -z "$OPT" ]]; then
        if [[ -t 0 && -t 1 ]] && command -v ugum >/dev/null 2>&1; then
            OPT="$(ugum choose --header "Agent Mesh:" \
                "status" "up" "down" "logs" "remote" "prefetch" \
                "canary" "recoll-index" "vane-llama-sync" "cdp-matrix")" || exit 0
        else
            OPT="status"
        fi
    fi

    # shellcheck disable=SC2086
    set -- {{ ARGS }}
    case "$OPT" in
    status)
        if [[ -n "${1:-}" ]]; then
            "$DX_SVC" status "$1"
        else
            for s in searxng tor i2p recoll vane lightpanda trawl; do
                "$DX_SVC" status "$s"
                echo
            done
            ujust mesh cdp-matrix
        fi
        ;;
    up) "$DX_SVC" up "${1:-mesh}" ;;
    down) "$DX_SVC" down "${1:-mesh}" ;;
    restart) "$DX_SVC" restart "${1:-searxng}" ;;
    logs) exec "$DX_SVC" logs "${1:-}" ;;
    prefetch) "$DX_SVC" prefetch "${1:-mesh}" ;;
    remote)
        sub="${1:-status}"
        svc="${2:-}"
        if [[ -n "$svc" ]]; then
            "$DX_SVC" remote "$sub" "$svc"
        else
            "$DX_SVC" remote "$sub" searxng
            "$DX_SVC" remote "$sub" vane
        fi
        ;;
    boot)
        sub="${1:-status}"
        svc="${2:-}"
        "$DX_SVC" boot "$sub" "$svc"
        ;;
    recoll-index)
        INDEXER="/usr/libexec/bazzite-dx-recoll-index"
        [[ -x "$INDEXER" ]] || INDEXER="{{ justfile_directory() }}/../system/usr/libexec/bazzite-dx-recoll-index"
        "$INDEXER" "$@"
        echo "✅ Indexação incremental concluída."
        ;;
    vane-llama-sync)
        VANE="http://127.0.0.1:61385"
        MODELS="$(curl -sf -m 5 http://127.0.0.1:61383/v1/models)" || { echo "❌ nomad-llama não responde (ujust llama up)" >&2; exit 1; }
        CFG="$(curl -sf -m 5 "$VANE/api/config")" || { echo "❌ Vane não responde (ujust mesh up vane)" >&2; exit 1; }
        PID="$(jq -r '.values.modelProviders[] | select(.type=="openai") | .id' <<<"$CFG" | head -1)"
        [[ -n "$PID" ]] || { echo "❌ Vane sem provider OpenAI." >&2; exit 1; }
        jq -r '.data[] | "\(if .meta.llamaswap.task == "embedding" then "embedding" else "chat" end) \(.id)"' <<<"$MODELS" | while read -r kind id; do
            if jq -e --arg id "$id" --arg k "$kind" '.values.modelProviders[] | select(.type=="openai")
                | (if $k=="embedding" then .embeddingModels else .chatModels end) | any(.key==$id)' <<<"$CFG" >/dev/null; then
                echo "  = $kind $id"
            else
                jq -n --arg id "$id" --arg k "$kind" '{key:$id, name:($id+" (nomad-llama)"), type:$k}' |
                    curl -sf -m 10 -X POST "$VANE/api/providers/$PID/models" -H 'Content-Type: application/json' -d @- >/dev/null
                echo "  + $kind $id"
            fi
        done
        echo "✅ Vane sincronizado com o nomad-llama."
        ;;
    canary)
        SEARXNG_URL="http://127.0.0.1:61387"
        if ! curl -sf "$SEARXNG_URL/healthz" >/dev/null 2>&1; then
            echo "❌ SearXNG não responde em $SEARXNG_URL. Rode 'ujust mesh up searxng'." >&2
            exit 1
        fi
        echo "=== 🐤 SEARXNG ENGINES CANARY TEST ==="
        printf "%-18s | %-10s | %-8s | %s\n" "MOTOR" "STATUS" "TEMPO" "RESULTADOS"
        echo "-----------------------------------------------------------------"
        test_engine() {
            local name="$1" query="${2:-linux kernel}" start_ts end_ts elapsed resp count unresp
            start_ts="$(date +%s%3N)"
            resp="$(curl -s -m 12 -G "$SEARXNG_URL/search" --data-urlencode "q=${query}" -d "format=json" -d "engines=${name}" 2>/dev/null || echo "{}")"
            end_ts="$(date +%s%3N)"
            elapsed=$((end_ts - start_ts))
            count="$(jq -r '((.results // []) | length) + ((.infoboxes // []) | length)' <<<"$resp" 2>/dev/null || echo "0")"
            unresp="$(jq -r 'if .unresponsive_engines then (.unresponsive_engines | map(.[0]) | join(",")) else "" end' <<<"$resp" 2>/dev/null || echo "")"
            if [[ "$count" -gt 0 ]]; then
                printf "%-18s | \033[32m%-10s\033[0m | %-6dms | %d resultados\n" "$name" "OK" "$elapsed" "$count"
            elif [[ "$unresp" == *"$name"* ]]; then
                printf "%-18s | \033[31m%-10s\033[0m | %-6dms | BLOQUEADO / ERRO\n" "$name" "FALHA" "$elapsed"
            else
                printf "%-18s | \033[33m%-10s\033[0m | %-6dms | 0 resultados (vazio)\n" "$name" "AVISO" "$elapsed"
            fi
        }
        test_engine "brave"
        test_engine "google cse"
        test_engine "duckduckgo"
        test_engine "mojeek"
        test_engine "wikipedia"
        test_engine "github" "antigravity"
        test_engine "arxiv" "quantum computing"
        test_engine "openalex" "quantum computing"
        test_engine "hackernews" "antigravity"
        test_engine "lemmy posts" "linux"
        test_engine "marginalia" "personal computers"
        test_engine "mwmbl" "open source"
        echo "-----------------------------------------------------------------"
        ;;
    cdp-matrix)
        echo "=== 🌐 BROWSER AUTOMATION CDP MATRIX ==="
        check_port() {
            local name="$1" port="$2" profile="$3"
            if ss -tlnH "src 127.0.0.1 sport = :${port}" 2>/dev/null | grep -q .; then
                printf '  [✔] %-14s :%-5d ATIVO    (%s)\n' "$name" "$port" "$profile"
            else
                printf '  [ ] %-14s :%-5d inativo  (%s)\n' "$name" "$port" "$profile"
            fi
        }
        check_port "Google Chrome" 9222 "~/.config/google-chrome-cdp"
        check_port "Microsoft Edge" 9223 "~/.config/microsoft-edge-cdp"
        check_port "Mozilla Firefox" 9224 "~/.mozilla/firefox-cdp (--no-remote)"
        check_port "Lightpanda" 9225 "In-Memory Zig Headless (zero profile)"
        ;;
    help | -h | --help)
        echo "Uso: ujust mesh <status|up [svc]|down [svc]|restart [svc]|logs <svc>|remote <on|off|status> [svc]|boot <on|off|status> <svc>|prefetch [svc]|canary|recoll-index|vane-llama-sync|cdp-matrix>"
        ;;
    *)
        echo "❌ Ação desconhecida para mesh: '$OPT'" >&2
        exit 2
        ;;
    esac
