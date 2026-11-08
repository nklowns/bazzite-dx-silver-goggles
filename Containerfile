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

ARG BASE_IMAGE=ghcr.io/ublue-os/bazzite-nvidia:45.20261105
ARG BASE_IMAGE_DIGEST=sha256:1d86fe5e788d651827757cbcdb01b17b1b5727995c0691419d6136b28cd50c97

# Build context, kept out of the final image.
FROM scratch AS ctx
COPY build_files /build_files
COPY packages /packages
COPY files/justfiles /just
COPY files/system /system_files
COPY modules /modules

FROM ${BASE_IMAGE}@${BASE_IMAGE_DIGEST}

ARG IMAGE_NAME=bazzite-dx-silver-goggles
ARG IMAGE_VENDOR=nklowns
ENV IMAGE_NAME=${IMAGE_NAME} IMAGE_VENDOR=${IMAGE_VENDOR}

RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=cache,dst=/var/cache/libdnf5 \
    --mount=type=cache,dst=/var/cache/dnf \
    --mount=type=tmpfs,dst=/tmp \
    /ctx/build_files/build.sh

CMD ["/sbin/init"]
