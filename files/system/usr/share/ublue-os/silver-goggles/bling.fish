# Bazzite-DX Silver Goggles: Shell Excellence (Bling)
# Standardized Shell Experience for Fish.
# Located in: /usr/share/ublue-os/silver-goggles/bling.fish

# Check if shell has already been sourced to prevent recursion
if set -q BLING_SOURCED
    return
end
set -g BLING_SOURCED 1

# --- Configuration Toggles ---
set -q BLUEFIN_SHELL_ENABLE_ATUIN; or set -g BLUEFIN_SHELL_ENABLE_ATUIN 1
set -q BLUEFIN_SHELL_ENABLE_STARSHIP; or set -g BLUEFIN_SHELL_ENABLE_STARSHIP 1
set -q BLUEFIN_SHELL_ENABLE_ZOXIDE; or set -g BLUEFIN_SHELL_ENABLE_ZOXIDE 1
set -q BLUEFIN_SHELL_ENABLE_MISE; or set -g BLUEFIN_SHELL_ENABLE_MISE 1
set -q BLUEFIN_SHELL_ENABLE_DIRENV; or set -g BLUEFIN_SHELL_ENABLE_DIRENV 1

# --- Load Common Aliases ---
if test -f /usr/share/ublue-os/silver-goggles/common-aliases.fish
    source /usr/share/ublue-os/silver-goggles/common-aliases.fish
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
        if test "$MISE_FISH_AUTO_ACTIVATE" != 0
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
        function fish_mode_prompt
            true
        end # https://github.com/microsoft/vscode/issues/245607#issuecomment-2777199777
    end

    # 5. Atuin History Integration (source last to avoid hook conflicts)
    if test "$BLUEFIN_SHELL_ENABLE_ATUIN" = 1; and command -v atuin >/dev/null
        atuin init fish $ATUIN_INIT_FLAGS | source
    end

end
