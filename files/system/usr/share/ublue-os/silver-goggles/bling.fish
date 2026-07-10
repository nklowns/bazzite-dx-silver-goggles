# Bazzite-DX Silver Goggles: Shell Excellence (Bling)
# Standardized Shell Experience for Fish.
# Located in: /usr/share/ublue-os/silver-goggles/bling.fish

# Check if shell has already been sourced to prevent recursion
if set -q BLING_FISH_SOURCED
    return
end
set -g BLING_FISH_SOURCED 1

# --- Configuration Toggles ---
set -q BLUEFIN_SHELL_ENABLE_ATUIN; or set -g BLUEFIN_SHELL_ENABLE_ATUIN 1
set -q BLUEFIN_SHELL_ENABLE_STARSHIP; or set -g BLUEFIN_SHELL_ENABLE_STARSHIP 1
set -q BLUEFIN_SHELL_ENABLE_ZOXIDE; or set -g BLUEFIN_SHELL_ENABLE_ZOXIDE 1
set -q BLUEFIN_SHELL_ENABLE_MISE; or set -g BLUEFIN_SHELL_ENABLE_MISE 1
set -q BLUEFIN_SHELL_ENABLE_DIRENV; or set -g BLUEFIN_SHELL_ENABLE_DIRENV 1
set -q BLUEFIN_SHELL_ENABLE_FZF; or set -g BLUEFIN_SHELL_ENABLE_FZF 1
set -q BLUEFIN_SHELL_ENABLE_K8S; or set -g BLUEFIN_SHELL_ENABLE_K8S 1

# --- Load Common Aliases ---
if test -f /usr/share/ublue-os/silver-goggles/common-aliases.fish
    source /usr/share/ublue-os/silver-goggles/common-aliases.fish
end

# --- Mise PATH Setup (Non-interactive safe) ---
# Ensure Mise shims are in PATH even in non-interactive shells (like SSH commands or IDE tasks).
# We prepend them to follow the "Inverted PATH Priority" (User-first) standard.
if test "$BLUEFIN_SHELL_ENABLE_MISE" = 1
    # Use mise's own logic to find data dir if possible, otherwise default
    set -l mise_data_dir (if set -q MISE_DATA_DIR; echo $MISE_DATA_DIR; else; echo $HOME/.local/share/mise; end)
    set -l mise_shims $mise_data_dir/shims
    if test -d $mise_shims
        if not contains -- $mise_shims $PATH
            set -gx PATH $mise_shims $PATH
        end
    end
end

# --- Tool Activation (interactive shells only) ---
# Aliases above are always available. Evals (prompt, hooks, completions)
# only make sense for humans — skip in scripts and agent-driven subshells.
if status is-interactive

    # --- VS Code / VS Code Insiders / Cursor / Antigravity IDE Integration ---
    if test "$TERM_PROGRAM" = "vscode"; or set -q VSCODE_GIT_ASKPASS_NODE
        if not test -f /run/.containerenv; and not test -f /.dockerenv
            switch "$EDITOR"
                case "" "*nano*" "*vi" "*vim"
                    set -l _detected_editor ""
                    for _var in "$VSCODE_GIT_ASKPASS_NODE" "$GIT_ASKPASS" "$TERM_PROGRAM_VERSION"
                        if string match -q "*code-insiders*" "$_var"
                            set _detected_editor "code-insiders"
                            break
                        elif string match -q "*cursor*" "$_var"
                            set _detected_editor "cursor"
                            break
                        elif string match -q "*antigravity-ide*" "$_var"
                            set _detected_editor "antigravity-ide"
                            break
                        elif string match -q "*code*" "$_var"
                            set _detected_editor "code"
                            break
                        end
                    end

                    if test -z "$_detected_editor"
                        set -l _pid $fish_pid
                        while test "$_pid" -gt 1
                            set -l _cmd (ps -p "$_pid" -o comm= 2>/dev/null)
                            if string match -q "*code-insiders*" "$_cmd"
                                set _detected_editor "code-insiders"
                                break
                            elif string match -q "*cursor*" "$_cmd"
                                set _detected_editor "cursor"
                                break
                            elif string match -q "*antigravity-ide*" "$_cmd"
                                set _detected_editor "antigravity-ide"
                                break
                            elif string match -q "*code*" "$_cmd"
                                set _detected_editor "code"
                                break
                            end
                            set _pid (ps -p "$_pid" -o ppid= 2>/dev/null | string trim)
                            if test -z "$_pid"
                                break
                            end
                        end
                    end

                    if test -n "$_detected_editor"; and command -v "$_detected_editor" >/dev/null 2>&1
                        set -gx EDITOR "$_detected_editor --wait"
                        set -gx VISUAL "$_detected_editor --wait"
                    end
            end
        end
    end

    # 1. Initialize direnv
    if test "$BLUEFIN_SHELL_ENABLE_DIRENV" = 1; and command -v direnv >/dev/null
        direnv hook fish | source
    end

    # 2. Mise Runtime Activation (Hooks/Interactive extras)
    if test "$BLUEFIN_SHELL_ENABLE_MISE" = 1; and command -v mise >/dev/null
        if test "$MISE_FISH_AUTO_ACTIVATE" != 0
            mise activate fish | source
        end
    end

    # 3. Zoxide (Better 'cd')
    if test "$BLUEFIN_SHELL_ENABLE_ZOXIDE" = 1; and command -v zoxide >/dev/null
        zoxide init fish | source
    end

    # 3.1 FZF
    if test "$BLUEFIN_SHELL_ENABLE_FZF" = 1; and command -v fzf >/dev/null
        if fzf --fish >/dev/null 2>&1
            fzf --fish | source
        else
            # Fallback for older fzf versions
            if test -n "$HOMEBREW_PREFIX"; and test -f $HOMEBREW_PREFIX/opt/fzf/shell/key-bindings.fish
                source $HOMEBREW_PREFIX/opt/fzf/shell/key-bindings.fish
            end
        end
    end

    # 4. Starship
    if test "$BLUEFIN_SHELL_ENABLE_STARSHIP" = 1; and command -v starship >/dev/null
        starship init fish | source
        function fish_mode_prompt
            true
        end # https://github.com/microsoft/vscode/issues/245607#issuecomment-2777199777
    end

    # 5. Atuin History Integration (Deferred/Lazy Loading)
    if test "$BLUEFIN_SHELL_ENABLE_ATUIN" = 1; and command -v atuin >/dev/null
        function _bling_lazy_atuin --on-event fish_prompt
            atuin init fish $ATUIN_INIT_FLAGS | source
            functions -e _bling_lazy_atuin
        end
    end

end
