#!/usr/bin/env bash

# Generates the BlueBuild build-recipe.yml with OCI metadata and pinned digests.
set -euo pipefail

TARGET_IMAGE="${1:-bazzite-nvidia}"
TAG="${2:-latest}"

# Metadata Resolution
BASE_IMAGE=$(yq ".images[] | select(.name == \"${TARGET_IMAGE}\") | .image" image-versions.yaml)
BASE_TAG=$(yq ".images[] | select(.name == \"${TARGET_IMAGE}\") | .tag" image-versions.yaml)
BASE_DIGEST=$(yq ".images[] | select(.name == \"${TARGET_IMAGE}\") | .digest" image-versions.yaml)
REPO_OWNER="${GITHUB_REPOSITORY_OWNER:-$(git remote get-url origin | sed -E 's/.*[:\/](.*)\/(.*)\.git/\1/')}"
REVISION=$(git rev-parse HEAD 2>/dev/null || echo 'local')
VERSION_FULL="${BASE_TAG}.$(date +%Y%m%d)"

# Configuration Exports
export BASE_IMAGE BASE_TAG BASE_DIGEST REPO_OWNER REVISION VERSION_FULL
export IMAGE_NAME="bazzite-dx-silver-goggles"
export IMAGE_DESC="Personal DX layer for Dell G15 5520. KDE/NVIDIA — Slim Edition."
export ARTIFACTHUB_LOGO_URL="https://avatars.githubusercontent.com/u/187439889?s=200&v=4"
# ostree.linux must describe the kernel shipped in the image, not the build host.
# Inherit it from the pinned base image; fall back to the label being omitted.
KERNEL_RELEASE=""
if command -v skopeo >/dev/null 2>&1; then
	if [[ -n "$BASE_DIGEST" && "$BASE_DIGEST" != "null" ]]; then
		KERNEL_RELEASE=$(skopeo inspect --format '{{ index .Labels "ostree.linux" }}' \
			"docker://${BASE_IMAGE}@${BASE_DIGEST}" 2>/dev/null || true)
	else
		KERNEL_RELEASE=$(skopeo inspect --format '{{ index .Labels "ostree.linux" }}' \
			"docker://${BASE_IMAGE}:${BASE_TAG}" 2>/dev/null || true)
	fi
fi
export KERNEL_RELEASE

if [[ -n "$BASE_DIGEST" && "$BASE_DIGEST" != "null" ]]; then
	export IMAGE_VERSION_VAL="${BASE_TAG}@${BASE_DIGEST}"
else
	export IMAGE_VERSION_VAL="${BASE_TAG}"
fi

[[ -z "${BASE_IMAGE}" || "${BASE_IMAGE}" == "null" ]] && {
	echo "Error: Image '${TARGET_IMAGE}' not found in image-versions.yaml"
	exit 1
}

echo "Generating build recipe for ${TARGET_IMAGE} (Base: ${BASE_IMAGE}:${IMAGE_VERSION_VAL})..."

# Orchestrate Recipe Transformation
yq '
  .name = env(IMAGE_NAME) |
  .description = env(IMAGE_DESC) |
  .base-image = env(BASE_IMAGE) |
  .image-version = env(IMAGE_VERSION_VAL)
' recipes/recipe.yml >recipes/build-recipe.yml

yq -i "
  .alt-tags = ([\"latest\", \"stable\", \"${TAG}\", env(BASE_TAG)] | unique) |
  .labels.\"io.artifacthub.package.logo-url\" = env(ARTIFACTHUB_LOGO_URL) |
  .labels.\"io.artifacthub.package.readme-url\" = \"https://raw.githubusercontent.com/\" + env(REPO_OWNER) + \"/bazzite-dx-silver-goggles/main/README.md\" |
  .labels.\"io.artifacthub.package.maintainers\" = \"[{\\\"name\\\": \\\"nklowns\\\", \\\"email\\\": \\\"nklowns@users.noreply.github.com\\\"}]\" |
  .labels.\"io.artifacthub.package.keywords\" = \"bootc,bazzite,dx,silver-goggles,dell-g15,ublue,universal-blue,fedora,gaming,developer\" |
  .labels.\"io.artifacthub.package.deprecated\" = \"false\" |
  .labels.\"io.artifacthub.package.prerelease\" = \"false\" |
  .labels.\"containers.bootc\" = \"1\" |
  .labels.\"org.opencontainers.image.vendor\" = env(REPO_OWNER) |
  .labels.\"org.opencontainers.image.licenses\" = \"Apache-2.0\" |
  .labels.\"org.opencontainers.image.source\" = \"https://github.com/\" + env(REPO_OWNER) + \"/bazzite-dx-silver-goggles\" |
  .labels.\"org.opencontainers.image.url\" = \"https://github.com/\" + env(REPO_OWNER) + \"/bazzite-dx-silver-goggles\" |
  .labels.\"org.opencontainers.image.documentation\" = \"https://raw.githubusercontent.com/\" + env(REPO_OWNER) + \"/bazzite-dx-silver-goggles/main/README.md\" |
  .labels.\"org.opencontainers.image.version\" = env(VERSION_FULL) |
  .labels.\"org.opencontainers.image.revision\" = env(REVISION)
" recipes/build-recipe.yml

if [[ -n "$KERNEL_RELEASE" ]]; then
	yq -i '.labels."ostree.linux" = env(KERNEL_RELEASE)' recipes/build-recipe.yml
else
	echo "Warning: could not resolve base image kernel; omitting ostree.linux label."
fi

# NOTE: Project NOMAD image pinning is deliberately NOT generated here any more.
#
# The earlier design kept digests in image-versions.yaml and rendered a docker-compose.yml
# from a .tmpl with envsubst at build time. That bought a second copy of the truth and a way
# for the two to disagree: the rendered file was also committed, CI regenerated it, and a
# stale local copy could ship unnoticed. The Quadlet units under
# files/system/etc/containers/systemd/users/ now carry their `Image=…@sha256:…` inline, and
# Renovate updates those files directly (see the customManager in .github/renovate.json5).
# The artifact that ships is the artifact that is pinned — no template, no render step, no
# drift to police.

