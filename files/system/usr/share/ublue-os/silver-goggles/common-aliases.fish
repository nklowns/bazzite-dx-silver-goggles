# Bazzite-DX Silver Goggles: Common Aliases & Config
# Native Fish implementation.
# Located in: /usr/share/ublue-os/silver-goggles/common-aliases.fish

# --- Configuration Toggles ---
set -q BLUEFIN_SHELL_ENABLE_EZA; or set -g BLUEFIN_SHELL_ENABLE_EZA 1
set -q BLUEFIN_SHELL_ENABLE_UGREP; or set -g BLUEFIN_SHELL_ENABLE_UGREP 1
set -q BLUEFIN_SHELL_ENABLE_BAT; or set -g BLUEFIN_SHELL_ENABLE_BAT 1

# --- Navigation & Basics ---
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'
alias mkdir='mkdir -p'
alias g='git'

# --- Alias Sections ---

# eza for ls
if test "$BLUEFIN_SHELL_ENABLE_EZA" = 1; and command -v eza >/dev/null
    alias ll='eza -l --icons=auto --group-directories-first'
    alias l.='eza -d .*'
    alias ls='eza'
    alias l1='eza -1'
end

# ugrep for grep
if test "$BLUEFIN_SHELL_ENABLE_UGREP" = 1
    if command -v ug >/dev/null
        alias grep='ug'
        alias egrep='ug -E'
        alias fgrep='ug -F'
        alias xzgrep='ug -z'
        alias xzegrep='ug -zE'
        alias xzfgrep='ug -zF'
    else if command -v ugrep >/dev/null
        alias grep='ugrep'
        alias egrep='ugrep -E'
        alias fgrep='ugrep -F'
        alias xzgrep='ugrep -z'
        alias xzegrep='ugrep -zE'
        alias xzfgrep='ugrep -zF'
    end
end

# bat for cat
if test "$BLUEFIN_SHELL_ENABLE_BAT" = 1; and command -v bat >/dev/null
    alias cat='bat --style=plain --pager=never'
end

# Kubernetes
if command -v kubectl >/dev/null
    alias k='kubectl'
end

# Obsidian CLI Fix
if command -v obsidian >/dev/null
    alias obsidian='ln -sf (set -q XDG_RUNTIME_DIR; and echo $XDG_RUNTIME_DIR; or echo /run/user/(id -u))/.flatpak/md.obsidian.Obsidian/xdg-run/.obsidian-cli.sock (set -q XDG_RUNTIME_DIR; and echo $XDG_RUNTIME_DIR; or echo /run/user/(id -u))/.obsidian-cli.sock 2>/dev/null; command obsidian'
end
