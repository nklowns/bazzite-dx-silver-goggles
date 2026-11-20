#!/usr/bin/env bash
# Hermetic smoke tests for files/system/usr/libexec/dx-svc.
# Uses a temporary UNIT_DIR, GGUF_DIR, LLAMA_CFG and XDG_CONFIG_HOME — touches nothing on the host.
set -euo pipefail

REPO_ROOT="$(cd -P -- "$(dirname -- "$0")/.." && pwd -P)"
DX_SVC="${REPO_ROOT}/files/system/usr/libexec/dx-svc"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

export XDG_CONFIG_HOME="${TMP}/config"
export HOME="${TMP}/home"
mkdir -p "$XDG_CONFIG_HOME" "$HOME" "${TMP}/units" "${TMP}/gguf/active" "${TMP}/gguf/retired"

# Seed synthetic Quadlets
cat >"${TMP}/units/nomad-llama.container" <<'EOF'
[Container]
Image=ghcr.io/mostlygeek/llama-swap:v274@sha256:0000000000000000000000000000000000000000000000000000000000000001
PublishPort=127.0.0.1:61383:8080
AddDevice=nvidia.com/gpu=all
EOF

cat >"${TMP}/units/aistudio-audio.container" <<'EOF'
[Container]
Image=ghcr.io/debpalash/omnivoice-studio:latest@sha256:0000000000000000000000000000000000000000000000000000000000000002
PublishPort=127.0.0.1:61386:3900
AddDevice=nvidia.com/gpu=all
EOF

cat >"${TMP}/units/mesh-searxng.container" <<'EOF'
[Container]
Image=docker.io/searxng/searxng:latest@sha256:0000000000000000000000000000000000000000000000000000000000000003
PublishPort=127.0.0.1:61387:8080
EOF

# Seed synthetic GGUFs + llama-swap config
printf 'keep' >"${TMP}/gguf/active/keep.gguf"
printf 'drop' >"${TMP}/gguf/retired/old.gguf"
cat >"${TMP}/llama.yaml" <<'EOF'
models:
  test:
    cmd: llama-server -m /models/gguf/active/keep.gguf
EOF

# Mock bazzite-dx-serve
cat >"${TMP}/mock-serve" <<'EOF'
#!/usr/bin/env bash
echo "absent"
EOF
chmod +x "${TMP}/mock-serve"

export DX_SVC_UNIT_DIR="${TMP}/units"
export DX_SVC_SERVE_BIN="${TMP}/mock-serve"
export DX_SVC_GGUF_DIR="${TMP}/gguf"
export DX_SVC_LLAMA_CFG="${TMP}/llama.yaml"

pass=0
fail=0
assert_ok() {
	local desc="$1"
	shift
	if "$@" >/dev/null 2>&1; then
		echo "  ✔ $desc"
		pass=$((pass + 1))
	else
		echo "  ❌ $desc" >&2
		fail=$((fail + 1))
	fi
}

assert_fail() {
	local desc="$1"
	shift
	if ! "$@" >/dev/null 2>&1; then
		echo "  ✔ $desc"
		pass=$((pass + 1))
	else
		echo "  ❌ $desc (expected failure)" >&2
		fail=$((fail + 1))
	fi
}

echo "Running dx-svc hermetic tests..."

# 1. Help & status
t_status_table() {
	local out
	out="$("$DX_SVC" status)"
	grep -q "searxng" <<<"$out" && grep -q "llama" <<<"$out"
}
t_alias_audio() {
	local out
	out="$("$DX_SVC" status audio)"
	grep -q "aistudio-audio.service" <<<"$out"
}
t_llama_local() {
	local out
	out="$("$DX_SVC" status)"
	grep "llama" <<<"$out" | grep -q "local-only"
}
t_gpu_tag() {
	local out
	out="$("$DX_SVC" status)"
	grep "audio" <<<"$out" | grep -q "GPU"
}

assert_ok "status table renders all synthetic units" t_status_table
assert_ok "status resolves alias 'audio' -> aistudio-audio.service" t_alias_audio
assert_ok "nomad-llama marked local-only in status table" t_llama_local
assert_ok "GPU tag detected from AddDevice=nvidia.com/gpu" t_gpu_tag

# 2. Security: nomad-llama remote exposure must be refused
assert_fail "remote on llama is hard-refused (port 61383 has no auth)" "$DX_SVC" remote on llama

# 3. Unknown service fails cleanly
assert_fail "unknown service returns non-zero" "$DX_SVC" status nonexistent-svc

# 4. Offline mode toggle creates/removes env + Quadlet drop-ins
t_offline_on() {
	"$DX_SVC" offline on >/dev/null
	[[ -f "$XDG_CONFIG_HOME/dx-svc/offline.env" ]]
	grep -q "HF_HUB_OFFLINE=1" "$HOME/.config/containers/systemd/aistudio-audio.container.d/20-offline.conf"
}
t_offline_off() {
	"$DX_SVC" offline off >/dev/null
	[[ ! -f "$XDG_CONFIG_HOME/dx-svc/offline.env" ]]
	[[ ! -f "$HOME/.config/containers/systemd/aistudio-audio.container.d/20-offline.conf" ]]
}
assert_ok "offline on creates offline.env and 20-offline.conf drop-ins" t_offline_on
assert_ok "offline off removes offline.env and drop-ins" t_offline_off

# 5. Retired GGUF detection (dry-run never deletes; identifies retired only)
t_prune_gguf() {
	local out
	out="$("$DX_SVC" prune)"
	grep -q "retired/old.gguf" <<<"$out"
	if grep -q "active/keep.gguf" <<<"$out"; then return 1; fi
	[[ -f "$DX_SVC_GGUF_DIR/retired/old.gguf" ]]
}
assert_ok "prune dry-run flags retired/old.gguf and spares active/keep.gguf" t_prune_gguf

# 6. Offline fast-fail on missing image
assert_fail "up --offline fails fast when image is not cached" "$DX_SVC" up audio --offline

echo "dx-svc tests: ${pass} passed, ${fail} failed"
[[ "$fail" -eq 0 ]]
