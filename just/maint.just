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

# Runs shell check on all Bash scripts (uses Container if local not found)
[group('Utility')]
lint:
    #!/usr/bin/env bash
    set -eoux pipefail
    if ! command -v shellcheck &>/dev/null; then
        echo "shellcheck not found locally. Running via ${PODMAN}..."
        /usr/bin/find . -type f -not -path "./.bluebuild*" -not -path "./.git/*" \( -iname "*.sh" -o -exec grep -qE '^#!.*(bash|sh|zsh)' {} \; \) -print -exec ${PODMAN} run --rm -v "$PWD:/mnt:Z" docker.io/koalaman/shellcheck-alpine shellcheck /mnt/{} ';'
    else
        /usr/bin/find . -type f -not -path "./.bluebuild*" -not -path "./.git/*" \( -iname "*.sh" -o -exec grep -qE '^#!.*(bash|sh|zsh)' {} \; \) -print -exec shellcheck "{}" ';'
    fi

# Runs shfmt on all Bash scripts (uses Container if local not found)
[group('Utility')]
format:
    #!/usr/bin/env bash
    set -eoux pipefail
    if ! command -v shfmt &>/dev/null; then
        echo "shfmt not found locally. Running via ${PODMAN}..."
        /usr/bin/find . -type f -not -path "./.bluebuild*" -not -path "./.git/*" \( -iname "*.sh" -o -exec grep -qE '^#!.*(bash|sh|zsh)' {} \; \) -print -exec ${PODMAN} run --rm -v "$PWD:/mnt:Z" --entrypoint shfmt docker.io/mvdan/shfmt:latest -w /mnt/{} ';'
    else
        /usr/bin/find . -type f -not -path "./.bluebuild*" -not -path "./.git/*" \( -iname "*.sh" -o -exec grep -qE '^#!.*(bash|sh|zsh)' {} \; \) -print -exec shfmt --write "{}" ';'
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
