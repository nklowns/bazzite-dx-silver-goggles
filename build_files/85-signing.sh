#!/usr/bin/env bash
# Container signature policy.
#
# The host ref is `ostree-image-signed:docker://ghcr.io/...`, so the image must
# carry the key and the policy that let it verify its own updates. The BlueBuild
# signing module did this at build time; the Containerfile path has to do the
# same or the next `bootc upgrade` on the host refuses the image.
set -euo pipefail

readonly IMAGE_NAME="${IMAGE_NAME:-bazzite-dx-silver-goggles}"
readonly IMAGE_VENDOR="${IMAGE_VENDOR:-nklowns}"
readonly IMAGE_REGISTRY="ghcr.io/${IMAGE_VENDOR}"
readonly IMAGE_REF="${IMAGE_REGISTRY}/${IMAGE_NAME}"
readonly KEY_PATH="/etc/pki/containers/${IMAGE_NAME}.pub"
readonly REGISTRY_FILE="/etc/containers/registries.d/${IMAGE_VENDOR}-${IMAGE_NAME}.yaml"
readonly POLICY_FILE="/etc/containers/policy.json"

echo "Installing signing key at ${KEY_PATH}"
install -Dm644 "${CONTEXT_PATH}/cosign.pub" "$KEY_PATH"

if [[ ! -f "$POLICY_FILE" ]]; then
	echo "CRITICAL: ${POLICY_FILE} missing from the base image; refusing to ship an unverifiable image."
	exit 1
fi

echo "Registering ${IMAGE_REF} as a sigstore-signed transport"
jq --arg registry "$IMAGE_REGISTRY" \
	--arg name "$IMAGE_NAME" \
	--arg key_path "$KEY_PATH" \
	'.transports.docker |=
	 { ($registry + "/" + $name): [
	     {
	       "type": "sigstoreSigned",
	       "keyPath": $key_path,
	       "signedIdentity": { "type": "matchRepository" }
	     }
	   ] } + .' \
	"$POLICY_FILE" >"/tmp/policy.json.tmp"
mv "/tmp/policy.json.tmp" "$POLICY_FILE"

# Tells containers/image to look for the sigstore attachment next to the image.
mkdir -p "$(dirname "$REGISTRY_FILE")"
cat >"$REGISTRY_FILE" <<EOF
docker:
  ${IMAGE_REF}:
    use-sigstore-attachments: true
EOF

echo "Signing policy installed for ${IMAGE_REF}"
