# Auto NuRec — Dockerized Mono-Camera Reconstruction Pipeline

One-shot Docker pipeline for **NVIDIA NuRec** neural reconstruction from a single (mono) pinhole camera. Runs [COLMAP](https://colmap.github.io/) for structure-from-motion and [3DGRUT](https://github.com/nv-tlabs/3dgrut) for dense 3D Gaussian reconstruction, then exports USDZ for [Isaac Sim](https://developer.nvidia.com/isaac-sim).

Based on the official workflow: [Reconstruct Scenes from Mono Camera Data](https://docs.nvidia.com/nurec/robotics/neural_reconstruction_mono.html).

## Requirements

- **Host**: Linux x86_64 — **aarch64 is not supported** (e.g. DGX Spark / Grace Hopper). Dependencies including `usd-core` (USDZ export) and `gcc_linux-64` (conda) have no aarch64 builds. Build and run this on an x86_64 machine.
- [NVIDIA Container Toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/install-guide.html) (for GPU access in Docker)
- **Hardware**: NVIDIA GPU (CUDA 11.8+ compatible)
- **Input**: Project folder whose only required content is an **`images/`** subfolder with pinhole-camera photos (e.g. smartphone). You do **not** need to install or run COLMAP on your host — the image already includes COLMAP and runs it inside the container.

## Quick start (images only)

The container has **COLMAP and 3DGUT** installed. You only need to provide a folder that contains an **`images`** subfolder with your photos. The pipeline will run COLMAP (SfM) and then 3DGUT (neural reconstruction) in one go.

```bash
# Your folder can be just:  my_project/images/*.jpg
# --shm-size: PyTorch DataLoader needs more than Docker’s default 64MB /dev/shm
docker run --gpus all --shm-size=8g -v /path/to/my_project:/data auto-nurec
```

All outputs (`database.db`, `sparse/`, `3dgrut/` with `export_last.usdz`) are written into the same project folder.

## Project layout

**Input:** Your project directory must contain an `images/` subfolder with pinhole-camera photos.

**After the pipeline**, the layout matches a typical COLMAP + 3DGUT run (same as running 3DGUT manually with `path=<project>` and `out_dir=<project>/3dgrut`):

```
/path/to/project/
├── images/           # Your photos (JPEG/PNG, pinhole) — required upfront
├── database.db       # COLMAP database (created by pipeline)
├── sparse/           # COLMAP sparse reconstruction (created by pipeline)
│   └── 0/
│       ├── cameras.bin
│       ├── images.bin
│       └── points3D.bin
└── 3dgrut/           # 3DGUT outputs (configurable via OUT_SUBDIR)
    └── <experiment_name>/
        └── <run-timestamp>/
            ├── export_last.usdz   # Import this in Isaac Sim
            ├── export_last.ingp
            ├── ckpt_last.pt
            └── ...
```

Capture tips (from the [NuRec docs](https://docs.nvidia.com/nurec/robotics/neural_reconstruction_mono.html)):

- ~60% overlap between consecutive shots
- Steady lighting, locked focus/exposure where possible
- Shutter ≥ 1/100 s; avoid motion blur
- Use JPEG or PNG (convert HEIC to JPG if needed)

## Build

The image includes **COLMAP** (apt) and **3DGUT** (conda env). Build from this folder:

```bash
docker build -t auto-nurec -f Dockerfile .
```

## Run

Mount your project directory at `/data` (or set `PROJECT_DIR` to the mount path). The container expects `PROJECT_DIR/images` to exist. Use **`--shm-size=8g`** so PyTorch DataLoader workers have enough shared memory (Docker default 64MB is too small).

```bash
docker run --gpus all --shm-size=8g -v /path/to/your/project:/data auto-nurec
```

Results appear under the project folder:

- `database.db` and `sparse/0/` at **project root** (COLMAP output; 3DGUT uses project root as `path`)
- `3dgrut/` (or `OUT_SUBDIR`) — training outputs; **`export_last.usdz`** is under `<experiment_name>/<run-timestamp>/` for Isaac Sim

### Environment variables

| Variable | Default | Description |
|----------|---------|-------------|
| `PROJECT_DIR` | `/data` | Project root (must contain `images/`) |
| `OUT_SUBDIR` | `3dgrut` | Subfolder name for 3DGUT outputs |
| `EXPERIMENT_NAME` | `3dgut_mcmc` | Experiment name for logs/checkpoints |
| `EXPORT_USDZ` | `true` | Export USDZ for Isaac Sim |
| `COLMAP_MAX_IMAGE_SIZE` | `2000` | Max image dimension for COLMAP feature extraction |

Example with custom output dir and experiment name:

```bash
docker run --gpus all --shm-size=8g \
  -v /path/to/project:/data \
  -e OUT_SUBDIR=my_run \
  -e EXPERIMENT_NAME=kitchen_01 \
  auto-nurec
```

## Outputs

- **`export_last.usdz`** — Under `3dgrut/<experiment_name>/<run-timestamp>/`. Load in Isaac Sim: **File → Import** (or drag into the viewport). Add a ground plane for physics and proxy for shadows; see the [NuRec mono workflow](https://docs.nvidia.com/nurec/robotics/neural_reconstruction_mono.html#deploy-in-isaac-sim).
- Checkpoints (`ckpt_last.pt`), INPG (`export_last.ingp`), and iteration outputs in the same run folder.

## Troubleshooting

- **`RuntimeError: unable to allocate shared memory(shm)`**: Add **`--shm-size=8g`** (or at least `1g`) to `docker run`. PyTorch DataLoader needs more than Docker’s default 64MB `/dev/shm`.
- **COLMAP “No good initial image pair”**: COLMAP produced a weak or empty sparse model. Improve overlap (~60%), lighting, and focus; avoid blur and mixed focal lengths. You can still run 3DGUT if `sparse/0` exists, but quality may be poor.
- **COLMAP fails / no `sparse/0`**: Check overlap and image quality; ensure enough in-focus, non-blurry images and consistent camera (single pinhole). Try lowering `COLMAP_MAX_IMAGE_SIZE` if you hit memory limits.
- **Out of GPU memory (3DGUT)**: Use smaller images (e.g. resize before capture or reduce `COLMAP_MAX_IMAGE_SIZE`) or a GPU with more VRAM.
- **CUDA/GPU not seen in container**: Use `docker run --gpus all` and ensure the [NVIDIA Container Toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/install-guide.html) is installed.

## References

- [NuRec — Reconstruct Scenes from Mono Camera Data](https://docs.nvidia.com/nurec/robotics/neural_reconstruction_mono.html)
- [3DGUT (3D Gaussian Ray Tracing)](https://github.com/nv-tlabs/3dgrut)
- [COLMAP](https://colmap.github.io/)
