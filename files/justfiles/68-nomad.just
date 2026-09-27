# vim: set ft=make :
# ==============================================================================
# GROUP: Project NOMAD (Offline Knowledge, AI & Maps)
#
# The stack runs as ROOTLESS PODMAN QUADLET units, not docker compose. Units live in
# /etc/containers/systemd/users/ (rootless Quadlet has no /usr search path) and a systemd
# generator turns each .container into a .service. So the verbs here are systemctl, and the
# unit names are nomad-{admin,mysql,redis,dozzle}.service.
#
# START, NOT ENABLE — and the distinction is not pedantry on this image. Lingering is on
# (`loginctl show-user $USER -p Linger` -> yes), which means an *enabled* user unit starts at
# BOOT with no login and survives logout. `enable` here would quietly sign the machine up for
# a permanent MySQL + Redis + Node server, on the same hardware a game session wants. Every
# recipe below therefore starts and stops; nothing enables. Anyone who genuinely wants NOMAD
# always-on can `systemctl --user enable nomad-admin.service` deliberately — see the [Install]
# comment in nomad-admin.container.
# ==============================================================================

# 🏕️ Iniciar o Project NOMAD (Command Center + MySQL + Redis)
[group('NOMAD')]
nomad-up:
    #!/usr/bin/env bash
    set -euo pipefail
    # No mkdir and no sudo: /var/srv/nomad is created by tmpfiles.d and its btrfs nodatacow
    # attribute, SELinux label and CACHEDIR.TAG are applied declaratively at boot by
    # ConfigureNomadStorage() in /usr/libexec/bazzite-dx-groups. If the tree is missing here,
    # that provisioning has not run — say so instead of papering over it with a mkdir that
    # would create a root-owned directory the rootless containers cannot write to.
    if [[ ! -d /var/srv/nomad/storage ]]; then
        echo "❌ /var/srv/nomad/storage não existe — o provisionamento declarativo não rodou."
        echo "   Verifique: systemctl status bazzite-dx-groups.service"
        exit 1
    fi
    # Secrets are generated on first run only and never overwritten, so MySQL keeps working
    # across image rebases (it only reads MYSQL_PASSWORD when initialising an empty datadir).
    /usr/libexec/project-nomad-bootstrap-env
    systemctl --user daemon-reload
    # Starting the admin pulls in mysql, redis, the network and podman.socket through
    # Requires=; the databases use Notify=healthy, so this returns once they really answer.
    systemctl --user start nomad-admin.service
    podman start nomad_qdrant 2>/dev/null || true
    echo "✅ Project NOMAD ativo em http://localhost:61380"
    echo "   Logs: journalctl --user -u nomad-admin.service -f (ou Cockpit na :61390)"
    echo "   Não sobe sozinho no próximo boot — rode 'ujust nomad-up' de novo."

# 🛑 Parar o Project NOMAD
[group('NOMAD')]
nomad-down:
    #!/usr/bin/env bash
    set -uo pipefail
    # admin last: stopping mysql/redis first would take the admin down with them via Requires=
    # and log a failure on the way out.
    podman stop nomad_qdrant 2>/dev/null || true
    systemctl --user stop nomad-admin.service nomad-mysql.service nomad-redis.service
    echo "🛑 Project NOMAD desativado. Dados preservados em /var/srv/nomad."

# ⚡ Habilitar o Project NOMAD para iniciar automaticamente no boot (Ative e esqueça)
[group('NOMAD')]
nomad-enable-boot:
    #!/usr/bin/env bash
    set -euo pipefail
    DROPIN_DIR="$HOME/.config/containers/systemd/nomad-admin.container.d"
    mkdir -p "$DROPIN_DIR"
    printf "[Install]\nWantedBy=default.target\n" > "$DROPIN_DIR/10-autostart.conf"
    systemctl --user daemon-reload
    just nomad-up
    echo "⚡ Project NOMAD habilitado para iniciar automaticamente no boot!"

# 🔌 Desabilitar o Project NOMAD da inicialização automática do boot
[group('NOMAD')]
nomad-disable-boot:
    #!/usr/bin/env bash
    set -uo pipefail
    rm -f "$HOME/.config/containers/systemd/nomad-admin.container.d/10-autostart.conf"
    rmdir "$HOME/.config/containers/systemd/nomad-admin.container.d" 2>/dev/null || true
    systemctl --user daemon-reload
    echo "🔌 Project NOMAD removido do boot automático. Use 'ujust nomad-up' quando precisar."

# 📊 Diagnóstico das units, uso de VRAM na RTX 3060 e volumes NOMAD
[group('NOMAD')]
nomad-status:
    #!/usr/bin/env bash
    set -uo pipefail
    echo "--- Units ---"
    if [[ -f "$HOME/.config/containers/systemd/nomad-admin.container.d/10-autostart.conf" ]]; then
        BOOT="enabled"
    else
        BOOT="disabled"
    fi
    for u in nomad-admin nomad-mysql nomad-redis; do
        # is-active prints the state on stdout AND exits non-zero for anything but active, so
        # `|| true` is the right guard; `|| echo <fallback>` would print two words on one line.
        if [[ "$u" == "nomad-admin" ]]; then
            printf '%-16s %s (boot: %s)\n' "$u" "$(systemctl --user is-active "$u.service" 2>/dev/null || true)" "$BOOT"
        else
            printf '%-16s %s\n' "$u" "$(systemctl --user is-active "$u.service" 2>/dev/null || true)"
        fi
    done
    echo "--- Containers ---"
    # Only the OPENING braces are escaped below, and the asymmetry is real. Measured: four
    # open-braces collapse to two, but four close-braces stay four — closing braces are not
    # interpolation syntax, so they need no escape at all. Quadrupling both sides, which is
    # the obvious-looking fix, renders a Go template with two stray closing braces: accepted
    # by just, rejected by podman, i.e. an error that surfaces as far from its cause as
    # possible. Note this applies to comments too — writing the raw token in prose anywhere
    # in a recipe body breaks the parse, which is how this comment got rewritten twice.
    podman ps --filter name=nomad_ --format 'table {{{{.Names}}\t{{{{.Status}}' 2>/dev/null || true
    echo "--- GPU (NVIDIA) ---"
    nvidia-smi --query-gpu=name,memory.total,memory.used,memory.free,utilization.gpu --format=csv 2>/dev/null || true
    echo "--- Disco /var/srv/nomad ---"
    du -sh /var/srv/nomad/* 2>/dev/null || true
    echo "--- btrfs nodatacow nos bancos (C = correto) ---"
    lsattr -d /var/srv/nomad/mysql /var/srv/nomad/redis 2>/dev/null || true
    echo "--- arquivos inalcançáveis pelos containers rootless ---"
    # A rootless container's user namespace maps exactly {1000} plus this user's subuid range.
    # A file owned by anything else cannot be chowned, or often even removed, from inside —
    # not by container root, not by `podman unshare`. That is not a cosmetic problem: a single
    # 89-byte redis snapshot owned by a raw uid put nomad-redis in a restart loop with
    #     chown: ./dump.rdb: Operation not permitted
    # as the only symptom, and took the entire stack down through Requires=. Nothing in that
    # message mentions ownership, namespaces or subuids, which is why this check exists.
    SUB_START=$(awk -F: -v u="$USER" '$1==u {print $2; exit}' /etc/subuid 2>/dev/null)
    SUB_LEN=$(awk -F: -v u="$USER" '$1==u {print $3; exit}' /etc/subuid 2>/dev/null)
    if [[ -n "${SUB_START:-}" && -n "${SUB_LEN:-}" ]]; then
        BAD=$(find /var/srv/nomad -printf '%U %p\n' 2>/dev/null |
            awk -v me="$(id -u)" -v s="$SUB_START" -v e="$((SUB_START + SUB_LEN - 1))" \
                '$1 != me && ($1 < s || $1 > e)')
        if [[ -n "$BAD" ]]; then
            echo "$BAD" | sed 's/^/    ⚠️  uid /'
            echo "    Corrija com: sudo chown $(id -u):$(id -g) <arquivo>   (ou remova, se for descartável)"
        else
            echo "    (nenhum — todos dentro de {$(id -u)} ∪ [$SUB_START, $((SUB_START + SUB_LEN - 1))])"
        fi
    else
        echo "    (sem faixa de subuid para $USER em /etc/subuid — rootless não funcionaria)"
    fi

# 🔄 Atualizar as imagens pinadas mantendo os dados intactos
[group('NOMAD')]
nomad-update:
    #!/usr/bin/env bash
    set -euo pipefail
    # Digests are pinned inline in the Quadlet units and bumped by Renovate, so "update" means
    # "fetch what the current image pins", not "move to latest". A real version bump arrives
    # through a rebase, not through here.
    echo "Puxando as imagens pinadas pelas units..."
    grep -h '^Image=' /etc/containers/systemd/users/nomad-*.container | cut -d= -f2- | while read -r img; do
        echo "  $img"
        podman pull "$img"
    done
    systemctl --user restart nomad-admin.service
    echo "✅ Project NOMAD atualizado."

# 🦙 Subir o nomad-llama: llama-swap + llama.cpp CUDA (OpenAI-compatível, opcional DX)
# Config do usuário: ~/.config/llama-swap/config.yaml (semeado do exemplo se não existir).
# Contrato completo (paths no container, portas): nomad-llama.container.
[group('NOMAD')]
llama-up:
    #!/usr/bin/env bash
    set -euo pipefail
    # Os três gates de GPU são declarativos na imagem, mas só valem depois do rebase — então
    # checa em vez de assumir: o llama-server aborta com um erro que não aponta a causa.
    if ! systemctl is-active --quiet nvidia-persistenced.service; then
        echo "⚠️  nvidia-persistenced parado — a injeção CDI vai falhar."
    fi
    if [[ "$(getsebool container_use_devices 2>/dev/null || echo '--> off')" == *off ]]; then
        echo "⚠️  container_use_devices=off — o container vai receber Permission denied nos devices."
    fi
    CFG="$HOME/.config/llama-swap/config.yaml"
    if [[ ! -e "$CFG" ]]; then
        mkdir -p "$(dirname "$CFG")"
        cp /usr/share/nomad-llama/config.example.yaml "$CFG"
        echo "📝 Config inicial criada em $CFG (exemplo com Qwen3.5-4B)."
        echo "   Pesos do exemplo: ujust llama-models-fetch"
    fi
    systemctl --user start nomad-llama.service
    echo "✅ nomad-llama ativo. Host: http://127.0.0.1:61383/v1   Stack: http://llama:8080/v1"
    curl -s -m 5 http://127.0.0.1:61383/v1/models | jq -r '"   modelos: " + ([.data[].id] | join(", "))' 2>/dev/null || true

[group('NOMAD')]
llama-down:
    systemctl --user stop nomad-llama.service
    echo "🛑 nomad-llama parado. VRAM liberada."

# Reinicia (necessário quando o config.yaml é SUBSTITUÍDO — edição in-place recarrega sozinha)
[group('NOMAD')]
llama-restart:
    systemctl --user restart nomad-llama.service
    echo "🔄 nomad-llama reiniciado."

# 🧹 Descarregar o modelo ativo da VRAM sem parar o serviço
[group('NOMAD')]
llama-unload:
    curl -s -m 30 -X POST http://127.0.0.1:61383/api/models/unload -o /dev/null && echo "✅ Modelo descarregado."

[group('NOMAD')]
llama-status:
    #!/usr/bin/env bash
    set -uo pipefail
    STATE=$(systemctl --user is-active nomad-llama.service 2>/dev/null || true)
    if [[ -f "$HOME/.config/containers/systemd/nomad-llama.container.d/10-autostart.conf" ]]; then BOOT=enabled; else BOOT=disabled; fi
    printf "%-12s %s (boot: %s)\n" "llama:" "${STATE:-inactive}" "$BOOT"
    CFG="$HOME/.config/llama-swap/config.yaml"
    printf "%-12s %s\n" "config:" "$( [[ -e "$CFG" ]] && readlink -f "$CFG" || echo 'ausente (ujust llama-up cria)')"
    if [[ "$STATE" == "active" ]]; then
        curl -s -m 5 http://127.0.0.1:61383/v1/models | jq -r '"modelos:     " + ([.data[].id] | join(", "))' 2>/dev/null || true
        curl -s -m 5 http://127.0.0.1:61383/running | jq -r '"carregado:   " + ([.running[]? | "\(.model) (\(.state))"] | join(", ") | if . == "" then "nenhum" else . end)' 2>/dev/null || true
    fi
    llama-models-fetch --list 2>/dev/null | sed 's/^/pesos:       /' || true

[group('NOMAD')]
llama-enable-boot:
    #!/usr/bin/env bash
    set -euo pipefail
    DROPIN_DIR="$HOME/.config/containers/systemd/nomad-llama.container.d"
    mkdir -p "$DROPIN_DIR"
    printf "[Install]\nWantedBy=default.target\n" > "$DROPIN_DIR/10-autostart.conf"
    systemctl --user daemon-reload
    just llama-up
    echo "⚡ nomad-llama habilitado no boot."

[group('NOMAD')]
llama-disable-boot:
    #!/usr/bin/env bash
    set -uo pipefail
    rm -f "$HOME/.config/containers/systemd/nomad-llama.container.d/10-autostart.conf"
    rmdir "$HOME/.config/containers/systemd/nomad-llama.container.d" 2>/dev/null || true
    systemctl --user daemon-reload
    echo "🔌 nomad-llama removido do boot."

# 📥 Baixar pesos GGUF do catálogo (retomável, sha256 verificado) para /var/srv/nomad/gguf
# Catálogo: $LLAMA_MODELS_CATALOG, ~/.config/llama-swap/catalog.json ou o exemplo da imagem.
[group('NOMAD')]
llama-models-fetch *ids:
    llama-models-fetch {{ ids }}
alias nomad-models-fetch := llama-models-fetch

# 🧹 Purgar a VRAM imediatamente (descarrega os modelos do nomad-llama)
[group('NOMAD')]
llm-vram-purge:
    #!/usr/bin/env bash
    set -uo pipefail
    if systemctl --user is-active --quiet nomad-llama.service; then
        curl -s -m 30 -X POST http://127.0.0.1:61383/api/models/unload -o /dev/null && echo "🧹 nomad-llama: modelos descarregados."
    fi
    nvidia-smi --query-gpu=memory.used,memory.total --format=csv,noheader 2>/dev/null | sed 's/^/   VRAM: /' || true

alias vram-purge := llm-vram-purge

# ⚖️ Analisar compatibilidade de LLMs locais com a GPU RTX 3060 (6GB) e 64GB RAM (llmfit)
[group('NOMAD')]
llm-fit +ARGS="fit":
    #!/usr/bin/env bash
    if command -v llmfit >/dev/null 2>&1; then
        llmfit {{ ARGS }}
    elif command -v uvx >/dev/null 2>&1; then
        uvx llmfit {{ ARGS }}
    else
        echo "❌ Nem llmfit nem uvx encontrados. Use 'mise use -g uv' ou 'uv tool install llmfit'."
        exit 1
    fi

# 🎯 Recomendar o melhor LLM local com benchmarks reais (whichllm)
[group('NOMAD')]
llm-which +ARGS="--speed usable --vram-headroom auto":
    #!/usr/bin/env bash
    if command -v whichllm >/dev/null 2>&1; then
        whichllm {{ ARGS }}
    elif command -v uvx >/dev/null 2>&1; then
        uvx whichllm@latest {{ ARGS }}
    else
        echo "❌ Nem whichllm nem uvx encontrados. Instale com 'uv tool install whichllm' ou via mise."
        exit 1
    fi

alias which-llm := llm-which

# 🧠 Guia de dimensionamento de LLM para Dell G15 (6GB VRAM + 64GB DDR5), medido neste hardware
[group('NOMAD')]
llm-advisor:
    #!/usr/bin/env bash
    set -euo pipefail
    cat << 'EOF'
    ================================================================================
    🧠 DIRETRIZES DE LLM: DELL G15 5520 (RTX 3060 6GB + 64GB DDR5 + i7-12700H)
    Backend: nomad-llama (llama-swap + llama.cpp CUDA) — ujust llama-up
    ================================================================================

    📌 O LIMITE REAL É O KV CACHE, NÃO OS PESOS
    --------------------------------------------------------------------------------
    • 7-8B denso com atenção plena em todas as camadas: KV não cabe na VRAM com
      contexto útil (OOM a 16k); com KV em RAM (--no-kv-offload) o decode cai
      ~56 → 24 → 15 tok/s em 0/8k/16k. Sempre meça com contexto PREENCHIDO
      (llama-bench -d), não só -c.
    • Modelos de atenção híbrida (Gated DeltaNet 3:1, sliding window) têm KV 3-4×
      menor: é isso que viabiliza 48-64k de contexto em 6 GB.

    1. TUDO NA VRAM — denso pequeno híbrido (ex: Qwen3.5-4B Q4_K_XL)
       • ~80 tok/s (≈116 com MTP --spec-type draft-mtp), 45 tok/s a 64k de contexto.
       • Visão via mmproj (--no-mmproj-offload se faltar VRAM).

    2. MoE COM EXPERTS NA CPU — melhor qualidade (ex: Qwen3.6-35B-A3B Q4_K)
       • --n-cpu-moe <nº de camadas> (todos na CPU) + atenção/KV na GPU: ~4 GB VRAM,
         ~41 tok/s, 64k de contexto; -ub 2048 = prefill 2.4× mais rápido.
       • Quant uniforme Q4_K > UD (tensores Q5/Q6) > IQ4_XS com experts na CPU.
       • MTP rende pouco aqui (+8%) e custa ~0.9 GB de VRAM.

    3. NÃO VALE: denso 27B+ (não cabe na GPU; na CPU ~2-3 tok/s).

    ⚠️ REGRAS
    --------------------------------------------------------------------------------
    • CUDA, não Vulkan: +15% decode (KV na GPU), +40-50% (KV em RAM), e no MoE o
      Vulkan fez 23 vs 31 tok/s e OOM a 32k.
    • KV q8_0 (-ctk/-ctv) + -fa on; 1 thread por P-core (-t 6 -C 0x555).
    • Evite Q2/Q3 brutos; prefira modelo menor em Q4_K/Q5_K.
    • Abliteration varia por modelo: meça antes de adotar (uma variante 4B perdeu
      a capacidade de código; a 35B-A3B não perdeu nada mensurável).
    • Embedding em CPU (CUDA_VISIBLE_DEVICES=) num grupo persistente do llama-swap:
      convive com o chat sem disputar VRAM.

    🔧 FERRAMENTAS
    --------------------------------------------------------------------------------
    • ujust llm-fit        -> Medição e avaliação de modelos via llmfit (TUI/CLI)
    • ujust which-llm      -> Recomendação baseada em benchmarks via whichllm
    • ujust llama-models-fetch -> Pesos GGUF do catálogo (sha256)
    ================================================================================
    EOF

# 🗂️ Shell com o mapeamento de UID do rootless, para mexer nos arquivos do NOMAD
[group('NOMAD')]
nomad-shell:
    #!/usr/bin/env bash
    set -euo pipefail
    # Rootless containers write as subordinate UIDs: a file created by MySQL (uid 999 inside)
    # lands as 524288+998 on the host, which your own account cannot read, chown or even
    # delete. That is not a misconfiguration, it is how user namespaces work — and it is why
    # `rm -rf` on NOMAD data fails with Permission denied. `podman unshare` enters the same
    # namespace, where those files are owned by root and behave normally.
    echo "Namespace de usuário do podman. Os arquivos de /var/srv/nomad ficam manipuláveis aqui."
    echo "Saia com 'exit'."
    podman unshare bash

# 🔒 Expor o Command Center no Tailnet via Tailscale Serve (porta 61380)
[group('NOMAD')]
remote-nomad-setup:
    #!/usr/bin/env bash
    set -euo pipefail
    DNS_NAME=$(tailscale status --self --json 2>/dev/null | jq -r '.Self.DNSName' | sed 's/\.$//')
    if [[ -z "$DNS_NAME" || "$DNS_NAME" == "null" ]]; then
        echo "❌ Não consegui ler o nome DNS do tailnet. O tailscaled está rodando e logado?"
        exit 1
    fi
    # Shared helper: it asks `serve status --json` for the listener/target pair rather than
    # grepping for the target alone, which is what let a service published on the wrong
    # endpoint read as "already correct" for as long as it did. It also handles the permission
    # case, so a missing --operator no longer aborts before the .env fix below runs.
    if ! /usr/libexec/bazzite-dx-serve ensure 61380; then
        echo "O NOMAD continua em 127.0.0.1:61380; só falta o proxy do tailnet."
        exit 0
    fi
    # AdonisJS builds absolute links and CORS from URL. Left at localhost it keeps emitting
    # localhost URLs to a browser that reached the machine over the tailnet, which breaks
    # redirects and asset paths in ways that look like an application bug.
    NEW_URL="https://${DNS_NAME}:61380"
    if grep -q "^URL=${NEW_URL}$" /var/srv/nomad/.env 2>/dev/null; then
        echo "URL já aponta para $NEW_URL."
    else
        sed -i "s|^URL=.*|URL=${NEW_URL}|" /var/srv/nomad/.env
        echo "URL do .env atualizada para $NEW_URL."
        systemctl --user try-restart nomad-admin.service
    fi
    echo "✅ Command Center remoto: $NEW_URL"

# 🔓 Remover o Command Center do Tailnet e devolver a URL para localhost
[group('NOMAD')]
remote-nomad-teardown:
    #!/usr/bin/env bash
    set -uo pipefail
    /usr/libexec/bazzite-dx-serve off 61380 || true
    if [[ -f /var/srv/nomad/.env ]]; then
        sed -i 's|^URL=.*|URL=http://localhost:61380|' /var/srv/nomad/.env
        systemctl --user try-restart nomad-admin.service
    fi
    echo "🔓 NOMAD removido do tailnet; URL de volta para http://localhost:61380."

# 🔥 Liberar as portas do NOMAD no firewall para a rede local / hotspot
[group('NOMAD')]
nomad-firewall-on:
    #!/usr/bin/env bash
    set -euo pipefail
    # The whole body used to sit inside `if command -v firewall-cmd`, with no else — so on a
    # host without firewalld this exited 0 having done nothing, which is the silent fallback
    # the inner message claimed to be guarding against.
    if ! command -v firewall-cmd >/dev/null 2>&1; then
        echo "❌ firewall-cmd não encontrado — não há firewalld neste host para configurar." >&2
        exit 1
    fi
    if ! sudo firewall-cmd --add-service=project-nomad --permanent; then
        echo "⚠️  Serviço firewalld 'project-nomad' indisponível — rode 'just check'/rebuild da imagem" \
             "para instalar a definição." >&2
        exit 1
    fi
    sudo firewall-cmd --reload
    echo "✅ Porta 61380 liberada na rede local."
    echo "   Sobre o tailnet isto é desnecessário: tailscale0 já está na zona 'trusted'."

# 🧯 Fechar as portas do NOMAD no firewall
[group('NOMAD')]
nomad-firewall-off:
    #!/usr/bin/env bash
    set -euo pipefail
    if ! command -v firewall-cmd >/dev/null 2>&1; then
        echo "❌ firewall-cmd não encontrado." >&2
        exit 1
    fi
    sudo firewall-cmd --remove-service=project-nomad --permanent || true
    sudo firewall-cmd --reload
    echo "🧯 Portas do NOMAD fechadas na rede local."
