#!/usr/bin/env bash

set -euo pipefail

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_DIR="$(cd "${BASE_DIR}/.." && pwd -P)"

SIF_PATH="${SIF_PATH:-${REPO_DIR}/apptainer/build/talos-nextflow.sif}"
PRELIGHT_WORK_ROOT="${PRELIGHT_WORK_ROOT:-/tmp/preflight_test_run}"
PRELIGHT_RESULTS_DIR="${PRELIGHT_RESULTS_DIR:-${PRELIGHT_WORK_ROOT}/results}"
TALOS_OUTPUT_DIR="${TALOS_OUTPUT_DIR:-${PRELIGHT_WORK_ROOT}/talos_outputs}"
TALOS_INPUT_TSV="${TALOS_INPUT_TSV:-${PRELIGHT_WORK_ROOT}/talos_input.tsv}"
PRELIGHT_COHORT_NAME="${PRELIGHT_COHORT_NAME:-preflight_first_trio}"
PROCESSED_ANNOTATIONS_DIR="${PROCESSED_ANNOTATIONS_DIR:-${REPO_DIR}/processed_annotations}"
TALOS_CONFIG_PATH="${TALOS_CONFIG_PATH:-${REPO_DIR}/nextflow/inputs/config.toml}"
TALOS_HISTORY_PATH="${TALOS_HISTORY_PATH:-${REPO_DIR}/nextflow/assets/NO_HISTORY}"
TALOS_EXT_IDS_PATH="${TALOS_EXT_IDS_PATH:-${REPO_DIR}/nextflow/assets/NO_FILE}"
TALOS_SEQR_MAP_PATH="${TALOS_SEQR_MAP_PATH:-${REPO_DIR}/nextflow/assets/NO_SEQR_FILE}"
TALOS_MITO_PATH="${TALOS_MITO_PATH:-${REPO_DIR}/nextflow/assets/NO_MITO}"

if [[ ! -f "${SIF_PATH}" ]]; then
    echo "[ERROR] Missing SIF: ${SIF_PATH}" >&2
    echo "[INFO] Build it with: bash ./build_apptainer_frontend.sh" >&2
    exit 1
fi

mkdir -p "${PRELIGHT_WORK_ROOT}" "${PRELIGHT_RESULTS_DIR}" "${TALOS_OUTPUT_DIR}"

bash "${BASE_DIR}/example_preflight_apptainer.sh"

COHORT_VCF="${PRELIGHT_RESULTS_DIR}/cohort_merged_spliceai.vcf.gz"
if [[ ! -f "${COHORT_VCF}" ]]; then
    COHORT_VCF="${PRELIGHT_RESULTS_DIR}/cohort_merged.vcf.gz"
fi

PEDIGREE_PATH="${BASE_DIR}/examples/first_trio/pedigree.ped"

if [[ ! -f "${COHORT_VCF}" ]]; then
    echo "[ERROR] Preflight cohort VCF not found in ${PRELIGHT_RESULTS_DIR}" >&2
    exit 1
fi

cat > "${TALOS_INPUT_TSV}" <<EOF
cohort	path	type	pedigree	config	history	ext_ids	seqr_map	mito
${PRELIGHT_COHORT_NAME}	${COHORT_VCF}	vcf	${PEDIGREE_PATH}	${TALOS_CONFIG_PATH}	${TALOS_HISTORY_PATH}	${TALOS_EXT_IDS_PATH}	${TALOS_SEQR_MAP_PATH}	${TALOS_MITO_PATH}
EOF

export APPTAINER_TMPDIR="${SINGULARITY_TMPDIR:-/tmp}"
export APPTAINER_CACHEDIR="${SINGULARITY_CACHEDIR:-$HOME/.apptainer/cache}"
export NXF_HOME="${NXF_HOME:-${REPO_DIR}/.nextflow-apptainer}"

mkdir -p "${NXF_HOME}"

exec apptainer exec \
    --bind "${REPO_DIR}:${REPO_DIR}" \
    --bind "${PRELIGHT_WORK_ROOT}:${PRELIGHT_WORK_ROOT}" \
    --pwd "${REPO_DIR}" \
    "${SIF_PATH}" \
    nextflow -c nextflow.config run main.nf \
        --input_tsv "${TALOS_INPUT_TSV}" \
        --processed_annotations "${PROCESSED_ANNOTATIONS_DIR}" \
        -output-dir "${TALOS_OUTPUT_DIR}" \
        -resume
