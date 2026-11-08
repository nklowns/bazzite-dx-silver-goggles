#
# bazzite-dx-silver-goggles — personal DX layer on top of Bazzite.
#
# Three responsibilities, nothing else:
#   1. enable the Dell G15 5520 hardware
#   2. package the engines for development, gaming and local LLM
#   3. ergonomics (ujust recipes, desktop integration)
#
# Build:  podman build -t bazzite-dx-silver-goggles .
# Test:   bcvk ephemeral run-ssh localhost/bazzite-dx-silver-goggles

# Single source of truth for the pin is image-versions.yaml; this default keeps
# `podman build .` working and `just check` asserts the two agree.
ARG BASE_IMAGE_REF=ghcr.io/ublue-os/bazzite-nvidia:45.20261105@sha256:1d86fe5e788d651827757cbcdb01b17b1b5727995c0691419d6136b28cd50c97

# Build context, kept out of the final image.
FROM scratch AS ctx
COPY build_files /build_files
COPY packages /packages
COPY files /files
COPY modules /modules
# The public key is baked into the image and referenced by the container policy,
# so the host can verify its own updates. `ostree-image-signed:docker://...`
# refuses an image that is not signed with this key.
COPY cosign.pub /cosign.pub

FROM ${BASE_IMAGE_REF}

# Re-declared inside the stage: an ARG set before FROM is only usable in the
# FROM line, so labels and the build script would see an empty value.
ARG BASE_IMAGE_REF
ARG IMAGE_NAME=bazzite-dx-silver-goggles
ARG IMAGE_VENDOR=nklowns
ARG IMAGE_VERSION=dev
ARG IMAGE_REVISION=unknown
ARG IMAGE_CREATED=unknown
ENV IMAGE_NAME=${IMAGE_NAME} IMAGE_VENDOR=${IMAGE_VENDOR}

# OCI + Artifact Hub labels. org.opencontainers.image.version is what
# `bootc status` / `rpm-ostree status` prints, so it must describe this image
# and not the base it was built from.
LABEL org.opencontainers.image.title="bazzite-dx-silver-goggles" \
      org.opencontainers.image.description="Developer Experience (DX) layer for Dell G15 5520. KDE/NVIDIA — Slim Edition." \
      org.opencontainers.image.source="https://github.com/nklowns/bazzite-dx-silver-goggles" \
      org.opencontainers.image.url="https://github.com/nklowns/bazzite-dx-silver-goggles" \
      org.opencontainers.image.documentation="https://raw.githubusercontent.com/nklowns/bazzite-dx-silver-goggles/main/README.md" \
      org.opencontainers.image.vendor="nklowns" \
      org.opencontainers.image.licenses="Apache-2.0" \
      org.opencontainers.image.version="${IMAGE_VERSION}" \
      org.opencontainers.image.revision="${IMAGE_REVISION}" \
      org.opencontainers.image.created="${IMAGE_CREATED}" \
      org.opencontainers.image.base.name="${BASE_IMAGE_REF}" \
      io.artifacthub.package.logo-url="https://avatars.githubusercontent.com/u/187439889?s=200&v=4" \
      io.artifacthub.package.readme-url="https://raw.githubusercontent.com/nklowns/bazzite-dx-silver-goggles/main/README.md" \
      io.artifacthub.package.keywords="bootc,bazzite,dx,silver-goggles,dell-g15,ublue,universal-blue,fedora,gaming,developer" \
      io.artifacthub.package.maintainers="[{name: nklowns, email: nklowns@users.noreply.github.com}]" \
      io.artifacthub.package.deprecated="false" \
      io.artifacthub.package.prerelease="false"

RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=cache,dst=/var/cache/libdnf5 \
    --mount=type=cache,dst=/var/cache/dnf \
    --mount=type=tmpfs,dst=/tmp \
    env BASE_IMAGE_REF="${BASE_IMAGE_REF}" bash /ctx/build_files/build.sh

CMD ["/sbin/init"]
