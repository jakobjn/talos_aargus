#!/usr/bin/env bash

set -euo pipefail

CONDA_ENV="${CONDA_ENV:-talos2_env}"
APPTAINER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
ASSETS_DIR="${APPTAINER_DIR}/assets"

mkdir -p "${ASSETS_DIR}"

if [[ -n "${CONDA_EXE:-}" ]]; then
    CONDA_BIN="${CONDA_EXE}"
elif command -v conda >/dev/null 2>&1; then
    CONDA_BIN="$(command -v conda)"
else
    echo "[ERROR] Could not find conda. Activate conda or set CONDA_EXE." >&2
    exit 1
fi

CONDA_BASE="$("${CONDA_BIN}" info --base)"
source "${CONDA_BASE}/etc/profile.d/conda.sh"
conda activate "${CONDA_ENV}"

ENV_PREFIX="${CONDA_PREFIX}"
if [[ -z "${ENV_PREFIX}" || ! -d "${ENV_PREFIX}" ]]; then
    echo "[ERROR] Active conda prefix for '${CONDA_ENV}' was not found." >&2
    exit 1
fi

ENV_TAR="${ASSETS_DIR}/${CONDA_ENV}.tar.gz"
MANIFEST="${ASSETS_DIR}/${CONDA_ENV}.manifest.txt"
CHECKSUM="${ASSETS_DIR}/${CONDA_ENV}.sha256"

echo "[INFO] Staging ${CONDA_ENV} from ${ENV_PREFIX}"
tar \
    --exclude='*.pyc' \
    --exclude='__pycache__' \
    --exclude='conda-meta/history' \
    -C / \
    -czf "${ENV_TAR}" \
    "${ENV_PREFIX#/}"

{
    echo "env_name=${CONDA_ENV}"
    echo "env_prefix=${ENV_PREFIX}"
    echo "created_at=$(date -Iseconds)"
    echo "host=$(hostname)"
    echo "python=$("${ENV_PREFIX}/bin/python" --version 2>&1)"
    echo "nextflow=$("${ENV_PREFIX}/bin/nextflow" -version 2>&1 | head -n 1)"
    echo "bcftools=$("${ENV_PREFIX}/bin/bcftools" --version 2>&1 | head -n 1)"
} > "${MANIFEST}"

sha256sum "${ENV_TAR}" > "${CHECKSUM}"

echo "[INFO] Wrote ${ENV_TAR}"
echo "[INFO] Wrote ${MANIFEST}"
echo "[INFO] Wrote ${CHECKSUM}"
