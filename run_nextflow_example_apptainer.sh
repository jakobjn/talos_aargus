#!/usr/bin/env bash

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
SIF_PATH="${REPO_DIR}/apptainer/build/talos-nextflow.sif"
OUTPUT_DIR="${OUTPUT_DIR:-${REPO_DIR}/nextflow_test_output_apptainer}"
FIX_PERMISSIONS="${REPO_DIR}/scripts/fix_permissions.sh"

if [[ ! -f "${SIF_PATH}" ]]; then
    echo "[ERROR] Missing SIF: ${SIF_PATH}" >&2
    echo "[INFO] Build it with: bash apptainer/build_sif.sh" >&2
    exit 1
fi

export APPTAINER_TMPDIR="${SINGULARITY_TMPDIR:-/tmp}"
export APPTAINER_CACHEDIR="${SINGULARITY_CACHEDIR:-$HOME/.apptainer/cache}"
export NXF_HOME="${NXF_HOME:-${REPO_DIR}/.nextflow-apptainer}"

mkdir -p "${OUTPUT_DIR}" "${NXF_HOME}"

apptainer exec \
    --bind "${REPO_DIR}:${REPO_DIR}" \
    --pwd "${REPO_DIR}" \
    "${SIF_PATH}" \
    nextflow -c nextflow.config run main.nf \
        --input_tsv nextflow/inputs/test.tsv \
        --processed_annotations processed_annotations \
        -output-dir "${OUTPUT_DIR}" \
        -resume

if [[ -x "${FIX_PERMISSIONS}" ]]; then
    bash "${FIX_PERMISSIONS}" "${OUTPUT_DIR}"
fi
