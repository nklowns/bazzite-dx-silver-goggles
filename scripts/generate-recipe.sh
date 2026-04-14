#!/usr/bin/env bash
# scripts/generate-recipe.sh
# Generates a BlueBuild build-recipe.yml with OCI metadata.

set -euo pipefail

TARGET_IMAGE="${1:-bazzite-nvidia}"
TAG="${2:-latest}"

# Resolve and Patch
BASE_IMAGE=$(yq ".images[] | select(.name == \"${TARGET_IMAGE}\") | .image" image-versions.yaml)
export BASE_IMAGE
BASE_TAG=$(yq ".images[] | select(.name == \"${TARGET_IMAGE}\") | .tag" image-versions.yaml)
export BASE_TAG
BASE_DIGEST=$(yq ".images[] | select(.name == \"${TARGET_IMAGE}\") | .digest" image-versions.yaml)
export BASE_DIGEST
export IMAGE_NAME="bazzite-dx-silver-goggles"
export IMAGE_DESC="Personal DX layer for Dell G15 5520. KDE/NVIDIA — Slim Edition."
export ARTIFACTHUB_LOGO_URL="https://avatars.githubusercontent.com/u/187439889?s=200&v=4"
REPO_OWNER="${GITHUB_REPOSITORY_OWNER:-$(git remote get-url origin | sed -E 's/.*[:\/](.*)\/(.*)\.git/\1/')}"
export REPO_OWNER
KERNEL_RELEASE=$(uname -r)
export KERNEL_RELEASE
VERSION_FULL="${BASE_TAG}.$(date +%Y%m%d)"
export VERSION_FULL
REVISION=$(git rev-parse HEAD 2>/dev/null || echo 'local')
export REVISION

if [[ -n "$BASE_DIGEST" && "$BASE_DIGEST" != "null" ]]; then
	export IMAGE_VERSION_VAL="${BASE_TAG}@${BASE_DIGEST}"
else
	export IMAGE_VERSION_VAL="${BASE_TAG}"
fi

if [ -z "${BASE_IMAGE}" ] || [ "${BASE_IMAGE}" == "null" ]; then
	echo "Error: Image '${TARGET_IMAGE}' not found in image-versions.yaml"
	exit 1
fi

echo "Generating build recipe for ${TARGET_IMAGE} (Base: ${BASE_IMAGE}:${IMAGE_VERSION_VAL})..."
mkdir -p .bluebuild

yq '
  .name = env(IMAGE_NAME) |
  .description = env(IMAGE_DESC) |
  .base-image = env(BASE_IMAGE) |
  .image-version = env(IMAGE_VERSION_VAL)
' recipes/recipe.yml >.bluebuild/build-recipe.yml

yq -i "
  .alt-tags = ([\"latest\", \"stable\", \"${TAG}\", env(BASE_TAG)] | unique) |
  .labels.\"io.artifacthub.package.logo-url\" = env(ARTIFACTHUB_LOGO_URL) |
  .labels.\"io.artifacthub.package.readme-url\" = \"https://raw.githubusercontent.com/\" + env(REPO_OWNER) + \"/bazzite-dx-silver-goggles/main/README.md\" |
  .labels.\"io.artifacthub.package.maintainers\" = \"[{\\\"name\\\": \\\"nklowns\\\", \\\"email\\\": \\\"nklowns@users.noreply.github.com\\\"}]\" |
  .labels.\"io.artifacthub.package.keywords\" = \"bootc,bazzite,dx,silver-goggles,dell-g15,ublue,universal-blue,fedora,gaming,developer\" |
  .labels.\"io.artifacthub.package.deprecated\" = \"false\" |
  .labels.\"io.artifacthub.package.prerelease\" = \"false\" |
  .labels.\"containers.bootc\" = \"1\" |
  .labels.\"ostree.linux\" = env(KERNEL_RELEASE) |
  .labels.\"org.opencontainers.image.vendor\" = env(REPO_OWNER) |
  .labels.\"org.opencontainers.image.licenses\" = \"Apache-2.0\" |
  .labels.\"org.opencontainers.image.source\" = \"https://github.com/\" + env(REPO_OWNER) + \"/bazzite-dx-silver-goggles\" |
  .labels.\"org.opencontainers.image.url\" = \"https://github.com/\" + env(REPO_OWNER) + \"/bazzite-dx-silver-goggles\" |
  .labels.\"org.opencontainers.image.documentation\" = \"https://raw.githubusercontent.com/\" + env(REPO_OWNER) + \"/bazzite-dx-silver-goggles/main/README.md\" |
  .labels.\"org.opencontainers.image.version\" = env(VERSION_FULL) |
  .labels.\"org.opencontainers.image.revision\" = env(REVISION)
" .bluebuild/build-recipe.yml
