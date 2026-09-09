#!/usr/bin/env bash

set -euo pipefail
umask 002

RUN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_DIR="${REPO_DIR:-$(cd "${RUN_DIR}/.." && pwd -P)}"
CONDA_ENV="${CONDA_ENV:-/faststorage/project/reanalyses_auh/env/talos2_env}"

SAMPLE_MANIFEST="${SAMPLE_MANIFEST:-${RUN_DIR}/preflight_inputs/sample_manifest.tsv}"
PEDIGREE="${PEDIGREE:-${RUN_DIR}/preflight_inputs/pedigree.ped}"
PREFLIGHT_OUTPUT_DIR="${PREFLIGHT_OUTPUT_DIR:-${RUN_DIR}/preflight_outputs}"
PREFLIGHT_WORK_DIR="${PREFLIGHT_WORK_DIR:-${RUN_DIR}/preflight_work}"
PREFLIGHT_LOG_FILE="${PREFLIGHT_LOG_FILE:-${RUN_DIR}/.nextflow.log}"
COMMON_DBSNP_VCF="${COMMON_DBSNP_VCF:-/faststorage/project/reanalyses_auh/resources/20260518_common_resource.vcf.gz}"
SPLICEAI_VCF="${SPLICEAI_VCF:-/faststorage/project/reanalyses_auh/resources/spliceai_scores_KGA_AUH_GRCh_38_Homo_sapiens_converted.vcf.gz}"
COMMON_DBSNP_ENABLED="${COMMON_DBSNP_ENABLED:-false}"
FAMILY_MERGE_ENABLED="${FAMILY_MERGE_ENABLED:-false}"
SPLICEAI_ENABLED="${SPLICEAI_ENABLED:-false}"
TALOS_CONFIG="${TALOS_CONFIG:-${RUN_DIR}/config/config.toml}"
TALOS_INPUT_ENABLED="${TALOS_INPUT_ENABLED:-true}"
TALOS_COHORT="${TALOS_COHORT:-DEPT}"
RESUME="${RESUME:-true}"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --run-dir) RUN_DIR="$2"; shift 2 ;;
        --repo-dir) REPO_DIR="$2"; shift 2 ;;
        --conda-env) CONDA_ENV="$2"; shift 2 ;;
        --sample-manifest) SAMPLE_MANIFEST="$2"; shift 2 ;;
        --pedigree) PEDIGREE="$2"; shift 2 ;;
        --output-dir) PREFLIGHT_OUTPUT_DIR="$2"; shift 2 ;;
        --work-dir) PREFLIGHT_WORK_DIR="$2"; shift 2 ;;
        --log-file) PREFLIGHT_LOG_FILE="$2"; shift 2 ;;
        --common-dbsnp-enabled) COMMON_DBSNP_ENABLED="$2"; shift 2 ;;
        --common-dbsnp-vcf) COMMON_DBSNP_VCF="$2"; shift 2 ;;
        --family-merge-enabled) FAMILY_MERGE_ENABLED="$2"; shift 2 ;;
        --spliceai-enabled) SPLICEAI_ENABLED="$2"; shift 2 ;;
        --spliceai-vcf) SPLICEAI_VCF="$2"; shift 2 ;;
        --talos-input-enabled) TALOS_INPUT_ENABLED="$2"; shift 2 ;;
        --talos-cohort) TALOS_COHORT="$2"; shift 2 ;;
        --talos-config) TALOS_CONFIG="$2"; shift 2 ;;
        --resume) RESUME="$2"; shift 2 ;;
        -h|--help)
            cat <<'EOF'
Usage: bash run_dept_preflight_local.sh [options]

Options:
  --run-dir PATH
  --repo-dir PATH
  --conda-env NAME_OR_PREFIX
  --sample-manifest PATH
  --pedigree PATH
  --output-dir PATH
  --work-dir PATH
  --log-file PATH
  --common-dbsnp-enabled true|false
  --common-dbsnp-vcf PATH
  --family-merge-enabled true|false
  --spliceai-enabled true|false
  --spliceai-vcf PATH
  --talos-input-enabled true|false
  --talos-cohort NAME
  --talos-config PATH
  --resume true|false
EOF
            exit 0
            ;;
        *) echo "[ERROR] Unknown argument: $1" >&2; exit 1 ;;
    esac
done

for path in "${SAMPLE_MANIFEST}" "${PEDIGREE}"; do
    if [[ ! -e "${path}" ]]; then
        echo "[ERROR] Missing required input: ${path}" >&2
        exit 1
    fi
done
if [[ "${COMMON_DBSNP_ENABLED}" == "true" && ! -e "${COMMON_DBSNP_VCF}" ]]; then
    echo "[ERROR] Missing common dbSNP VCF: ${COMMON_DBSNP_VCF}" >&2
    exit 1
fi
if [[ "${SPLICEAI_ENABLED}" == "true" && ! -e "${SPLICEAI_VCF}" ]]; then
    echo "[ERROR] Missing SpliceAI VCF: ${SPLICEAI_VCF}" >&2
    exit 1
fi
if [[ "${TALOS_INPUT_ENABLED}" == "true" && ! -e "${TALOS_CONFIG}" ]]; then
    echo "[ERROR] Missing Talos config: ${TALOS_CONFIG}" >&2
    exit 1
fi

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

export NXF_HOME="${NXF_HOME:-${RUN_DIR}/.nextflow-preflight-local}"
export NXF_DISABLE_CHECK_LATEST=true
mkdir -p "${NXF_HOME}" "${PREFLIGHT_OUTPUT_DIR}" "${PREFLIGHT_WORK_DIR}"
ln -sfn "$(readlink -f "${PEDIGREE}")" "${PREFLIGHT_OUTPUT_DIR}/pedigree.ped"

nextflow_args=(
    -c "${REPO_DIR}/preflight/nextflow.config"
    run "${REPO_DIR}/preflight/main.nf"
    --sample_manifest "${SAMPLE_MANIFEST}"
    --pedigree "${PEDIGREE}"
    --runtime_bin_dir "$(dirname "$(command -v nextflow)")"
    --common_dbsnp_enabled "${COMMON_DBSNP_ENABLED}"
    --common_dbsnp_vcf "${COMMON_DBSNP_VCF}"
    --family_merge_enabled "${FAMILY_MERGE_ENABLED}"
    --spliceai_enabled "${SPLICEAI_ENABLED}"
    --spliceai_vcf "${SPLICEAI_VCF}"
    --talos_input_enabled "${TALOS_INPUT_ENABLED}"
    --talos_cohort "${TALOS_COHORT}"
    --talos_config "${TALOS_CONFIG}"
    -work-dir "${PREFLIGHT_WORK_DIR}"
    -output-dir "${PREFLIGHT_OUTPUT_DIR}"
)

if [[ "${RESUME}" == "true" ]]; then
    nextflow_args+=(-resume)
fi

cd "${RUN_DIR}"
env -u HTTP_PROXY -u HTTPS_PROXY -u ALL_PROXY -u http_proxy -u https_proxy -u all_proxy \
    nextflow -log "${PREFLIGHT_LOG_FILE}" "${nextflow_args[@]}"

stable_vcf="${PREFLIGHT_OUTPUT_DIR}/cohort_merged.vcf.gz"
stable_tbi="${stable_vcf}.tbi"
if [[ -L "${stable_vcf}" ]]; then
    stable_target="$(readlink -f "${stable_vcf}")"
    stable_target_tbi="${stable_target}.tbi"
    if [[ -s "${stable_target_tbi}" ]]; then
        rm -f "${stable_tbi}"
        ln -s "${stable_target_tbi}" "${stable_tbi}"
    fi
fi

if [[ ! -s "${PREFLIGHT_OUTPUT_DIR}/cohort_merged.vcf.gz" ]]; then
    echo "[ERROR] Preflight did not create cohort VCF: ${PREFLIGHT_OUTPUT_DIR}/cohort_merged.vcf.gz" >&2
    exit 1
fi
if [[ ! -s "${PREFLIGHT_OUTPUT_DIR}/cohort_merged.vcf.gz.tbi" ]]; then
    echo "[ERROR] Preflight did not create cohort VCF index: ${PREFLIGHT_OUTPUT_DIR}/cohort_merged.vcf.gz.tbi" >&2
    exit 1
fi
if [[ "${TALOS_INPUT_ENABLED}" == "true" && ! -s "${PREFLIGHT_OUTPUT_DIR}/talos_input.tsv" ]]; then
    echo "[ERROR] Preflight did not create TALOS input: ${PREFLIGHT_OUTPUT_DIR}/talos_input.tsv" >&2
    exit 1
fi
