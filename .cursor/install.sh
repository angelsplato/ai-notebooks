#!/usr/bin/env bash
# Idempotent Cloud Agent bootstrap for the ai-notebooks repository.
#
# The notebooks target TensorFlow 2 / Keras 2 (circa 2019-2021) and the classic
# pre-0.26 OpenAI Gym API. TensorFlow 2.12 (bundled Keras 2.12) is the newest
# release that runs them unmodified, and it requires Python <= 3.11. Since the
# base image ships Python 3.12, we provision Python 3.11 with `uv`, create a
# virtualenv with the pinned stack, and register a Jupyter kernel so both
# JupyterLab and `jupyter nbconvert --execute` use it.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VENV_DIR="${VENV_DIR:-$HOME/.venv-ai}"
PY_VERSION="3.11"

echo "==> Installing system packages (swig, C/C++ toolchain, curl)"
# swig + gcc/g++ are required to build the box2d-py wheel (LunarLander env).
if command -v swig >/dev/null 2>&1 && command -v g++ >/dev/null 2>&1 && command -v curl >/dev/null 2>&1; then
  echo "    system build tools already present, skipping apt"
else
  if command -v sudo >/dev/null 2>&1; then APT="sudo apt-get"; else APT="apt-get"; fi
  export DEBIAN_FRONTEND=noninteractive
  # apt mirrors occasionally return transient 5xx errors; retry a few times.
  for attempt in 1 2 3 4 5; do
    if $APT update -qq; then break; fi
    echo "    apt-get update failed (attempt $attempt), retrying in $((attempt*4))s..."
    sleep $((attempt*4))
  done
  $APT install -y -qq --no-install-recommends swig build-essential python3-dev curl ca-certificates
fi

echo "==> Ensuring uv (Python version manager) is available"
export PATH="$HOME/.local/bin:$PATH"
if ! command -v uv >/dev/null 2>&1; then
  curl -LsSf https://astral.sh/uv/install.sh | sh
  export PATH="$HOME/.local/bin:$PATH"
fi
uv python install "$PY_VERSION"

echo "==> Creating/refreshing Python $PY_VERSION virtualenv at $VENV_DIR"
if [ ! -x "$VENV_DIR/bin/python" ]; then
  uv venv --python "$PY_VERSION" "$VENV_DIR"
fi
# shellcheck disable=SC1091
source "$VENV_DIR/bin/activate"

echo "==> Installing Python dependencies"
# box2d-py compiles a C++ extension; force the system GCC/G++ so it finds the
# standard library headers (uv's standalone Python defaults to a clang config
# that cannot locate <string>).
CC=gcc CXX=g++ uv pip install -r "$REPO_ROOT/requirements.txt" \
  --override "$REPO_ROOT/.cursor/pip-overrides.txt"

echo "==> Registering Jupyter kernel 'python3' -> $VENV_DIR"
# The notebooks declare kernelspec name "python3"; register that name so both
# JupyterLab and `jupyter nbconvert --execute` pick up this venv automatically.
python -m ipykernel install --user \
  --name python3 \
  --display-name "Python 3 (ai-notebooks)" \
  --env TF_CPP_MIN_LOG_LEVEL 2

echo "==> Install complete. Python: $(python --version) | TensorFlow: $(python -c 'import tensorflow as tf; print(tf.__version__)')"
