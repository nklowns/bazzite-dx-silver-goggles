# Normalizes HOME to /var/home/$USER for OSTree deployments across all login/SSH/TTY shells.
# Ensures path parity with systemd user session and GUI applications.

if string match -q '/home/*' "$HOME"; and test -d "/var$HOME"
    set -gx HOME "/var$HOME"
end
