# vim: set ft=make :
# ==============================================================================
# GROUP: system / setup — Bazzite-DX Core, Post-Upgrade & Brew Bundles
# ==============================================================================

# Gerenciar camada Bazzite-DX. Opções: doctor | kargs | post-upgrade | group [sync|list-all|list-active] | workspace [list|add|remove] | keybindings | ebpf
[group('system')]
dx ACTION="" *ARGS:
    #!/usr/bin/env bash
    set -euo pipefail
    DX_SVC="/usr/libexec/dx-svc"
    [[ -x "$DX_SVC" ]] || DX_SVC="{{ justfile_directory() }}/../system/usr/libexec/dx-svc"
    OPT="{{ ACTION }}"
    if [[ -z "$OPT" ]]; then
        if [[ -t 0 && -t 1 ]] && command -v ugum >/dev/null 2>&1; then
            OPT="$(ugum choose --header "Bazzite-DX:" \
                "doctor" "post-upgrade" "kargs" "group" "workspace" "keybindings" "ebpf")" || exit 0
        else
            OPT="doctor"
        fi
    fi
    # shellcheck disable=SC2086
    set -- {{ ARGS }}

    case "$OPT" in
    doctor)
        echo "=== Bazzite-DX: Medical Report ==="
        echo "1. Core Kernel Matrix:"
        grep -iE --color "iommu|kvm|vfio" /proc/cmdline || echo "Warning: Specialized kargs not detected!"
        if [[ -r /usr/lib/bootc/kargs.d/10-silver-goggles.toml ]]; then
            echo "   Declared kargs.d (converge com 'ujust dx kargs'):"
            while IFS= read -r karg; do
                if tr ' ' '\n' </proc/cmdline | grep -qxF "$karg"; then
                    echo "   [ OK ] $karg"
                else
                    echo "   [FAIL] $karg (run: ujust dx kargs)"
                fi
            done < <(grep -vE '^[[:space:]]*#' /usr/lib/bootc/kargs.d/10-silver-goggles.toml | grep -oE '"[^"]+"' | tr -d '"')
        fi
        echo -e "\n2. Architecture & Image:"
        [[ -f /usr/share/ublue-os/image-info.json ]] && jq -C . /usr/share/ublue-os/image-info.json
        echo -e "\n3. Developer Group Sync:"
        for grp in dialout video render plugdev docker libvirt incus-admin adbusers; do
            if groups "$USER" | grep -qw "$grp"; then
                echo "  [ OK ] $grp"
            elif getent group "$grp" >/dev/null 2>&1; then
                echo "  [FAIL] $grp (run: ujust dx group sync)"
            else
                echo "  [SKIP] $grp (not in system)"
            fi
        done
        echo -e "\n4. Experience Layer:"
        command -v bbrew >/dev/null && echo "  [ OK ] bbrew" || echo "  [WARN] bbrew absent"
        ;;
    kargs)
        readonly toml=/usr/lib/bootc/kargs.d/10-silver-goggles.toml
        [[ -r "$toml" ]] || { echo "error: $toml absent" >&2; exit 1; }
        mapfile -t declared < <(grep -vE '^[[:space:]]*#' "$toml" | grep -oE '"[^"]+"' | tr -d '"')
        pending="$(rpm-ostree kargs 2>/dev/null || cat /proc/cmdline)"
        mapfile -t applied < <(tr ' ' '\n' <<<"$pending")
        keys="$(printf '%s\n' "${applied[@]}" | cut -d= -f1)"
        missing=(); divergent=()
        for karg in "${declared[@]}"; do
            printf '%s\n' "${applied[@]}" | grep -qxF "$karg" && continue
            if printf '%s\n' "$keys" | grep -qxF "${karg%%=*}"; then
                divergent+=("$karg")
            else
                missing+=("$karg")
            fi
        done
        if [[ ${#missing[@]} -eq 0 && ${#divergent[@]} -eq 0 ]]; then
            echo "✅ Todos os ${#declared[@]} kargs declarados estão presentes."
            exit 0
        fi
        ((${#missing[@]})) && { printf 'missing (%d):\n' "${#missing[@]}"; printf '  %s\n' "${missing[@]}"; }
        ((${#divergent[@]})) && { printf 'divergent (%d):\n' "${#divergent[@]}"; printf '  %s\n' "${divergent[@]}"; }
        ((${#missing[@]})) || exit 0
        args=()
        for karg in "${missing[@]}"; do args+=("--append-if-missing=$karg"); done
        sudo rpm-ostree kargs "${args[@]}"
        echo "✅ Staged; reinicie para aplicar."
        ;;
    post-upgrade)
        auto_prefetch=false
        [[ "${1:-}" == "--prefetch" ]] && auto_prefetch=true
        echo "=== 1. Kernel Args (kargs.d) ==="
        if [[ -r /usr/lib/bootc/kargs.d/10-silver-goggles.toml ]]; then
            pending="$(rpm-ostree kargs 2>/dev/null || cat /proc/cmdline)"
            miss=0
            while IFS= read -r karg; do
                tr ' ' '\n' <<<"$pending" | grep -qxF "$karg" || { echo "  ⚠️  faltando: $karg"; miss=$((miss + 1)); }
            done < <(grep -vE '^[[:space:]]*#' /usr/lib/bootc/kargs.d/10-silver-goggles.toml | grep -oE '"[^"]+"' | tr -d '"')
            [[ "$miss" -eq 0 ]] && echo "  ✅ kargs em dia." || echo "  → Convergir com: ujust dx kargs"
        fi

        echo
        echo "=== 2. Cache Offline dos Quadlets (@sha256 pós-upgrade) ==="
        "$DX_SVC" status
        missing_svcs="$("$DX_SVC" status | awk '$5 == "missing" {print $1}')"
        if [[ -n "$missing_svcs" ]]; then
            echo
            echo "⚠️  Serviços sem imagem em cache local:"
            sed 's/^/  - /' <<<"$missing_svcs"
            if [[ "$auto_prefetch" == true ]]; then
                "$DX_SVC" prefetch all
            elif [[ -t 0 && -t 1 ]] && command -v ugum >/dev/null 2>&1; then
                if ugum confirm "Executar prefetch das imagens faltantes agora?"; then
                    "$DX_SVC" prefetch all
                fi
            else
                echo "  → Baixar para uso offline: ujust svc prefetch all"
            fi
        fi

        echo
        echo "=== 3. Driver NVIDIA, Waydroid & gpu-unlock ==="
        nv_ver="$(cat /sys/module/nvidia/version 2>/dev/null || nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null | head -1 || echo 'ausente')"
        echo "  NVIDIA driver ativo: $nv_ver"
        if systemctl list-unit-files waydroid-container.service >/dev/null 2>&1; then
            wd_st="$(systemctl is-active waydroid-container.service 2>/dev/null || true)"
            echo "  waydroid-container:  ${wd_st:-inactive}"
            if [[ "$wd_st" != "active" ]] && command -v waydroid-nvidia-setup >/dev/null 2>&1; then
                echo "  ℹ️  Se o driver mudou (ex.: $nv_ver), re-valide com: sudo waydroid-nvidia-setup"
            fi
        fi
        if [[ -f "/usr/lib/modules/$(uname -r)/extra/gpu_unlock.ko" ]]; then
            echo "  gpu_unlock.ko:       presente para $(uname -r)"
        else
            echo "  gpu_unlock.ko:       ausente para $(uname -r)"
        fi

        echo
        echo "=== 4. Armazenamento órfão (dry-run) ==="
        "$DX_SVC" prune | grep -E '^(Imagens órfãs|Encontrados |✅|Dry-run)' || true
        ;;
    group)
        CMD="${1:-}"
        if [[ -z "$CMD" ]]; then
            if [[ -t 0 && -t 1 ]] && command -v ugum >/dev/null 2>&1; then
                CMD="$(ugum choose --header "DX Groups:" "sync" "list-active" "list-all")" || exit 0
            else
                CMD="list-active"
            fi
        fi
        case "$CMD" in
        sync)
            if groups "$USER" | grep -qw "input"; then
                sudo gpasswd -d "$USER" input 2>/dev/null || true
            fi
            for grp in docker libvirt incus-admin dialout video render plugdev adbusers; do
                if getent group "$grp" >/dev/null; then
                    grep -q "^$grp:" /etc/group || grep "^$grp:" /usr/lib/group | sudo tee -a /etc/group >/dev/null
                    groups "$USER" | grep -qw "$grp" || sudo usermod -a -G "$grp" "$USER"
                fi
            done
            echo "✅ Grupos DX sincronizados (reabra a sessão para aplicar)."
            ;;
        list-all) getent group | cut -d: -f1 | sort ;;
        list-active) id -Gn | tr ' ' '\n' | sort ;;
        *) echo "Uso: ujust dx group <sync|list-active|list-all>" >&2; exit 2 ;;
        esac
        ;;
    workspace)
        sub="${1:-list}"
        target="${2:-}"
        CFG_FILE="$HOME/.config/bazzite-dx/workspaces.dirs"
        sync_recoll() {
            local dropin_dir="$HOME/.config/containers/systemd/mesh-recoll.container.d"
            local dropin_file="$dropin_dir/10-workspaces.conf"
            local topdirs="/export/Documents" line d bn
            if [[ -s "$CFG_FILE" ]]; then
                mkdir -p "$dropin_dir"
                { echo "# Generated from $CFG_FILE"; echo "[Container]"; } >"$dropin_file"
                while IFS= read -r line || [[ -n "$line" ]]; do
                    [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
                    d="${line/#\~/$HOME}"
                    if [[ -d "$d" ]]; then
                        bn="$(basename "$d")"
                        echo "Volume=$d:/export/$bn:ro" >>"$dropin_file"
                        topdirs="$topdirs /export/$bn"
                    fi
                done <"$CFG_FILE"
            else
                rm -f "$dropin_file"
            fi
            [[ -f "$HOME/.config/recoll/recoll.conf" ]] && sed -i "s|^topdirs = .*|topdirs = $topdirs|" "$HOME/.config/recoll/recoll.conf"
            systemctl --user daemon-reload 2>/dev/null || true
        }
        case "$sub" in
        list)
            if [[ -f "$CFG_FILE" ]]; then
                grep -v '^[[:space:]]*#' "$CFG_FILE" | grep -v '^[[:space:]]*$' || echo "(nenhum workspace registrado)"
            else
                echo "(nenhum workspace registrado — use: ujust dx workspace add ~/dev)"
            fi
            ;;
        add)
            [[ -n "$target" ]] || { [[ -t 0 ]] && target="$(ugum input --placeholder "Caminho (ex.: ~/dev)")" || { echo "Uso: ujust dx workspace add <dir>" >&2; exit 2; }; }
            target="$(realpath -m "${target/#\~/$HOME}")"
            mkdir -p "$HOME/.config/bazzite-dx" && chmod 700 "$HOME/.config/bazzite-dx"
            touch "$CFG_FILE" && chmod 600 "$CFG_FILE"
            grep -Fxq "$target" "$CFG_FILE" || echo "$target" >>"$CFG_FILE"
            sync_recoll
            echo "✅ Workspace registrado: $target"
            ;;
        remove)
            [[ -f "$CFG_FILE" ]] || { echo "Nenhum workspace registrado."; exit 0; }
            if [[ -z "$target" && -t 0 ]] && command -v ugum >/dev/null 2>&1; then
                # shellcheck disable=SC2046
                target="$(ugum choose $(grep -v '^[[:space:]]*#' "$CFG_FILE" | grep -v '^[[:space:]]*$'))" || exit 0
            fi
            [[ -n "$target" ]] || exit 0
            target="$(realpath -m "${target/#\~/$HOME}")"
            sed -i "\|^$target\$|d" "$CFG_FILE"
            sync_recoll
            echo "🗑️ Workspace removido: $target"
            ;;
        *) echo "Uso: ujust dx workspace <list|add <dir>|remove [dir]>" >&2; exit 2 ;;
        esac
        ;;
    keybindings)
        SCRIPT="/usr/libexec/bazzite-dx-ide-keybindings"
        [[ -x "$SCRIPT" ]] || SCRIPT="{{ justfile_directory() }}/../system/usr/libexec/bazzite-dx-ide-keybindings"
        "$SCRIPT"
        echo "✅ Atalhos de IDE sincronizados."
        ;;
    ebpf)
        sudo bpftop
        ;;
    help | -h | --help)
        echo "Uso: ujust dx <doctor|post-upgrade [--prefetch]|kargs|group <...>|workspace <...>|keybindings|ebpf>"
        ;;
    *)
        echo "❌ Ação desconhecida para dx: '$OPT'" >&2
        exit 2
        ;;
    esac

# Gerenciar Brewfiles (cli | ai | cncf | personal | all). Opções: install | check | cleanup | trust
[group('setup')]
brew ACTION="" FLAVOR="":
    #!/usr/bin/env bash
    set -euo pipefail
    OFFLINE_ENV="${XDG_CONFIG_HOME:-$HOME/.config}/dx-svc/offline.env"
    if [[ -f "$OFFLINE_ENV" ]]; then
        export HOMEBREW_NO_AUTO_UPDATE=1
    fi

    OPT="{{ ACTION }}"
    FLV="{{ FLAVOR }}"
    if [[ -z "$OPT" ]]; then
        if [[ -t 0 && -t 1 ]] && command -v ugum >/dev/null 2>&1; then
            OPT="$(ugum choose --header "Homebrew Bundles:" "check" "install" "cleanup" "trust")" || exit 0
        else
            OPT="check"
        fi
    fi

    if [[ "$OPT" == "trust" ]]; then
        command -v brew >/dev/null || { echo "❌ Homebrew não encontrado." >&2; exit 1; }
        brew tap | grep -vE '^(homebrew/)' | while read -r tap; do
            [[ -n "$tap" ]] && brew trust "$tap" || true
        done
        echo "✅ Taps confiados."
        exit 0
    fi

    if [[ -z "$FLV" ]]; then
        if [[ -t 0 && -t 1 ]] && command -v ugum >/dev/null 2>&1; then
            FLV="$(ugum choose --header "Flavor:" "personal" "cli" "ai" "cncf" "all")" || exit 0
        else
            FLV="all"
        fi
    fi

    BREW_DIR="/usr/share/ublue-os/homebrew"
    FILES=()
    case "$FLV" in
    cli) FILES=("$BREW_DIR/cli.Brewfile") ;;
    ai) FILES=("$BREW_DIR/ai-tools.Brewfile") ;;
    cncf) FILES=("$BREW_DIR/cncf.Brewfile") ;;
    personal) FILES=("$BREW_DIR/silver-goggles.Brewfile") ;;
    all) FILES=("$BREW_DIR/cli.Brewfile" "$BREW_DIR/ai-tools.Brewfile" "$BREW_DIR/cncf.Brewfile" "$BREW_DIR/dx-build.Brewfile" "$BREW_DIR/dx-fonts.Brewfile" "$BREW_DIR/silver-goggles.Brewfile") ;;
    *) echo "❌ Flavor desconhecido: '$FLV' (use cli|ai|cncf|personal|all)" >&2; exit 2 ;;
    esac

    OVERALL_RC=0
    for FILE in "${FILES[@]}"; do
        [[ -f "$FILE" ]] || continue
        case "$OPT" in
        install)
            if [[ "$(basename "$FILE")" == "silver-goggles.Brewfile" ]]; then
                flatpak remote-add --user --if-not-exists elyprismlauncher https://elyprismlauncher.github.io/flatpak/elyprismlauncher.flatpakref || true
            fi
            while read -r tap; do
                [[ -n "$tap" ]] && brew trust "$tap" || true
            done < <(grep -E '^tap "' "$FILE" | sed -E 's/tap "([^"]+)".*/\1/' || true)
            if ! brew bundle --file="$FILE"; then
                echo "⚠️  Falha no bundle $(basename "$FILE") — tentando entradas individualmente..."
                while read -r kind name; do
                    case "$kind" in
                    brew) brew list --formula "${name##*/}" &>/dev/null || brew install --formula "$name" || OVERALL_RC=1 ;;
                    cask) brew list --cask "${name##*/}" &>/dev/null || brew install --cask "$name" || OVERALL_RC=1 ;;
                    flatpak) flatpak info "$name" &>/dev/null || flatpak install -y "$name" || OVERALL_RC=1 ;;
                    esac
                done < <(grep -E '^(brew|cask|flatpak) "' "$FILE" | sed -E 's/^(brew|cask|flatpak) "([^"]+)".*/\1 \2/')
            fi
            ;;
        check) brew bundle check --file="$FILE" || OVERALL_RC=1 ;;
        cleanup) brew bundle cleanup --file="$FILE" ;;
        *) echo "Uso: ujust brew <install|check|cleanup|trust> [cli|ai|cncf|personal|all]" >&2; exit 2 ;;
        esac
    done
    exit "$OVERALL_RC"
