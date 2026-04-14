# Bazzite-DX Silver Goggles: Shell Excellence (Bling)
# Standardized Shell Experience for Fish.
# Located in: /usr/share/ublue-os/silver-goggles/bling.fish

# Check if shell has already been sourced to prevent recursion
if set -q BLING_SOURCED
    return
end
set -g BLING_SOURCED 1

# --- Configuration Toggles ---
set -q BLUEFIN_SHELL_ENABLE_EZA; or set -g BLUEFIN_SHELL_ENABLE_EZA 1
set -q BLUEFIN_SHELL_ENABLE_UGREP; or set -g BLUEFIN_SHELL_ENABLE_UGREP 1
set -q BLUEFIN_SHELL_ENABLE_BAT; or set -g BLUEFIN_SHELL_ENABLE_BAT 1
set -q BLUEFIN_SHELL_ENABLE_ATUIN; or set -g BLUEFIN_SHELL_ENABLE_ATUIN 1
set -q BLUEFIN_SHELL_ENABLE_STARSHIP; or set -g BLUEFIN_SHELL_ENABLE_STARSHIP 1
set -q BLUEFIN_SHELL_ENABLE_ZOXIDE; or set -g BLUEFIN_SHELL_ENABLE_ZOXIDE 1
set -q BLUEFIN_SHELL_ENABLE_MISE; or set -g BLUEFIN_SHELL_ENABLE_MISE 1
set -q BLUEFIN_SHELL_ENABLE_DIRENV; or set -g BLUEFIN_SHELL_ENABLE_DIRENV 1

# --- Power-User Extras ---
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
if test "$BLUEFIN_SHELL_ENABLE_UGREP" = 1; and command -v ug >/dev/null
    alias grep='ug'
    alias egrep='ug -E'
    alias fgrep='ug -F'
    alias xzgrep='ug -z'
    alias xzegrep='ug -zE'
    alias xzfgrep='ug -zF'
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

# --- Tool Activation (interactive shells only) ---
# Aliases above are always available. Evals (prompt, hooks, completions)
# only make sense for humans — skip in scripts and agent-driven subshells.
if status is-interactive

    # 1. Initialize direnv
    if test "$BLUEFIN_SHELL_ENABLE_DIRENV" = 1; and command -v direnv >/dev/null
        direnv hook fish | source
    end

    # 2. Mise (early for PATH availability)
    if test "$BLUEFIN_SHELL_ENABLE_MISE" = 1; and command -v mise >/dev/null
        if test "$MISE_FISH_AUTO_ACTIVATE" != "0"
            mise activate fish | source
        end
    end

    # 3. Zoxide (Better 'cd')
    if test "$BLUEFIN_SHELL_ENABLE_ZOXIDE" = 1; and command -v zoxide >/dev/null
        zoxide init fish | source
    end

    # 4. Starship
    if test "$BLUEFIN_SHELL_ENABLE_STARSHIP" = 1; and command -v starship >/dev/null
        starship init fish | source
        function fish_mode_prompt; true; end # https://github.com/microsoft/vscode/issues/245607#issuecomment-2777199777
    end

    # 5. Atuin History Integration (source last to avoid hook conflicts)
    if test "$BLUEFIN_SHELL_ENABLE_ATUIN" = 1; and command -v atuin >/dev/null
        atuin init fish $ATUIN_INIT_FLAGS | source
    end


end
