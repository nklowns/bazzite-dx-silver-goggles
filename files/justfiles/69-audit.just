# vim: set ft=make :
# ==============================================================================
# GROUP: audit — Read-only audits (boot, ports, security, disk)
# ==============================================================================

# Auditorias read-only do host. Opções: boot | ports | security | disk | all
[group('audit')]
audit ACTION="":
    #!/usr/bin/env bash
    set -uo pipefail
    OPT="{{ ACTION }}"
    if [[ -z "$OPT" ]]; then
        if [[ -t 0 && -t 1 ]] && command -v ugum >/dev/null 2>&1; then
            OPT="$(ugum choose --header "Auditoria read-only:" "boot" "ports" "security" "disk" "all")" || exit 0
        else
            OPT="all"
        fi
    fi

    DX_SVC="/usr/libexec/dx-svc"
    [[ -x "$DX_SVC" ]] || DX_SVC="{{ justfile_directory() }}/../system/usr/libexec/dx-svc"

    run_boot() {
        echo "=== Sistema: habilitado no host, ausente na imagem, preset=disabled ==="
        local img host found unit preset missing entry linger AL_USER LOCK
        img="$(mktemp)"; host="$(mktemp)"
        find /usr/etc/systemd/system -mindepth 2 -maxdepth 2 -path '*.wants/*' -printf '%f\n' 2>/dev/null | sort -u >"$img"
        find /etc/systemd/system -mindepth 2 -maxdepth 2 -path '*.wants/*' -printf '%f\n' 2>/dev/null | sort -u >"$host"
        found=0
        while IFS= read -r unit; do
            [[ -n "$unit" ]] || continue
            preset="$(systemctl list-unit-files --no-legend "$unit" 2>/dev/null | awk '{print $3}')"
            [[ "$preset" == "disabled" ]] || continue
            printf '  %-40s (preset: %s)\n' "$unit" "${preset:-?}"
            found=1
        done < <(comm -13 "$img" "$host")
        [[ "$found" -eq 1 ]] || echo "  (nenhum)"
        rm -f "$img" "$host"

        echo
        echo "=== Sistema: a IMAGEM habilita, o host não (deleção local preservada pelo ostree) ==="
        img="$(mktemp)"; host="$(mktemp)"
        find /usr/etc/systemd/system -mindepth 2 -maxdepth 2 -path '*.wants/*' -printf '%P\n' 2>/dev/null | sort -u >"$img"
        find /etc/systemd/system -mindepth 2 -maxdepth 2 -path '*.wants/*' -printf '%P\n' 2>/dev/null | sort -u >"$host"
        missing=0
        while IFS= read -r entry; do
            [[ -n "$entry" ]] || continue
            printf '  %s\n' "$entry"
            missing=1
        done < <(comm -23 "$img" "$host")
        if [[ "$missing" -eq 1 ]]; then
            echo "  Reativar: sudo systemctl enable --now <unit>"
        else
            echo "  (nenhum)"
        fi
        rm -f "$img" "$host"

        echo
        echo "=== Usuário: habilitado em \$HOME ==="
        if [[ -d "$HOME/.config/systemd/user" ]]; then
            find "$HOME/.config/systemd/user" -path '*.wants/*' -printf '  %f\n' 2>/dev/null | sort -u
        fi
        if [[ -d "$HOME/.config/containers/systemd" ]]; then
            find "$HOME/.config/containers/systemd" -name "10-autostart.conf" 2>/dev/null | while IFS= read -r f; do
                printf '  %s (Quadlet drop-in)\n' "$(basename "$(dirname "$f")" .container.d).service"
            done | sort -u
        fi

        echo
        linger="$(loginctl show-user "$USER" -p Linger --value 2>/dev/null || echo unknown)"
        if [[ "$linger" == "yes" ]]; then
            echo "⚠️  Linger=yes — units de usuário acima sobem no BOOT."
        else
            echo "Linger=$linger — units de usuário sobem no login."
        fi

        echo
        echo "=== Autologin e bloqueio ==="
        AL_USER="$(grep -oP '^\s*User=\K.*' /etc/plasmalogin.conf 2>/dev/null | tail -1 || true)"
        if [[ -z "$AL_USER" ]]; then
            echo "  autologin: não configurado"
        elif ! id "$AL_USER" >/dev/null 2>&1; then
            echo "  ⚠️  autologin aponta para '$AL_USER' (inexistente)"
        else
            echo "  autologin: $AL_USER"
        fi
        LOCK="$(systemctl --user is-enabled lock-on-session-start.service 2>/dev/null || true)"
        LOCK="${LOCK:-ausente}"
        if [[ -n "$AL_USER" && "$LOCK" != "enabled" ]]; then
            echo "  ⚠️  bloqueio na sessão: $LOCK — corrija com: ujust autologin setup"
        else
            echo "  bloqueio na sessão: $LOCK"
        fi

        echo
        echo "=== Custo medido do boot ==="
        systemd-analyze 2>/dev/null | head -1
        echo "--- sistema (top 5) ---"
        systemd-analyze blame --no-pager 2>/dev/null | head -5
        echo "--- usuário (top 5) ---"
        systemd-analyze --user blame --no-pager 2>/dev/null | head -5
    }

    run_ports() {
        echo "=== Serviços DX na faixa reservada (61300-61399) ==="
        ss -tlnH 2>/dev/null | awk '{print $4}' | grep -oE '[0-9]+$' | sort -un |
            awk '$1 >= 61300 && $1 <= 61399 {printf "  %s\n", $1}' || true
        echo
        echo "=== Portas comuns de desenvolvimento ocupadas ==="
        local busy=0 unknown=0 p line who
        for p in 3000 5173 6333 6334 8080 8081 8090 8100 8200 8400 8410 8420 8430 8440 8450 8470 8480 8490 8500 9090 11434; do
            line="$(ss -tlnpH "sport = :$p" 2>/dev/null | head -1 || true)"
            [[ -n "$line" ]] || continue
            who="$(printf '%s' "$line" | grep -oE 'users:\(\("[^"]+' | sed 's/.*"//' | head -1 || true)"
            if [[ -z "$who" ]]; then who="(processo oculto — root)"; unknown=1; fi
            printf '  %-6s %s\n' "$p" "$who"
            busy=1
        done
        [[ "$busy" -eq 1 ]] || echo "  (nenhuma)"
        [[ "$unknown" -eq 0 ]] || echo "  Para ver processos de root: sudo ujust audit ports"
        echo
        echo "=== Endpoints publicados no tailnet ==="
        if [[ -x /usr/libexec/bazzite-dx-serve ]]; then
            local port
            for port in 61337 61380 61384 61385 61386 61387 61389 61390 61392 61395; do
                printf '  %-6s %s\n' "$port" "$(/usr/libexec/bazzite-dx-serve status "$port" 2>/dev/null || echo 'erro')"
            done
        fi
    }

    run_security() {
        echo "=== 1. Superfície de Rede & Daemons Expostos ==="
        if ss -tlnH 'sport = :44322 or sport = :44323' 2>/dev/null | grep -qE '(0\.0\.0\.0|\[::\])'; then
            echo "  ❌ PCP escutando em 0.0.0.0"
        elif ss -tlnH 'sport = :44322 or sport = :44323' 2>/dev/null | grep -q '127\.0\.0\.1'; then
            echo "  ✅ PCP restrito a localhost (44322/44323)."
        else
            echo "  ✅ PCP desativado."
        fi
        if ss -ulnH 'sport = :5355' 2>/dev/null | grep -q '5355'; then
            echo "  ⚠️  LLMNR escutando na porta 5355 UDP."
        else
            echo "  ✅ LLMNR desativado."
        fi
        printf "  SSH no boot: %s | Samba no boot: %s\n" \
            "$(systemctl is-enabled sshd.service 2>/dev/null || echo disabled)" \
            "$(systemctl is-enabled smb.service 2>/dev/null || echo disabled)"

        echo
        echo "=== 2. Firewall ==="
        if command -v firewall-cmd >/dev/null 2>&1; then
            local def_zone
            def_zone="$(firewall-cmd --get-default-zone 2>/dev/null || echo desconhecido)"
            echo "  Zona padrão: $def_zone"
            [[ "$def_zone" == "FedoraWorkstation" ]] && echo "  ⚠️  FedoraWorkstation abre 1025-65535 na LAN. Recomendado: public."
            firewall-cmd --get-active-zones 2>/dev/null | sed 's/^/  /'
        fi

        echo
        echo "=== 3. Sunshine UPnP ==="
        local sunshine_conf="$HOME/.var/app/dev.lizardbyte.app.Sunshine/config/sunshine/sunshine.conf"
        if [[ -f "$sunshine_conf" ]]; then
            if grep -qE '^\s*upnp\s*=\s*enabled' "$sunshine_conf"; then
                echo "  ❌ Sunshine UPnP ativado!"
            else
                echo "  ✅ Sunshine UPnP desativado."
            fi
        fi

        echo
        echo "=== 4. Flatpak overrides de risco ==="
        local leak_found=0 override_dir f app
        for override_dir in "/var/lib/flatpak/overrides" "$HOME/.local/share/flatpak/overrides"; do
            [[ -d "$override_dir" ]] || continue
            for f in "$override_dir"/*; do
                [[ -f "$f" ]] || continue
                app="$(basename "$f")"
                if grep -q 'org.freedesktop.Flatpak=talk' "$f" 2>/dev/null; then
                    echo "  ❌ $app ($override_dir): org.freedesktop.Flatpak=talk"
                    leak_found=1
                fi
                if grep -qE 'filesystems=.*host' "$f" 2>/dev/null; then
                    echo "  ⚠️  $app ($override_dir): filesystems=host"
                    leak_found=1
                fi
            done
        done
        [[ "$leak_found" -eq 0 ]] && echo "  ✅ Nenhum escape crítico."

        echo
        echo "=== 5. Sockets em 0.0.0.0 ==="
        ss -tulnH 'src = 0.0.0.0' 2>/dev/null | awk '{print "  " $1 " " $5}' | sort -u || echo "  (nenhum)"

        echo
        echo "=== 6. Btrfs nodatacow (+C) em /var/srv ==="
        local tmpfiles_dir="/usr/lib/tmpfiles.d" srv_dir tf
        [[ -d "$tmpfiles_dir" ]] || tmpfiles_dir="{{ justfile_directory() }}/../system/usr/lib/tmpfiles.d"
        while IFS= read -r srv_dir; do
            [[ -d "$srv_dir" ]] || continue
            if lsattr -d "$srv_dir" 2>/dev/null | awk '{print $1}' | grep -q 'C'; then
                echo "  ✅ $srv_dir (+C)"
            else
                echo "  ⚠️  $srv_dir sem +C (sudo chattr +C $srv_dir)"
            fi
        done < <(
            for tf in "$tmpfiles_dir"/*.conf; do
                [[ -r "$tf" ]] || continue
                awk '$1 == "h" && $2 ~ /^\/var\/srv\// && $NF ~ /\+C/ {print $2}' "$tf"
            done | sort -u
        )
    }

    run_disk() {
        echo "=== 1. Filesystems ==="
        df -h / /var "$HOME" 2>/dev/null | awk 'NR==1 || !seen[$1]++'
        echo
        echo "=== 2. /var/srv (Dados, Modelos & Pesos) ==="
        if [[ -d /var/srv ]]; then
            du -sh /var/srv/* /var/srv/nomad/* 2>/dev/null | sort -hr | head -n 15 | sed 's/^/  /'
        fi
        echo
        echo "=== 3. Podman ==="
        podman system df 2>/dev/null | sed 's/^/  /' || true
        echo
        echo "=== 4. Quadlets órfãos & GGUFs retired (dry-run) ==="
        if [[ -x "$DX_SVC" ]]; then
            "$DX_SVC" prune | sed 's/^/  /'
        fi
        echo
        echo "=== 5. OSTree, Flatpak & Homebrew ==="
        if command -v rpm-ostree >/dev/null 2>&1; then
            echo "  OSTree deployments: $(rpm-ostree status --json 2>/dev/null | jq '.deployments | length' 2>/dev/null || echo '?')"
        fi
        if command -v flatpak >/dev/null 2>&1; then
            echo "  Flatpak apps/runtimes: $(flatpak list --columns=application 2>/dev/null | wc -l) (limpar órfãos: flatpak uninstall --unused)"
        fi
        if command -v brew >/dev/null 2>&1; then
            local bcache
            bcache="$(brew --cache 2>/dev/null || true)"
            [[ -d "$bcache" ]] && echo "  Homebrew cache: $(du -sh "$bcache" 2>/dev/null | cut -f1) (limpar: brew cleanup --prune=all)"
        fi
    }

    case "$OPT" in
    boot) run_boot ;;
    ports) run_ports ;;
    security) run_security ;;
    disk) run_disk ;;
    all)
        run_boot; echo
        run_ports; echo
        run_security; echo
        run_disk
        ;;
    help | -h | --help)
        echo "Uso: ujust audit <boot|ports|security|disk|all>"
        ;;
    *)
        echo "❌ Auditoria desconhecida: '$OPT'" >&2
        exit 2
        ;;
    esac
