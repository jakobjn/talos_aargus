#!/usr/bin/env bash

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

export APPTAINER_TMPDIR="${SINGULARITY_TMPDIR:-/tmp}"
export APPTAINER_CACHEDIR="${SINGULARITY_CACHEDIR:-$HOME/.apptainer/cache}"

cd "${REPO_DIR}"

echo "[INFO] Front-end Apptainer build starting in ${REPO_DIR}"
echo "[INFO] APPTAINER_TMPDIR=${APPTAINER_TMPDIR}"
echo "[INFO] APPTAINER_CACHEDIR=${APPTAINER_CACHEDIR}"

bash apptainer/fetch_env_to_folder.sh
bash apptainer/build_sif.sh

echo "[INFO] Front-end Apptainer build finished"
echo "[INFO] Example run: bash ./run_nextflow_example_apptainer.sh"
