#!/usr/bin/env bash
# NuRec mono-camera pipeline: COLMAP (SfM) + 3DGUT (neural reconstruction).
# Expects PROJECT_DIR to contain an "images" subfolder with pinhole camera photos.
# Layout matches successful run: database.db + sparse/ at project root, path=PROJECT_DIR.
# See: https://docs.nvidia.com/nurec/robotics/neural_reconstruction_mono.html

set -euo pipefail

# Headless Qt for COLMAP in Docker (no display)
export QT_QPA_PLATFORM=offscreen

PROJECT_DIR="${PROJECT_DIR:-/data}"
OUT_SUBDIR="${OUT_SUBDIR:-3dgrut}"
EXPERIMENT_NAME="${EXPERIMENT_NAME:-3dgut_mcmc}"
EXPORT_USDZ="${EXPORT_USDZ:-true}"
COLMAP_MAX_IMAGE_SIZE="${COLMAP_MAX_IMAGE_SIZE:-2000}"

IMAGES_DIR="${PROJECT_DIR}/images"
OUT_DIR="${PROJECT_DIR}/${OUT_SUBDIR}"

if [[ ! -d "$IMAGES_DIR" ]]; then
  echo "ERROR: Project directory must contain 'images' subfolder: $IMAGES_DIR" >&2
  exit 1
fi

echo "=== NuRec pipeline ==="
echo "  PROJECT_DIR (path for 3DGUT): $PROJECT_DIR"
echo "  Output dir (out_dir):         $OUT_DIR"
echo ""

# --- Step 1: COLMAP outputs at project root (database.db, sparse/) so path=PROJECT_DIR works for 3DGUT
# Remove existing COLMAP outputs to avoid SQLite/schema conflicts
rm -f "$PROJECT_DIR/database.db"
rm -rf "$PROJECT_DIR/sparse"
mkdir -p "$PROJECT_DIR/sparse"

# --- Step 2: COLMAP feature extraction (tutorial: feature detection & extraction)
# https://docs.nvidia.com/nurec/robotics/neural_reconstruction_mono.html#using-colmap-command-line
echo "=== COLMAP: feature extraction ==="
colmap feature_extractor \
  --database_path "$PROJECT_DIR/database.db" \
  --image_path "$IMAGES_DIR" \
  --ImageReader.single_camera 1 \
  --ImageReader.camera_model PINHOLE \
  --SiftExtraction.max_image_size "$COLMAP_MAX_IMAGE_SIZE" \
  --SiftExtraction.estimate_affine_shape 1 \
  --SiftExtraction.domain_size_pooling 1

# --- Step 3: COLMAP feature matching (tutorial: exhaustive_matcher with SiftMatching.use_gpu 1)
# GPU needs OpenGL context; we use Xvfb in entrypoint. Set COLMAP_USE_GPU_MATCHING=0 to force CPU.
COLMAP_GPU_MATCH="${COLMAP_USE_GPU_MATCHING:-1}"
echo "=== COLMAP: feature matching (use_gpu=${COLMAP_GPU_MATCH}) ==="
colmap exhaustive_matcher \
  --database_path "$PROJECT_DIR/database.db" \
  --SiftMatching.use_gpu "$COLMAP_GPU_MATCH"

# --- Step 4: COLMAP mapper / Global SfM (tutorial: mapper)
echo "=== COLMAP: mapper (SfM) ==="
colmap mapper \
  --database_path "$PROJECT_DIR/database.db" \
  --image_path "$IMAGES_DIR" \
  --output_path "$PROJECT_DIR/sparse"

if [[ ! -d "$PROJECT_DIR/sparse/0" ]]; then
  echo "ERROR: COLMAP did not produce sparse/0 (reconstruction may have failed)." >&2
  exit 1
fi

echo "COLMAP sparse reconstruction done: $PROJECT_DIR/sparse/0"
echo ""

# --- Step 5: 3DGUT training and USDZ export (path=PROJECT_DIR, out_dir=PROJECT_DIR/3dgrut)
echo "=== 3DGUT: training and export ==="
mkdir -p "$OUT_DIR"

# Run from 3dgrut repo root so Hydra finds configs; path = project root (images/ + sparse/0/ there)
cd /opt/3dgrut && python train.py \
  --config-name apps/colmap_3dgut_mcmc.yaml \
  path="$PROJECT_DIR" \
  out_dir="$OUT_DIR" \
  experiment_name="$EXPERIMENT_NAME" \
  export_usdz.enabled="$EXPORT_USDZ" \
  export_usdz.apply_normalizing_transform=true

echo ""
echo "=== Pipeline complete ==="
echo "  path:   $PROJECT_DIR (images/ + sparse/0/ + database.db)"
echo "  out_dir: $OUT_DIR"
echo "  USDZ:   see experiment subfolder under out_dir, e.g. $OUT_DIR/<experiment>/export_last.usdz"
echo "  Load export_last.usdz in Isaac Sim (File → Import)."
