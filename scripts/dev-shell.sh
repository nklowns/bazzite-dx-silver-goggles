#!/usr/bin/env bash
# Silver Goggles: Hot-Reload Dev Shell (v2 - High Fidelity)
# Launches an interactive shell using the CURRENT workspace files.

set -uo pipefail # Removido -e para evitar que erros no source fechem o terminal

SHELL_TYPE="${1:-bash}"
PROJECT_ROOT=$(pwd)
TEMP_DEV_DIR=$(mktemp -d -t silver-goggles-dev.XXXXXX)

# Cleanup: remove o diretório temporário quando o script fechar
trap 'rm -rf "$TEMP_DEV_DIR"' EXIT

printf "🔥 Launching %s with Silver Goggles Dev Context...\n" "$SHELL_TYPE"
printf "📂 Workspace: %s\n" "$PROJECT_ROOT"
printf "🛠️  Shadow Root: %s\n" "$TEMP_DEV_DIR"

# 1. Preparar Shadow Root (Arquivos de Bling)
mkdir -p "$TEMP_DEV_DIR/silver-goggles"
cp -r "$PROJECT_ROOT/files/system/usr/share/ublue-os/silver-goggles/." "$TEMP_DEV_DIR/silver-goggles/"

# 2. Patch: Substituir caminhos de sistema pelo Shadow Root local
find "$TEMP_DEV_DIR/silver-goggles" -type f -exec sed -i "s|/usr/share/ublue-os/silver-goggles|$TEMP_DEV_DIR/silver-goggles|g" {} +

# 3. Lançar o Shell com isolamento
case "$SHELL_TYPE" in
bash)
	BASHRC_DEV="$TEMP_DEV_DIR/dev.bashrc"
	# Carrega o bashrc real primeiro
	[[ -f ~/.bashrc ]] && echo "source ~/.bashrc" >"$BASHRC_DEV"
	echo "export BLING_ENABLE=1" >>"$BASHRC_DEV"
	# Injeta o Homebrew local
	cat "$PROJECT_ROOT/files/system/etc/profile.d/brew.sh" >>"$BASHRC_DEV"
	# Injeta o wrapper patcheado
	sed "s|/usr/share/ublue-os/silver-goggles|$TEMP_DEV_DIR/silver-goggles|g" "$PROJECT_ROOT/files/system/etc/profile.d/95-bazzite-dx-bling.sh" >>"$BASHRC_DEV"
	printf "echo -e '\\n✨ Silver Goggles Dev-Shell (BASH) Active!'\n" >>"$BASHRC_DEV"

	# --norc evita carregar /etc/bash.bashrc que poderia causar conflitos
	bash --norc --rcfile "$BASHRC_DEV" -i
	;;
zsh)
	ZDOTDIR_DEV="$TEMP_DEV_DIR/zsh"
	mkdir -p "$ZDOTDIR_DEV"
	cat <<EOF >"$ZDOTDIR_DEV/.zshrc"
[[ -f ~/.zshrc ]] && source ~/.zshrc
export BLING_ENABLE=1
EOF
	# Injeta o Homebrew local
	cat "$PROJECT_ROOT/files/system/etc/profile.d/brew.sh" >>"$ZDOTDIR_DEV/.zshrc"
	# Injeta o wrapper patcheado
	sed "s|/usr/share/ublue-os/silver-goggles|$TEMP_DEV_DIR/silver-goggles|g" "$PROJECT_ROOT/files/system/etc/profile.d/95-bazzite-dx-bling.sh" >>"$ZDOTDIR_DEV/.zshrc"

	printf "echo -e '\\n✨ Silver Goggles Dev-Shell (ZSH) Active!'\n" >>"$ZDOTDIR_DEV/.zshrc"

	# -d evita rcs globais de sistema
	ZDOTDIR="$ZDOTDIR_DEV" zsh -d -i
	;;
fish)
	FISH_INIT="$TEMP_DEV_DIR/init.fish"
	# Gera o comando de inicialização com caminhos patcheados
	# Primeiro carrega o homebrew local
	cat "$PROJECT_ROOT/files/system/etc/fish/conf.d/brew.fish" >"$FISH_INIT"
	# Depois injeta o wrapper patcheado
	sed "s|/usr/share/ublue-os/silver-goggles|$TEMP_DEV_DIR/silver-goggles|g" "$PROJECT_ROOT/files/system/etc/fish/conf.d/95-bazzite-dx-bling.fish" >>"$FISH_INIT"

	printf "✨ Silver Goggles Dev-Shell (FISH) Active!\n"
	# -i força interatividade. -C executa o comando.
	# Envolvemos em um bloco begin/end para capturar erros sem fechar o shell
	fish -i -C "
            if test -f $FISH_INIT
                source $FISH_INIT
            else
                echo '❌ Dev init file not found'
            end
        "
	;;
*)
	printf "❌ Unsupported shell: %s\n" "$SHELL_TYPE"
	exit 1
	;;
esac
