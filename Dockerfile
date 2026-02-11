# NuRec mono-camera pipeline: COLMAP + 3DGUT (NVIDIA neural reconstruction).
# Based on: https://docs.nvidia.com/nurec/robotics/neural_reconstruction_mono.html
# Requires: Docker build with GPU support (e.g. nvidia-docker2) and NVIDIA GPU at runtime.
# CUDA 12.8.1: includes Blackwell (sm_120) in TORCH_CUDA_ARCH_LIST via 3dgrut install_env.sh.

ARG CUDA_VERSION=12.8.1
FROM nvidia/cuda:${CUDA_VERSION}-devel-ubuntu22.04

ENV DEBIAN_FRONTEND=noninteractive
ENV CUDA_VERSION=12.8.1
# 3DGUT expects GCC <= 11 for nvcc
ENV CC=gcc-11
ENV CXX=g++-11

# System deps: GCC-11, COLMAP, Xvfb (virtual display for COLMAP GPU matcher OpenGL), Miniconda deps
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    git \
    gcc-11 \
    g++-11 \
    colmap \
    xvfb \
    && rm -rf /var/lib/apt/lists/*

# Miniconda (accept ToS so default channels work in non-interactive build)
RUN curl -fsSL https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh -o /tmp/miniconda.sh \
    && bash /tmp/miniconda.sh -b -p /opt/conda \
    && rm /tmp/miniconda.sh
ENV PATH="/opt/conda/bin:$PATH"
RUN conda tos accept --override-channels --channel https://repo.anaconda.com/pkgs/main \
    && conda tos accept --override-channels --channel https://repo.anaconda.com/pkgs/r

# Clone 3DGUT and install env (CUDA 12.8.1, PyTorch cu128, 3DGUT deps; archs 7.5–12.0 incl. Blackwell)
RUN git clone --recursive https://github.com/nv-tlabs/3dgrut.git /opt/3dgrut
WORKDIR /opt/3dgrut
RUN chmod +x install_env.sh \
    && bash -c 'source /opt/conda/etc/profile.d/conda.sh && ./install_env.sh 3dgrut WITH_GCC11'

# 3DGUT trainer imports viser (optional GUI); ensure it is installed for headless run
RUN bash -c 'source /opt/conda/etc/profile.d/conda.sh && conda activate 3dgrut && pip install viser'

# Pipeline scripts and default env for 3dgrut
COPY scripts/run_pipeline.sh scripts/entrypoint.sh /opt/auto-nurec/scripts/
RUN chmod +x /opt/auto-nurec/scripts/run_pipeline.sh /opt/auto-nurec/scripts/entrypoint.sh
ENV PATH="/opt/conda/envs/3dgrut/bin:$PATH"

# Default: run full pipeline. Override PROJECT_DIR by mounting volume and env.
WORKDIR /data
ENV PROJECT_DIR=/data
# Headless Qt for COLMAP (no display in container)
ENV QT_QPA_PLATFORM=offscreen
# Virtual display for COLMAP GPU matcher (SiftGPU needs OpenGL context). Set to 0 to force CPU matching.
ENV COLMAP_USE_GPU_MATCHING=1

ENTRYPOINT ["/opt/auto-nurec/scripts/entrypoint.sh"]