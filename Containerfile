# Builder Stage for AWCC native RPM packaging
FROM ghcr.io/ublue-os/bazzite-dx-nvidia:stable AS builder
WORKDIR /tmp/rpmbuild
# Install rpm tools and required build dependencies explicitly
# We use --setopt=*.exclude= to bypass Bazzite's strict mesa package exclusion rules temporarily
RUN dnf5 install -y --setopt=*.exclude= rpm-build rpmdevtools dnf5-plugins \
    cmake ninja-build meson gcc-c++ git libX11-devel libxkbcommon-devel \
    glfw-devel systemd-devel libudev-devel libglvnd-devel wayland-devel

COPY build_files/awcc.spec .

# Fetch sources, build RPM, and extract it
RUN rpmdev-setuptree && \
    spectool -g -R awcc.spec && \
    rpmbuild -ba awcc.spec && \
    cp /root/rpmbuild/RPMS/x86_64/awcc*.rpm /tmp/

# Allow build scripts to be referenced without being copied into the final image
FROM scratch AS ctx
COPY system_files /system_files
COPY build_files /build_files

# Base Image
ARG BASE_IMAGE="ghcr.io/ublue-os/bazzite-dx-nvidia:stable"
FROM ${BASE_IMAGE}

## Other possible base images include:
# FROM ghcr.io/ublue-os/bazzite:latest
# FROM ghcr.io/ublue-os/bluefin-nvidia:stable
# 
# ... and so on, here are more base images
# Universal Blue Images: https://github.com/orgs/ublue-os/packages
# Fedora base image: quay.io/fedora/fedora-bootc:41
# CentOS base images: quay.io/centos-bootc/centos-bootc:stream10

### [IM]MUTABLE /opt
## Some bootable images, like Fedora, have /opt symlinked to /var/opt, in order to
## make it mutable/writable for users. However, some packages write files to this directory,
## thus its contents might be wiped out when bootc deploys an image, making it troublesome for
## some packages. Eg, google-chrome, docker-desktop.
##
## Uncomment the following line if one desires to make /opt immutable and be able to be used
## by the package manager.

# RUN rm /opt && mkdir /opt

### MODIFICATIONS
## make modifications desired in your image and install packages by modifying the build.sh script
## the following RUN directive does all the things required to run "build.sh" as recommended.

RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=bind,from=builder,source=/tmp,target=/tmp/builder_artifacts \
    --mount=type=cache,dst=/var/cache \
    --mount=type=cache,dst=/var/log \
    --mount=type=tmpfs,dst=/tmp \
    cp -rv /ctx/system_files/. / && \
    /ctx/build_files/build.sh
    
### LINTING
## Verify final image and contents are correct.
RUN bootc container lint
