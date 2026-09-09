#!/usr/bin/env bash

set -euo pipefail
umask 002

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
RUN_DIR="${RUN_DIR:-${SCRIPT_DIR}}"
REPO_DIR="${REPO_DIR:-$(cd "${SCRIPT_DIR}/.." && pwd -P)}"
CONDA_ENV="${CONDA_ENV:-/faststorage/project/reanalyses_auh/env/talos2_env}"

TALOS_INPUT_TSV="${TALOS_INPUT_TSV:-${RUN_DIR}/talos_input.tsv}"
TALOS_OUTPUT_DIR="${TALOS_OUTPUT_DIR:-${RUN_DIR}/cohort_outputs}"
PROCESSED_ANNOTATIONS_DIR="${PROCESSED_ANNOTATIONS_DIR:-${RUN_DIR}/processed_annotations}"
TALOS_NEXTFLOW_CONFIG="${TALOS_NEXTFLOW_CONFIG:-${RUN_DIR}/config/dept_local.config}"
SPLICEAI_ENABLED="${SPLICEAI_ENABLED:-true}"
SPLICEAI_VCF="${SPLICEAI_VCF:-/faststorage/project/reanalyses_auh/resources/spliceai_scores_KGA_AUH_GRCh_38_Homo_sapiens_converted.vcf.gz}"
RESUME="${RESUME:-true}"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --run-dir) RUN_DIR="$2"; shift 2 ;;
        --repo-dir) REPO_DIR="$2"; shift 2 ;;
        --conda-env) CONDA_ENV="$2"; shift 2 ;;
        --input-tsv) TALOS_INPUT_TSV="$2"; shift 2 ;;
        --output-dir) TALOS_OUTPUT_DIR="$2"; shift 2 ;;
        --processed-annotations) PROCESSED_ANNOTATIONS_DIR="$2"; shift 2 ;;
        --nextflow-config) TALOS_NEXTFLOW_CONFIG="$2"; shift 2 ;;
        --spliceai-enabled) SPLICEAI_ENABLED="$2"; shift 2 ;;
        --spliceai-vcf) SPLICEAI_VCF="$2"; shift 2 ;;
        --resume) RESUME="$2"; shift 2 ;;
        -h|--help)
            cat <<'EOF'
Usage: bash run_dept_talos_local.sh [options]

Options:
  --run-dir PATH
  --repo-dir PATH
  --conda-env NAME_OR_PREFIX
  --input-tsv PATH
  --output-dir PATH
  --processed-annotations PATH
  --nextflow-config PATH
  --spliceai-enabled true|false
  --spliceai-vcf PATH
  --resume true|false
EOF
            exit 0
            ;;
        *) echo "[ERROR] Unknown argument: $1" >&2; exit 1 ;;
    esac
done

if [[ "${SPLICEAI_ENABLED}" == "true" ]]; then
    if [[ -z "${SPLICEAI_VCF}" ]]; then
        echo "[ERROR] --spliceai-vcf is required when --spliceai-enabled true" >&2
        exit 1
    fi
    if [[ ! -e "${SPLICEAI_VCF}" ]]; then
        echo "[ERROR] Missing SpliceAI VCF: ${SPLICEAI_VCF}" >&2
        exit 1
    fi
fi

mkdir -p "${TALOS_OUTPUT_DIR}" "${RUN_DIR}/work" "${RUN_DIR}/logs"

if [[ -d "${CONDA_ENV}" && -x "${CONDA_ENV}/bin/nextflow" ]]; then
    export PATH="${CONDA_ENV}/bin:${PATH}"
else
    if [[ -n "${CONDA_EXE:-}" ]]; then
        CONDA_BIN="${CONDA_EXE}"
    elif command -v conda >/dev/null 2>&1; then
        CONDA_BIN="$(command -v conda)"
    else
        echo "[ERROR] Could not find conda on PATH." >&2
        exit 1
    fi

    CONDA_BASE="$("${CONDA_BIN}" info --base)"
    CONDA_SH="${CONDA_BASE}/etc/profile.d/conda.sh"
    if [[ ! -f "${CONDA_SH}" ]]; then
        echo "[ERROR] Conda initialization script not found: ${CONDA_SH}" >&2
        exit 1
    fi

    source "${CONDA_SH}"
    conda activate "${CONDA_ENV}"
fi

export PYTHONPATH="${REPO_DIR}/src${PYTHONPATH:+:${PYTHONPATH}}"
export NXF_HOME="${NXF_HOME:-${RUN_DIR}/.nextflow-local}"
export NXF_PLUGINS_DIR="${NXF_PLUGINS_DIR:-${NXF_HOME}/plugins}"
mkdir -p "${NXF_HOME}" "${NXF_PLUGINS_DIR}"

cd "${RUN_DIR}"

nextflow_args=(
    -c "${REPO_DIR}/nextflow.config"
    -c "${TALOS_NEXTFLOW_CONFIG}"
    run "${REPO_DIR}/main.nf"
    --input_tsv "${TALOS_INPUT_TSV}"
    --processed_annotations "${PROCESSED_ANNOTATIONS_DIR}"
    --spliceai_enabled "${SPLICEAI_ENABLED}"
    -output-dir "${TALOS_OUTPUT_DIR}"
)

if [[ -n "${SPLICEAI_VCF}" ]]; then
    nextflow_args+=(--spliceai_vcf "${SPLICEAI_VCF}")
fi

if [[ "${RESUME}" == "true" ]]; then
    nextflow_args+=(-resume)
fi

exec nextflow "${nextflow_args[@]}"
