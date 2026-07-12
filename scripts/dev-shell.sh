#!/usr/bin/env bash

# Orchestrates a shadowed dev environment to test "Bling" without host mutation.
set -uo pipefail

readonly SHELL_TYPE="${1:-bash}"
PROJECT_ROOT=$(pwd)
readonly PROJECT_ROOT
SHADOW_ROOT_BASE=$(mktemp -d -t silver-goggles-dev.XXXXXX)
readonly SHADOW_ROOT_BASE

# Lifecycle Hook: Ensure cleanup of shadow root upon exit.
trap 'rm -rf "$SHADOW_ROOT_BASE"' EXIT

PrepareShadowEnvironment() {
	local shadow_bling="$SHADOW_ROOT_BASE/silver-goggles"
	mkdir -p "$shadow_bling"

	cp -R "$PROJECT_ROOT/files/system/usr/share/ublue-os/silver-goggles/." "$shadow_bling/"

	# Redirect asset lookups to the shadow root.
	find "$shadow_bling" -type f -exec sed -i "s|/usr/share/ublue-os/silver-goggles|$shadow_bling|g" {} +
}

InjectPatchedScript() {
	local source_script="$1"
	local target_rc="$2"
	local shadow_bling="$SHADOW_ROOT_BASE/silver-goggles"

	sed "s|/usr/share/ublue-os/silver-goggles|$shadow_bling|g" "$source_script" >>"$target_rc"
}

LaunchBash() {
	local rc_file="$SHADOW_ROOT_BASE/dev.bashrc"

	[[ -f ~/.bashrc ]] && echo "source ~/.bashrc" >"$rc_file"
	echo "export BLING_ENABLE=1" >>"$rc_file"

	cat "$PROJECT_ROOT/files/system/etc/profile.d/brew.sh" >>"$rc_file"
	InjectPatchedScript "$PROJECT_ROOT/files/system/etc/profile.d/zz-bazzite-dx-bling.sh" "$rc_file"

	printf "echo -e '\\n✨ Silver Goggles Dev-Shell (BASH) Active!'\n" >>"$rc_file"

	bash --norc --rcfile "$rc_file" -i
}

LaunchZsh() {
	local zsh_dir="$SHADOW_ROOT_BASE/zsh"
	local rc_file="$zsh_dir/.zshrc"
	mkdir -p "$zsh_dir"

	echo "[[ -f ~/.zshrc ]] && source ~/.zshrc" >"$rc_file"
	echo "export BLING_ENABLE=1" >>"$rc_file"

	cat "$PROJECT_ROOT/files/system/etc/profile.d/brew.sh" >>"$rc_file"
	InjectPatchedScript "$PROJECT_ROOT/files/system/etc/profile.d/zz-bazzite-dx-bling.sh" "$rc_file"

	printf "echo -e '\\n✨ Silver Goggles Dev-Shell (ZSH) Active!'\n" >>"$rc_file"

	ZDOTDIR="$zsh_dir" zsh -d -i
}

LaunchFish() {
	local init_file="$SHADOW_ROOT_BASE/init.fish"

	cat "$PROJECT_ROOT/files/system/usr/share/fish/vendor_conf.d/ublue-brew.fish" >"$init_file"
	InjectPatchedScript "$PROJECT_ROOT/files/system/usr/share/fish/vendor_conf.d/zz-bazzite-dx-bling.fish" "$init_file"

	printf "✨ Silver Goggles Dev-Shell (FISH) Active!\n"
	fish -i -C "source $init_file"
}

# --- Execution ---
printf "🚀 Bootstrapping %s Dev Environment...\n" "$SHELL_TYPE"
printf "📂 Source: %s\n" "$PROJECT_ROOT"

PrepareShadowEnvironment

case "$SHELL_TYPE" in
bash) LaunchBash ;;
zsh) LaunchZsh ;;
fish) LaunchFish ;;
*)
	printf "❌ Error: Unsupported shell '%s'\n" "$SHELL_TYPE"
	exit 1
	;;
esac
