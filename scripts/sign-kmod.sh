#!/usr/bin/env bash
# Sign a kernel module with the silver-goggles MOK key and verify it.
# Usage: KMOD_SIGNING_KEY="<PEM>" sign-kmod.sh <module.ko> <kmod.der> [kernel-release]
# Fails closed: empty key, key/cert mismatch or missing signature is an error.
set -euo pipefail

ko=${1:?module.ko}
der=${2:?kmod.der}
kver=${3:-$(uname -r)}

[[ -n ${KMOD_SIGNING_KEY:-} ]] || {
    echo "KMOD_SIGNING_KEY is empty or unset" >&2
    exit 1
}
[[ -f $ko && -f $der ]] || {
    echo "module or certificate not found" >&2
    exit 1
}

sign_file=${SIGN_FILE:-}
if [[ -z $sign_file ]]; then
    for c in "/lib/modules/$kver/build/scripts/sign-file" "/usr/src/kernels/$kver/scripts/sign-file"; do
        [[ -x $c ]] && sign_file=$c && break
    done
fi
[[ -x $sign_file ]] || {
    echo "sign-file not found for kernel $kver" >&2
    exit 1
}

umask 077
work=$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/kmod-sign.XXXXXX")
cleanup() {
    find "$work" -type f -exec shred -u {} + 2>/dev/null || true
    rm -rf "$work"
}
trap cleanup EXIT
key=$work/key.pem
printf '%s\n' "$KMOD_SIGNING_KEY" >"$key"

# The secret must be the private half of the committed certificate.
key_fp=$(openssl pkey -in "$key" -pubout -outform DER | sha256sum | cut -d' ' -f1)
der_fp=$(openssl x509 -inform DER -in "$der" -pubkey -noout | openssl pkey -pubin -outform DER | sha256sum | cut -d' ' -f1)
if [[ $key_fp != "$der_fp" ]]; then
    echo "signing key does not match $der (key $key_fp, cert $der_fp)" >&2
    exit 1
fi

# Refuse a pre-signed input: the post-check below would pass on a foreign signature.
if tail -c 28 "$ko" | grep -q '~Module signature appended~'; then
    echo "$ko is already signed; sign the unsigned build output" >&2
    exit 1
fi

"$sign_file" sha256 "$key" "$der" "$ko"

tail -c 28 "$ko" | grep -q '~Module signature appended~' ||
    {
        echo "no module signature appended to $ko" >&2
        exit 1
    }
echo "signed $ko (sha256 $(sha256sum "$ko" | cut -d' ' -f1)), key fingerprint $der_fp"
