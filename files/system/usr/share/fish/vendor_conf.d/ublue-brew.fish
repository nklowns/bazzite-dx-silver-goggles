# Bazzite-DX: Homebrew for Fish
# HOMEBREW_* vars are system-wide via /usr/lib/environment.d/homebrew.conf

set -l brew_bin "/home/linuxbrew/.linuxbrew/bin/brew"
set -l brew_prefix "/home/linuxbrew/.linuxbrew"

if test -x "$brew_bin"; and test (id -u) != 0
    # Add brew to PATH. 
    # Manual move-to-end to ensure system tools keep priority over brew tools.
    # Skip if already at the very end to keep it fast.
    if test "$PATH[-1]" != "$brew_prefix/sbin"
        for path in "$brew_prefix/bin" "$brew_prefix/sbin"
            if set -l index (contains -i -- $path $PATH)
                set -e PATH[$index]
            end
            set -gx PATH $PATH $path
        end
    end

    # Interactive extras (slow bits and completions)
    if status is-interactive
        if not set -q HOMEBREW_PREFIX_INITIALIZED
            # Set MANPATH/INFOPATH for interactive use.
            # Filter both old (set -gx PATH) and new (fish_add_path) Homebrew PATH syntax
            # since PATH is already handled above.
            eval ($brew_bin shellenv fish | grep -vE '(fish_add_path|set -gx PATH)')
            set -gx HOMEBREW_PREFIX_INITIALIZED 1
        end

        # Load completions — prefix hardcoded to avoid calling brew --prefix
        if test -d "$brew_prefix/share/fish/completions"
            set -a fish_complete_path "$brew_prefix/share/fish/completions"
        end
        if test -d "$brew_prefix/share/fish/vendor_completions.d"
            set -a fish_complete_path "$brew_prefix/share/fish/vendor_completions.d"
        end
    end
end
