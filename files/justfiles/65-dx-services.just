# vim: set ft=make :
# ==============================================================================
# GROUP: services (Unified Quadlet Lifecycle Controller)
#
# Single data-driven entrypoint for all rootless Podman Quadlets under
# /etc/containers/systemd/users/. Delegates to /usr/libexec/dx-svc.
# ==============================================================================

# Gerenciar serviços Quadlet (status | up | down | restart | logs | remote | boot | prefetch | offline | prune)
[group('services')]
svc ACTION="" *ARGS:
    #!/usr/bin/env bash
    set -euo pipefail
    BIN="/usr/libexec/dx-svc"
    if [[ ! -x "$BIN" ]]; then
        BIN="{{ justfile_directory() }}/../system/usr/libexec/dx-svc"
    fi
    if [[ -z "{{ ACTION }}" ]]; then
        exec "$BIN"
    fi
    exec "$BIN" "{{ ACTION }}" {{ ARGS }}
