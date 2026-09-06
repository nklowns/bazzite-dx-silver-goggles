# ==============================================================================
# GROUP 5: Component Development (Hot-Swap)
# ==============================================================================

# Abre um shell interativo com o contexto de desenvolvimento (bash, zsh, fish)
[group('Development')]
dev-shell shell="bash":
    ./scripts/dev-shell.sh {{ shell }}
