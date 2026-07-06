# Bazzite-DX Silver Goggles: Common Aliases & Config
# Native Fish implementation.
# Located in: /usr/share/ublue-os/silver-goggles/common-aliases.fish

# --- Configuration Toggles ---
set -q BLUEFIN_SHELL_ENABLE_EZA; or set -g BLUEFIN_SHELL_ENABLE_EZA 1
set -q BLUEFIN_SHELL_ENABLE_UGREP; or set -g BLUEFIN_SHELL_ENABLE_UGREP 1
set -q BLUEFIN_SHELL_ENABLE_BAT; or set -g BLUEFIN_SHELL_ENABLE_BAT 1

# --- Core Navigation & Basics ---
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'
alias mkdir='mkdir -p'
alias g='git'

# --- Modern CLI Replacements (Scannable Blocks) ---

# <eza>
if test "$BLUEFIN_SHELL_ENABLE_EZA" = 1; and command -v eza >/dev/null
    alias ls='eza --icons=auto --group-directories-first'
    alias ll='eza -l --icons=auto --group-directories-first'
    alias la='eza -la --icons=auto --group-directories-first'
    alias l.='eza -d .* --icons=auto'
    alias tree='eza --tree --icons=auto'
end
# </eza>

# <ugrep>
if test "$BLUEFIN_SHELL_ENABLE_UGREP" = 1; and command -v ug >/dev/null
    alias grep='ug'
    alias egrep='ug -E'
    alias fgrep='ug -F'
end
# </ugrep>

# <ripgrep>
command -v rg >/dev/null; and alias rg='rg --smart-case'
# </ripgrep>

# <bat>
if test "$BLUEFIN_SHELL_ENABLE_BAT" = 1; and command -v bat >/dev/null
    alias cat='bat -pp --pager=never'
    set -gx PAGER bat
    set -gx MANPAGER "sh -c 'col -bx | bat -l man -p'"
end
# </bat>

# <fd>
command -v fd >/dev/null; and alias f='fd'
# </fd>

# --- Cloud Native & Dev Tools ---

# <kubectl>
command -v kubectl >/dev/null; and alias k='kubectl'
command -v kubecolor >/dev/null; and alias kubectl='kubecolor'
# </kubectl>

# <helm>
command -v helm >/dev/null; and alias h='helm'
# </helm>

# Obsidian CLI Fix
if command -v obsidian >/dev/null
    alias obsidian='ln -sf (set -q XDG_RUNTIME_DIR; and echo $XDG_RUNTIME_DIR; or echo /run/user/(id -u))/.flatpak/md.obsidian.Obsidian/xdg-run/.obsidian-cli.sock (set -q XDG_RUNTIME_DIR; and echo $XDG_RUNTIME_DIR; or echo /run/user/(id -u))/.obsidian-cli.sock 2>/dev/null; command obsidian'
end

# Only configure host-specific aliases and environments on the host (not inside containers/distrobox)
if not test -f /run/.containerenv; and not test -f /.dockerenv

    # --- Modern Bling Integrations & Aliases ---

    # <yazi>
    if command -v yazi >/dev/null
        alias y='yazi'
        function yy
            set -l tmp (mktemp -t "yazi-cwd.XXXXXX")
            yazi $argv --cwd-file=$tmp
            if test -f $tmp
                set -l cwd (cat $tmp)
                if test -n "$cwd"; and test "$cwd" != "$PWD"
                    builtin cd $cwd
                end
                rm -f $tmp
            end
        end
    end
    # </yazi>

    # <delta>
    if command -v delta >/dev/null
        set -gx GIT_PAGER delta
    end
    # </delta>

end


