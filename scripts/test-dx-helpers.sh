#!/usr/bin/env bash
# Hermetic smoke tests for critical DX helpers:
#   - files/system/usr/libexec/bazzite-dx-serve
#   - files/system/usr/libexec/project-nomad-loopback-apps (PortBindings rewriter)
#   - files/system/usr/libexec/bazzite-dx-recoll-index
#   - files/system/usr/lib/tmpfiles.d/*.conf (/var/srv +C contract)
set -euo pipefail

REPO_ROOT="$(cd -P -- "$(dirname -- "$0")/.." && pwd -P)"
SERVE_BIN="${REPO_ROOT}/files/system/usr/libexec/bazzite-dx-serve"
RECOLL_BIN="${REPO_ROOT}/files/system/usr/libexec/bazzite-dx-recoll-index"
TMPFILES_DIR="${REPO_ROOT}/files/system/usr/lib/tmpfiles.d"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

MOCK_BIN="${TMP}/bin"
mkdir -p "$MOCK_BIN"

pass=0
fail=0
assert_ok() {
	local name="$1"
	shift
	if "$@"; then
		printf '  [PASS] %s\n' "$name"
		pass=$((pass + 1))
	else
		printf '  [FAIL] %s\n' "$name" >&2
		fail=$((fail + 1))
	fi
}

echo "Running hermetic helper tests..."

# --- 1. bazzite-dx-serve ------------------------------------------------------
cat >"${MOCK_BIN}/tailscale" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
case "${1:-} ${2:-}" in
"serve status")
	cat "${MOCK_TS_SERVE_JSON}"
	;;
"status --json")
	cat "${MOCK_TS_STATUS_JSON}"
	;;
"serve --bg")
	echo "SERVE_BG:$*" >>"${MOCK_TS_LOG}"
	;;
"serve --https="*)
	echo "SERVE_OFF:$*" >>"${MOCK_TS_LOG}"
	;;
*)
	echo "OTHER:$*" >>"${MOCK_TS_LOG}"
	;;
esac
EOF
chmod +x "${MOCK_BIN}/tailscale"

export MOCK_TS_SERVE_JSON="${TMP}/ts-serve.json"
export MOCK_TS_STATUS_JSON="${TMP}/ts-status.json"
export MOCK_TS_LOG="${TMP}/ts.log"
: >"$MOCK_TS_LOG"

cat >"$MOCK_TS_SERVE_JSON" <<'EOF'
{
  "Web": {
    "g15.tailnet.ts.net:61380": { "Handlers": { "/": { "Proxy": "http://127.0.0.1:61380" } } },
    "g15.tailnet.ts.net:443":   { "Handlers": { "/": { "Proxy": "http://127.0.0.1:61337" } } }
  }
}
EOF
cat >"$MOCK_TS_STATUS_JSON" <<'EOF'
{ "BackendState": "Running", "Self": { "Online": true } }
EOF

test_serve_ok() {
	local out
	out="$(PATH="${MOCK_BIN}:$PATH" "$SERVE_BIN" status 61380)"
	[[ "$out" == "ok" ]]
}
test_serve_misplaced() {
	local out
	out="$(PATH="${MOCK_BIN}:$PATH" "$SERVE_BIN" status 61337)"
	[[ "$out" == "misplaced:g15.tailnet.ts.net:443" ]]
}
test_serve_absent() {
	local out
	out="$(PATH="${MOCK_BIN}:$PATH" "$SERVE_BIN" status 61384)"
	[[ "$out" == "absent" ]]
}
test_serve_ensure_stopped() {
	printf '{"BackendState":"Stopped","Self":{"Online":false}}\n' >"$MOCK_TS_STATUS_JSON"
	if PATH="${MOCK_BIN}:$PATH" "$SERVE_BIN" ensure 61384 >/dev/null 2>&1; then
		return 1
	fi
	printf '{"BackendState":"Running","Self":{"Online":true}}\n' >"$MOCK_TS_STATUS_JSON"
}
test_serve_ensure_publishes() {
	: >"$MOCK_TS_LOG"
	PATH="${MOCK_BIN}:$PATH" "$SERVE_BIN" ensure 61384 >/dev/null
	grep -qF 'SERVE_BG:serve --bg --https=61384 http://127.0.0.1:61384' "$MOCK_TS_LOG"
}
test_serve_ensure_misplaced_does_not_overwrite() {
	: >"$MOCK_TS_LOG"
	local out
	out="$(PATH="${MOCK_BIN}:$PATH" "$SERVE_BIN" ensure 61337)"
	grep -qF 'listener errado: g15.tailnet.ts.net:443' <<<"$out"
	[[ ! -s "$MOCK_TS_LOG" ]]
}

assert_ok "bazzite-dx-serve: status ok" test_serve_ok
assert_ok "bazzite-dx-serve: status misplaced" test_serve_misplaced
assert_ok "bazzite-dx-serve: status absent" test_serve_absent
assert_ok "bazzite-dx-serve: ensure fails when tailscale stopped" test_serve_ensure_stopped
assert_ok "bazzite-dx-serve: ensure publishes absent port" test_serve_ensure_publishes
assert_ok "bazzite-dx-serve: ensure warns without clobbering misplaced listener" test_serve_ensure_misplaced_does_not_overwrite

# --- 2. project-nomad-loopback-apps (PortBindings rewriter) -------------------
test_loopback_rewrite() {
	python3 - <<'PY'
import base64, json, re

def rewrite_rows(rows):
    out = []
    for line in rows.splitlines():
        name, b64 = line.split("\t", 1)
        if not re.fullmatch(r"[a-z0-9_]+", name):
            continue
        cfg = json.loads(base64.b64decode(b64.replace("\\n", "")))
        changed = False
        for bindings in (cfg.get("HostConfig", {}).get("PortBindings") or {}).values():
            for b in bindings or []:
                if b.get("HostIp") in (None, "", "0.0.0.0", "::"):
                    b["HostIp"] = "127.0.0.1"
                    changed = True
        if changed:
            out.append((name, cfg))
    return out

def enc(obj):
    return base64.b64encode(json.dumps(obj).encode()).decode()

rows = "\n".join([
    f"qdrant\t{enc({'HostConfig': {'PortBindings': {'6333/tcp': [{'HostPort': '6333'}], '6334/tcp': [{'HostIp': '0.0.0.0', 'HostPort': '6334'}]}}})}",
    f"safe_app\t{enc({'HostConfig': {'PortBindings': {'8080/tcp': [{'HostIp': '127.0.0.1', 'HostPort': '8080'}]}}})}",
    f"bad;DROP\t{enc({'HostConfig': {'PortBindings': {'9000/tcp': [{'HostIp': '::', 'HostPort': '9000'}]}}})}",
])
res = rewrite_rows(rows)
assert len(res) == 1 and res[0][0] == "qdrant", res
pb = res[0][1]["HostConfig"]["PortBindings"]
assert pb["6333/tcp"][0]["HostIp"] == "127.0.0.1"
assert pb["6334/tcp"][0]["HostIp"] == "127.0.0.1"
PY
}

assert_ok "project-nomad-loopback-apps: rewrites 0.0.0.0/empty, keeps 127.0.0.1, rejects invalid names" test_loopback_rewrite

# --- 3. bazzite-dx-recoll-index (image from Quadlet + workspaces.dirs) --------
cat >"${MOCK_BIN}/podman" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
case "${1:-}" in
ps) exit 0 ;;
rm) exit 0 ;;
run)
	printf '%s\n' "$@" >"${MOCK_PODMAN_ARGS}"
	exit 0
	;;
esac
EOF
chmod +x "${MOCK_BIN}/podman"

test_recoll_index_resolution() {
	local rtmp="${TMP}/recoll"
	mkdir -p "${rtmp}/home/Documents" "${rtmp}/home/dev/proj" "${rtmp}/home/.config/bazzite-dx" "${rtmp}/units"
	cat >"${rtmp}/units/mesh-recoll.container" <<'EOF'
[Container]
Image=docker.io/ageos/recoll-webui:test@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
EOF
	# shellcheck disable=SC2088
	printf '~/dev/proj\n# comment\n' >"${rtmp}/home/.config/bazzite-dx/workspaces.dirs"
	export MOCK_PODMAN_ARGS="${rtmp}/podman.args"
	HOME="${rtmp}/home" DX_SVC_UNIT_DIR="${rtmp}/units" PATH="${MOCK_BIN}:$PATH" "$RECOLL_BIN" -z >/dev/null
	grep -qxF 'docker.io/ageos/recoll-webui:test@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa' "$MOCK_PODMAN_ARGS"
	grep -qxF "${rtmp}/home/dev/proj:/export/proj:ro" "$MOCK_PODMAN_ARGS"
	grep -qxF -- '-z' "$MOCK_PODMAN_ARGS"
}

assert_ok "bazzite-dx-recoll-index: resolves Image= from mesh-recoll.container & mounts workspaces" test_recoll_index_resolution

# --- 4. tmpfiles.d /var/srv +C declarative contract ---------------------------
test_tmpfiles_srv_contract() {
	local tf_tmp="${TMP}/tmpfiles"
	mkdir -p "$tf_tmp"
	cp "$TMPFILES_DIR"/*.conf "$tf_tmp/"
	# Simulate root-only /usr/lib/tmpfiles.d/audit.conf (0000) to verify parser skips unreadable files
	printf 'd /var/log/audit 0700 root root -\n' >"${tf_tmp}/audit.conf"
	chmod 000 "${tf_tmp}/audit.conf"
	local list count
	list="$(
		for tf in "$tf_tmp"/*.conf; do
			[[ -r "$tf" ]] || continue
			awk '$1 == "h" && $2 ~ /^\/var\/srv\// && $NF ~ /\+C/ {print $2}' "$tf"
		done | sort -u
	)"
	chmod 644 "${tf_tmp}/audit.conf"
	count="$(wc -l <<<"$list")"
	[[ "$count" -ge 15 ]]
	grep -qxF '/var/srv/visual/models' <<<"$list"
	grep -qxF '/var/srv/audio/tts/models' <<<"$list"
	grep -qxF '/var/srv/nomad/mysql' <<<"$list"
	grep -qxF '/var/srv/rustdesk' <<<"$list"
}

assert_ok "tmpfiles.d: declares /var/srv +C targets for nomad, visual & audio" test_tmpfiles_srv_contract

echo "Result: ${pass} passed, ${fail} failed."
[[ "$fail" -eq 0 ]]
