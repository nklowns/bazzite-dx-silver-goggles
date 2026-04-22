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
    # 1. ShellCheck for Bash/Sh
    echo "Running ShellCheck on Bash/Sh scripts..."
    if ! command -v shellcheck &>/dev/null; then
        /usr/bin/find . -type f -not -path "./.bluebuild*" -not -path "./.git/*" \( -iname "*.sh" -o -exec grep -qE '^#!.*(\<bash\>|\<sh\>)' {} \; \) -print -exec ${PODMAN} run --rm -v "$PWD:/mnt:Z" docker.io/koalaman/shellcheck-alpine shellcheck /mnt/{} ';'
    else
        /usr/bin/find . -type f -not -path "./.bluebuild*" -not -path "./.git/*" \( -iname "*.sh" -o -exec grep -qE '^#!.*(\<bash\>|\<sh\>)' {} \; \) -print -exec shellcheck "{}" ';'
    fi

    # 2. Zsh Syntax Check
    echo "Running syntax check on Zsh scripts..."
    /usr/bin/find . -type f -not -path "./.bluebuild*" -not -path "./.git/*" \( -iname "*.zsh" -o -exec grep -qE '^#!.*\<zsh\>' {} \; \) -print -exec zsh -n "{}" ';'

    # 3. Fish Syntax Check
    echo "Running syntax check on Fish scripts..."
    /usr/bin/find . -type f -not -path "./.bluebuild*" -not -path "./.git/*" \( -iname "*.fish" -o -exec grep -qE '^#!.*\<fish\>' {} \; \) -print -exec fish -n "{}" ';'

# Runs formatting on all scripts (shfmt for Bash/Zsh, fish_indent for Fish)
[group('Utility')]
format:
    #!/usr/bin/env bash
    set -eoux pipefail
    # 1. shfmt for Bash/Sh
    echo "Formatting Bash/Sh scripts..."
    if ! command -v shfmt &>/dev/null; then
        /usr/bin/find . -type f -not -path "./.bluebuild*" -not -path "./.git/*" \( -iname "*.sh" -o -exec grep -qE '^#!.*(\<bash\>|\<sh\>)' {} \; \) -print -exec ${PODMAN} run --rm -v "$PWD:/mnt:Z" --entrypoint shfmt docker.io/mvdan/shfmt:latest -w /mnt/{} ';'
    else
        /usr/bin/find . -type f -not -path "./.bluebuild*" -not -path "./.git/*" \( -iname "*.sh" -o -exec grep -qE '^#!.*(\<bash\>|\<sh\>)' {} \; \) -print -exec shfmt --write "{}" ';'
    fi

    # 2. shfmt for Zsh
    echo "Formatting Zsh scripts..."
    if ! command -v shfmt &>/dev/null; then
        /usr/bin/find . -type f -not -path "./.bluebuild*" -not -path "./.git/*" \( -iname "*.zsh" -o -exec grep -qE '^#!.*\<zsh\>' {} \; \) -print -exec ${PODMAN} run --rm -v "$PWD:/mnt:Z" --entrypoint shfmt docker.io/mvdan/shfmt:latest -ln=zsh -w /mnt/{} ';'
    else
        /usr/bin/find . -type f -not -path "./.bluebuild*" -not -path "./.git/*" \( -iname "*.zsh" -o -exec grep -qE '^#!.*\<zsh\>' {} \; \) -print -exec shfmt -ln=zsh --write "{}" ';'
    fi

    # 3. fish_indent for Fish
    echo "Formatting Fish scripts..."
    # fish_indent is part of the fish package
    /usr/bin/find . -type f -not -path "./.bluebuild*" -not -path "./.git/*" \( -iname "*.fish" -o -exec grep -qE '^#!.*\<fish\>' {} \; \) -print -exec fish_indent --write "{}" ';'

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
