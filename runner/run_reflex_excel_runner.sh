#!/usr/bin/env bash
set -euo pipefail
umask 002

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

FRONTEND_PORT="${REFLEX_FRONTEND_PORT:-3100}"
BACKEND_PORT="${REFLEX_BACKEND_PORT:-8100}"
REFLEX_ARGS=(
  --frontend-port "$FRONTEND_PORT"
  --backend-port "$BACKEND_PORT"
  "$@"
)

echo "Starting TALOS AARGUS TEST RUNNER"
echo "Frontend: http://localhost:${FRONTEND_PORT}"
echo "Backend:  http://localhost:${BACKEND_PORT}"

if [[ -n "${REFLEX_CONDA_ENV:-}" ]]; then
  conda run -n "$REFLEX_CONDA_ENV" reflex run "${REFLEX_ARGS[@]}"
elif [[ -n "${REFLEX_CONDA_PREFIX:-}" ]]; then
  conda run -p "$REFLEX_CONDA_PREFIX" reflex run "${REFLEX_ARGS[@]}"
elif command -v uv >/dev/null 2>&1; then
  uv run reflex run "${REFLEX_ARGS[@]}"
elif conda env list | awk '{print $1}' | grep -qx "talos_env"; then
  conda run -n talos_env reflex run "${REFLEX_ARGS[@]}"
else
  reflex run "${REFLEX_ARGS[@]}"
fi
