# vim: set ft=make :
# ==============================================================================
# GROUP: Audit — make the policies in AGENTS.md checkable instead of aspirational
#
# Both recipes are read-only: no sudo, no state change, nothing to undo.
# ==============================================================================

# 🥾 O que sobe no boot fora do que a imagem declara
[group('Audit')]
boot-audit:
    #!/usr/bin/env bash
    set -uo pipefail
    # DRIFT IS AN INTERSECTION, and getting that wrong is why this recipe reads the way it
    # does. Three signals, none sufficient alone:
    #
    #   /usr/etc/systemd/system/*.wants/   what the IMAGE enabled. On ostree /usr/etc is the
    #                                      image's /etc and /etc is the live 3-way merge, so
    #                                      the baseline needs no generated artefact — it is
    #                                      already on every host and is replaced by a rebase.
    #   /etc/systemd/system/*.wants/       what is enabled now.
    #   the preset column                  whether systemd enabled it on first boot per
    #                                      policy, which is not a human decision.
    #
    # Diffing only the first two flags brew-update.timer, nvidia-persistenced and
    # waydroid-container — all preset=enabled, i.e. exactly what is supposed to happen. An
    # audit that cries wolf gets ignored, and an ignored audit is worse than none.
    #
    # `find`, not `ls`: ls is aliased to eza on this image and its output is not parseable.
    # This list is FACTS, not violations. Some entries are deliberate and correct — upstream's
    # own `ujust tailscale enable` turns on tailscaled.service, which ships preset=disabled, so
    # a tailscale-first machine will always show it here. The audit's job is to make the set
    # visible so a human can tell intent from accumulation; it cannot make that call itself.
    echo "=== Sistema: habilitado no host, ausente na imagem, preset=disabled ==="
    img=$(mktemp) host=$(mktemp)
    find /usr/etc/systemd/system -mindepth 2 -maxdepth 2 -path '*.wants/*' -printf '%f\n' 2>/dev/null | sort -u >"$img"
    find /etc/systemd/system -mindepth 2 -maxdepth 2 -path '*.wants/*' -printf '%f\n' 2>/dev/null | sort -u >"$host"
    found=0
    while IFS= read -r unit; do
        [ -n "$unit" ] || continue
        preset=$(systemctl list-unit-files --no-legend "$unit" 2>/dev/null | awk '{print $3}')
        # preset=enabled means systemd turned it on by policy on first boot, not a person.
        [ "$preset" = "disabled" ] || continue
        printf '  %-40s (preset: %s)\n' "$unit" "${preset:-?}"
        found=1
    done < <(comm -13 "$img" "$host")
    [ "$found" -eq 1 ] || echo "  (nenhum)"
    rm -f "$img" "$host"

    echo
    # THE OTHER DIRECTION, and the one that actually hurt. Everything above is "the host
    # enabled something extra". This is "the image enables it and the host does not" — which
    # is silent by construction: there is no failed unit, no error, the timer simply is not
    # there. `uupd.timer` sat like this and the machine stopped auto-updating with nothing to
    # show for it.
    #
    # The cause is ostree's /etc merge, not a build bug. A unit disabled locally once is
    # recorded as a deletion and preserved across every future deployment, no matter how many
    # times the image enables it — verified with `ostree admin config-diff`, which reports
    # them as `D`, and by finding the symlinks present in usr/etc of BOTH deployments on disk
    # while absent from the live /etc.
    #
    # Deliberately reported and not repaired. That merge behaviour is ostree working as
    # designed: a local administrative decision outranks the image, and some of these were
    # probably disabled on purpose. Re-enabling them from a boot service would override a
    # choice the OS went out of its way to protect. Surfacing it is the honest job; the fix
    # is one `systemctl enable` by someone who knows which of these they meant.
    echo "=== Sistema: a IMAGEM habilita, o host não (deleção local preservada pelo ostree) ==="
    img=$(mktemp) host=$(mktemp)
    find /usr/etc/systemd/system -mindepth 2 -maxdepth 2 -path '*.wants/*' -printf '%P\n' 2>/dev/null | sort -u >"$img"
    find /etc/systemd/system -mindepth 2 -maxdepth 2 -path '*.wants/*' -printf '%P\n' 2>/dev/null | sort -u >"$host"
    missing=0
    while IFS= read -r entry; do
        [ -n "$entry" ] || continue
        printf '  %s\n' "$entry"
        missing=1
    done < <(comm -23 "$img" "$host")
    if [ "$missing" -eq 1 ]; then
        echo "  Reativar o que você quiser de volta:  sudo systemctl enable --now <unit>"
    else
        echo "  (nenhum)"
    fi
    rm -f "$img" "$host"

    echo
    echo "=== Usuário: habilitado em \$HOME ==="
    # Every enablement symlink under ~/.config is local by construction — the image ships its
    # user units in /usr/lib/systemd/user and never enables them. So there is no baseline to
    # diff here; the whole list is the answer.
    if [ -d "$HOME/.config/systemd/user" ]; then
        find "$HOME/.config/systemd/user" -path '*.wants/*' -printf '  %f\n' 2>/dev/null | sort -u
    fi
    if [ -d "$HOME/.config/containers/systemd" ]; then
        find "$HOME/.config/containers/systemd" -name "10-autostart.conf" 2>/dev/null | while IFS= read -r f; do
            parent=$(basename "$(dirname "$f")")
            printf '  %s (Quadlet drop-in)\n' "${parent%.container.d}.service"
        done | sort -u
    fi

    echo
    linger=$(loginctl show-user "$USER" -p Linger --value 2>/dev/null || echo unknown)
    if [ "$linger" = "yes" ]; then
        echo "⚠️  Linger=yes — TUDO da lista de usuário acima sobe no BOOT, não no login,"
        echo "    e sobrevive ao logout. Ver a política de boot no AGENTS.md."
    else
        echo "Linger=$linger — units de usuário sobem no login."
    fi

    echo
    # Autologin decides whether this machine comes back on its own after a reboot, and every
    # way it can break is silent: the greeter simply appears, with no error and no log. That
    # matters more here than on a desktop, because sunshine.service carries
    # Requisite=graphical-session.target and cannot start until someone has logged in — so a
    # broken autologin means no remote access at all until a human walks over.
    echo "=== Autologin e bloqueio ==="
    AL_USER=$(grep -oP '^\s*User=\K.*' /etc/plasmalogin.conf 2>/dev/null | tail -1)
    if [[ -z "${AL_USER:-}" ]]; then
        echo "  autologin: não configurado (System Settings → Login Screen)"
        echo "             consequência: após um reboot o Sunshine só sobe quando alguém logar"
    elif ! id "$AL_USER" >/dev/null 2>&1; then
        echo "  ⚠️  autologin aponta para '$AL_USER', que NÃO EXISTE — a máquina para na tela de login"
    else
        echo "  autologin: $AL_USER"
    fi
    # The lock is the half that stops autologin from being a downgrade. Reported separately
    # because the dangerous state is not "both off" — it is autologin on with the lock off.
    # `|| true`, never `|| echo <fallback>`: is-enabled already prints the state on stdout AND
    # exits non-zero for anything but enabled, so a fallback yields both strings. The same trap
    # is documented for is-active in casting-status, and I walked straight into it here.
    LOCK=$(systemctl --user is-enabled lock-on-session-start.service 2>/dev/null || true)
    LOCK=${LOCK:-ausente}
    if [[ -n "${AL_USER:-}" && "$LOCK" != "enabled" ]]; then
        echo "  ⚠️  bloqueio na sessão: $LOCK — com autologin ligado, a sessão abre DESTRAVADA."
        echo "      Corrija com: ujust autologin-setup"
    else
        echo "  bloqueio na sessão: $LOCK"
    fi
    # Leftover from the first-run wizard: it rewrites autologin on every boot until
    # /etc/plasma-setup-done exists, which is what ClearAutologinObstacles creates.
    if [[ -f /etc/plasmalogin.conf.d/99-plasma-setup.conf ]]; then
        echo "  ⚠️  99-plasma-setup.conf presente — o assistente de primeiro boot ainda reescreve"
        echo "      o autologin a cada boot. Esperado antes do rebase que traz o conserto."
    fi

    echo
    echo "=== Custo medido do boot ==="
    systemd-analyze 2>/dev/null | head -1
    echo "--- sistema, 5 maiores ---"
    systemd-analyze blame --no-pager 2>/dev/null | head -5
    echo "--- usuário, 5 maiores ---"
    systemd-analyze --user blame --no-pager 2>/dev/null | head -5

# 🔌 Portas escutando vs a faixa reservada 61300-61399
[group('Audit')]
ports-audit:
    #!/usr/bin/env bash
    set -uo pipefail
    echo "=== Serviços DX na faixa reservada (61300-61399) ==="
    ss -tlnH 2>/dev/null | awk '{print $4}' | grep -oE '[0-9]+$' | sort -un |
        awk '$1 >= 61300 && $1 <= 61399 {printf "  %s\n", $1}' || true
    echo
    echo "=== Portas comuns de desenvolvimento ocupadas por serviço do sistema ==="
    # Not an exhaustive list of dev ports — these are the ones this layer or Project NOMAD
    # would plausibly be squatting. 8090/8100/8200/8400-8500 are the host ports that
    # service_seeder.ts assigns to Supply Depot apps; 11434 and 6333/6334 are Ollama's and
    # Qdrant's defaults. The Command Center reaches its own apps over the container network,
    # so nothing here needs a host port — but the seeder publishes them anyway, and NOMAD's
    # UI has a port field per app to change it.
    busy=0 unknown=0
    for p in 3000 5173 6333 6334 8080 8081 8090 8100 8200 8400 8410 8420 8430 8440 8450 8470 8480 8490 8500 9090 11434; do
        line=$(ss -tlnpH "sport = :$p" 2>/dev/null | head -1)
        [ -n "$line" ] || continue
        # `ss -p` only names the process for sockets the caller owns, so a root-owned listener
        # shows nothing when this runs unprivileged. Report the gap rather than printing a
        # bare "?" that reads like the port is broken.
        who=$(printf '%s' "$line" | grep -oE 'users:\(\("[^"]+' | sed 's/.*"//' | head -1)
        if [ -z "$who" ]; then who="(processo oculto — root)"; unknown=1; fi
        printf '  %-6s %s\n' "$p" "$who"
        busy=1
    done
    [ "$busy" -eq 1 ] || echo "  (nenhuma)"
    [ "$unknown" -eq 0 ] || echo "  Para ver os processos de root: sudo ujust ports-audit"
    echo
    echo "=== Exceções conhecidas — protocolo fixo, NÃO movíveis ==="
    # Listed so they are never mistaken for violations. The client picks the port in each of
    # these, so relocating them just breaks discovery.
    echo "  47984/47989/48010  Sunshine (Moonlight)"
    echo "  46899              FCast"
    echo "  7000/7100          AirPlay (uxplay)"
    echo "  1716               KDE Connect"
    echo
    echo "=== Endpoints publicados no tailnet ==="
    if [ ! -x /usr/libexec/bazzite-dx-serve ]; then
        echo "  (helper ausente nesta imagem — rebaseie para uma que o inclua)"
    else
        for port in 61337 61380 61381 61384 61385 61386 61387 61388 61390; do
            printf '  %-6s %s\n' "$port" "$(/usr/libexec/bazzite-dx-serve status "$port" 2>/dev/null || echo 'erro')"
        done
        echo "  misplaced = publicado num listener diferente da própria porta, que é como o"
        echo "  code-server acabou ocupando o domínio raiz do tailnet sem ninguém notar."
    fi
