# Normalizes HOME to /var/home/$USER for OSTree deployments across all login/SSH/TTY shells.
# Ensures path parity with systemd user session and GUI applications.

if string match -q '/home/*' "$HOME"; and test -d "/var$HOME"
    set -gx HOME "/var$HOME"
end

if string match -q '/home/*' "$PWD"; and test -d "/var$PWD"
    builtin cd "/var$PWD" >/dev/null 2>&1
end
