# Declarative builder for upstream leejet/stable-diffusion.cpp (master, CUDA 13 / sm_86).
# Produces /out/sd-cli compatible with docker.io/yanwk/comfyui-boot:cu130-slim-v2.
# Invoked via: ujust visual build-sdcpp
FROM docker.io/yanwk/comfyui-boot:base-cu130-devel

RUN dnf install -y -q cmake make git && dnf clean all

ARG SDCPP_REF=master
RUN git clone --depth 1 --branch "${SDCPP_REF}" --recursive https://github.com/leejet/stable-diffusion.cpp /src && \
    cmake -S /src -B /build \
      -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_CUDA_ARCHITECTURES=86 \
      -DSD_CUDA=ON \
      -DGGML_CUDA_FA=ON && \
    cmake --build /build --config Release -j"$(nproc)" --target sd-cli
