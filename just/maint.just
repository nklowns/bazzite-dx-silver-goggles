# ==============================================================================
# GROUP 1: Utility (Maintenance & CI)
# ==============================================================================

# Check Just Syntax and BlueBuild Recipe
[group('Just')]
check:
    #!/usr/bin/env bash
    find . -type f -name "*.just" | while read -r file; do
    	echo "Checking syntax: $file"
    	just --unstable --fmt --check -f "$file"
    done
    echo "Checking syntax: Justfile"
    just --unstable --fmt --check -f Justfile
    if [ -f recipes/recipe.yml ]; then
      echo "Validating BlueBuild recipe..."
      bluebuild validate recipes/recipe.yml
      echo "Validating generated build recipe (what CI actually ships)..."
      just generate-recipe "bazzite-nvidia" "latest"
      bluebuild validate recipes/build-recipe.yml
    fi
    echo "Running ShellCheck on Bash scripts..."
    just lint

# Fix Just Syntax and Format scripts
[group('Just')]
fix:
    #!/usr/bin/env bash
    find . -type f -name "*.just" | while read -r file; do
    	echo "Fixing syntax: $file"
    	just --unstable --fmt -f "$file"
    done
    echo "Fixing syntax: Justfile"
    just --unstable --fmt -f Justfile
    echo "Formatting Bash scripts..."
    just format

# Runs shell check on all scripts (ShellCheck for Bash, zsh -n for Zsh, fish -n for Fish)
[group('Utility')]
lint:
    #!/usr/bin/env bash
    set -eoux pipefail
    # 1. ShellCheck for Bash/Sh — containerized by default (hermetic build tooling);
    # host binary (dnf/brew) only as fallback. Batched in a single run so the
    # tool's exit code propagates (find -exec ';' silently swallows failures).
    echo "Running ShellCheck on Bash/Sh scripts..."
    mapfile -d '' bash_scripts < <(/usr/bin/find . -type f -not -path "./.bluebuild*" -not -path "./.git/*" \( -iname "*.sh" -o -exec grep -qE '^#!.*(\<bash\>|\<sh\>)' {} \; \) -print0)
    if [ "${#bash_scripts[@]}" -eq 0 ]; then
        echo "No Bash/Sh scripts found."
    elif command -v "${PODMAN}" &>/dev/null; then
        printf '%s\n' "${bash_scripts[@]}"
        ${PODMAN} run --rm -v "$PWD:/mnt:Z" -w /mnt docker.io/koalaman/shellcheck-alpine:v0.11.0 shellcheck "${bash_scripts[@]}"
    elif command -v shellcheck &>/dev/null; then
        printf '%s\n' "${bash_scripts[@]}"
        shellcheck "${bash_scripts[@]}"
    else
        echo "ERROR: no container engine and no shellcheck on host (install via brew or dnf)." >&2
        exit 1
    fi

    # 2. Zsh Syntax Check — zsh -n takes a single script, so loop (set -e propagates).
    # Missing interpreter is a hard error: find -exec used to swallow it and CI
    # stayed green while never checking anything.
    echo "Running syntax check on Zsh scripts..."
    mapfile -d '' zsh_files < <(/usr/bin/find . -type f -not -path "./.bluebuild*" -not -path "./.git/*" \( -iname "*.zsh" -o -exec grep -qE '^#!.*\<zsh\>' {} \; \) -print0)
    if [ "${#zsh_files[@]}" -eq 0 ]; then
        echo "No Zsh scripts found."
    elif command -v zsh &>/dev/null; then
        for f in "${zsh_files[@]}"; do
            echo "$f"
            zsh -n "$f"
        done
    else
        echo "ERROR: zsh not available; cannot syntax-check ${#zsh_files[@]} Zsh script(s)." >&2
        exit 1
    fi

    # 3. Fish Syntax Check — same rules as Zsh above.
    echo "Running syntax check on Fish scripts..."
    mapfile -d '' fish_files < <(/usr/bin/find . -type f -not -path "./.bluebuild*" -not -path "./.git/*" \( -iname "*.fish" -o -exec grep -qE '^#!.*\<fish\>' {} \; \) -print0)
    if [ "${#fish_files[@]}" -eq 0 ]; then
        echo "No Fish scripts found."
    elif command -v fish &>/dev/null; then
        for f in "${fish_files[@]}"; do
            echo "$f"
            fish -n "$f"
        done
    else
        echo "ERROR: fish not available; cannot syntax-check ${#fish_files[@]} Fish script(s)." >&2
        exit 1
    fi

# Runs formatting on all scripts (shfmt for Bash/Zsh, fish_indent for Fish)
[group('Utility')]
format:
    #!/usr/bin/env bash
    set -eoux pipefail
    # 1. shfmt for Bash/Sh — containerized by default (hermetic build tooling);
    # host binary (dnf/brew) only as fallback. Batched: one container per tool,
    # exit code propagates (find -exec ';' silently swallows failures).
    echo "Formatting Bash/Sh scripts..."
    mapfile -d '' bash_scripts < <(/usr/bin/find . -type f -not -path "./.bluebuild*" -not -path "./.git/*" \( -iname "*.sh" -o -exec grep -qE '^#!.*(\<bash\>|\<sh\>)' {} \; \) -print0)
    if [ "${#bash_scripts[@]}" -eq 0 ]; then
        echo "No Bash/Sh scripts found."
    elif command -v "${PODMAN}" &>/dev/null; then
        printf '%s\n' "${bash_scripts[@]}"
        ${PODMAN} run --rm -v "$PWD:/mnt:Z" -w /mnt --entrypoint shfmt docker.io/mvdan/shfmt:v3.13.1 -w "${bash_scripts[@]}"
    elif command -v shfmt &>/dev/null; then
        printf '%s\n' "${bash_scripts[@]}"
        shfmt --write "${bash_scripts[@]}"
    else
        echo "ERROR: no container engine and no shfmt on host (install via brew or dnf)." >&2
        exit 1
    fi

    # 2. shfmt for Zsh
    echo "Formatting Zsh scripts..."
    mapfile -d '' zsh_scripts < <(/usr/bin/find . -type f -not -path "./.bluebuild*" -not -path "./.git/*" \( -iname "*.zsh" -o -exec grep -qE '^#!.*\<zsh\>' {} \; \) -print0)
    if [ "${#zsh_scripts[@]}" -eq 0 ]; then
        echo "No Zsh scripts found."
    elif command -v "${PODMAN}" &>/dev/null; then
        printf '%s\n' "${zsh_scripts[@]}"
        ${PODMAN} run --rm -v "$PWD:/mnt:Z" -w /mnt --entrypoint shfmt docker.io/mvdan/shfmt:v3.13.1 -ln=zsh -w "${zsh_scripts[@]}"
    elif command -v shfmt &>/dev/null; then
        printf '%s\n' "${zsh_scripts[@]}"
        shfmt -ln=zsh --write "${zsh_scripts[@]}"
    else
        echo "ERROR: no container engine and no shfmt on host (install via brew or dnf)." >&2
        exit 1
    fi

    # 3. fish_indent for Fish (part of the fish package) — loop so a failure
    # propagates via set -e; missing tool is a hard error, not a silent skip.
    echo "Formatting Fish scripts..."
    mapfile -d '' fish_files < <(/usr/bin/find . -type f -not -path "./.bluebuild*" -not -path "./.git/*" \( -iname "*.fish" -o -exec grep -qE '^#!.*\<fish\>' {} \; \) -print0)
    if [ "${#fish_files[@]}" -eq 0 ]; then
        echo "No Fish scripts found."
    elif command -v fish_indent &>/dev/null; then
        for f in "${fish_files[@]}"; do
            echo "$f"
            fish_indent --write "$f"
        done
    else
        echo "ERROR: fish_indent not available (install fish); cannot format ${#fish_files[@]} Fish script(s)." >&2
        exit 1
    fi

# Clean Repo
[group('Utility')]
clean:
    #!/usr/bin/env bash
    set -euxo pipefail
    touch _build
    find *_build* -exec rm -rf {} \;
    rm -f previous.manifest.json
    rm -f changelog.md
    rm -f output.env
    rm -rf output/

# Sudo Clean Repo
[group('Utility')]
[private]
sudo-clean:
    just sudoif just clean

# sudoif bash function
[group('Utility')]
[private]
sudoif command *args:
    #!/usr/bin/bash
    function sudoif(){
        if [[ "${UID}" -eq 0 ]]; then
            "$@"
        elif [[ "$(command -v sudo)" && -n "${SSH_ASKPASS:-}" ]] && [[ -n "${DISPLAY:-}" || -n "${WAYLAND_DISPLAY:-}" ]]; then
            /usr/bin/sudo --askpass "$@" || exit 1
        elif [[ "$(command -v sudo)" ]]; then
            /usr/bin/sudo "$@" || exit 1
        else
            exit 1
        fi
    }
    sudoif {{ command }} {{ args }}
