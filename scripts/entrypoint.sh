#!/usr/bin/env bash
set -eo pipefail
# Virtual display for COLMAP GPU feature matching (OpenGL context)
export DISPLAY=:99
Xvfb :99 -screen 0 1024x768x24 -ac &
XVFB_PID=$!
sleep 2
# Allow unbound vars during conda activate (env's activate.d may reference ADDR2LINE etc.)
set +u
source /opt/conda/etc/profile.d/conda.sh
conda activate 3dgrut
set -u
/opt/auto-nurec/scripts/run_pipeline.sh "$@"
EXIT=$?
kill $XVFB_PID 2>/dev/null || true
exit $EXIT
