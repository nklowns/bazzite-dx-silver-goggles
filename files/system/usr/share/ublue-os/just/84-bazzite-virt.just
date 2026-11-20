# vim: set ft=make :

# Gerenciar virtualização (IOMMU/KVM, Windows/macOS guests, VFIO GPU passthrough). Opções: setup | win | mac | vfio
[group('hardware')]
virt ACTION="" *ARGS:
    #!/usr/bin/env bash
    set -euo pipefail
    OPT="{{ ACTION }}"
    if [[ -z "$OPT" ]]; then
        if [[ -t 0 && -t 1 ]] && command -v ugum >/dev/null 2>&1; then
            OPT="$(ugum choose --header "Virtualização:" "setup" "win" "mac" "vfio")" || exit 0
        else
            echo "Uso: ujust virt <setup|win|mac|vfio> [opções]" >&2
            exit 2
        fi
    fi
    case "$OPT" in
    setup) /usr/libexec/bazzite-dx-virt-setup {{ ARGS }} ;;
    win) /usr/libexec/bazzite-dx-win-utils {{ ARGS }} ;;
    mac) /usr/libexec/bazzite-dx-macos-utils {{ ARGS }} ;;
    vfio) /usr/libexec/bazzite-dx-manage-vfio {{ ARGS }} ;;
    help | -h | --help) echo "Uso: ujust virt <setup|win|mac|vfio> [opções]" ;;
    *) echo "❌ Ação desconhecida para virt: '$OPT'" >&2; exit 2 ;;
    esac
