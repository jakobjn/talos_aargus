#!/usr/bin/env bash

set -euo pipefail

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_DIR="$(cd "${BASE_DIR}/.." && pwd -P)"

SIF_PATH="${SIF_PATH:-${REPO_DIR}/apptainer/build/talos-nextflow.sif}"
OUTPUT_DIR="${OUTPUT_DIR:-${BASE_DIR}/results}"
SAMPLE_MANIFEST="${SAMPLE_MANIFEST:-}"
PEDIGREE="${PEDIGREE:-}"
PREFLIGHT_CONFIG="${PREFLIGHT_CONFIG:-}"
RUNTIME_BIN_DIR="${RUNTIME_BIN_DIR:-${REPO_DIR}/preflight/runtime/talos2_env/bin}"
COMMON_DBSNP_ENABLED="${COMMON_DBSNP_ENABLED:-false}"
COMMON_DBSNP_VCF="${COMMON_DBSNP_VCF:-}"
SPLICEAI_ENABLED="${SPLICEAI_ENABLED:-false}"
SPLICEAI_VCF="${SPLICEAI_VCF:-}"
PUBLISH_FAMILY_VCFS="${PUBLISH_FAMILY_VCFS:-false}"
FLUSH_PUBLISHED_FAMILY_VCFS="${FLUSH_PUBLISHED_FAMILY_VCFS:-false}"
NXF_HOME="${NXF_HOME:-${REPO_DIR}/.nextflow-apptainer}"

if [[ ! -f "${SIF_PATH}" ]]; then
    echo "[ERROR] Missing SIF: ${SIF_PATH}" >&2
    echo "[INFO] Build it with: bash ./build_apptainer_frontend.sh" >&2
    exit 1
fi

if [[ -z "${SAMPLE_MANIFEST}" || -z "${PEDIGREE}" ]]; then
    echo "[ERROR] SAMPLE_MANIFEST and PEDIGREE must be set" >&2
    exit 1
fi

if [[ ! -f "${SAMPLE_MANIFEST}" ]]; then
    echo "[ERROR] Sample manifest not found: ${SAMPLE_MANIFEST}" >&2
    exit 1
fi

if [[ ! -f "${PEDIGREE}" ]]; then
    echo "[ERROR] Pedigree not found: ${PEDIGREE}" >&2
    exit 1
fi

if [[ "${COMMON_DBSNP_ENABLED}" == "true" && -z "${COMMON_DBSNP_VCF}" ]]; then
    echo "[ERROR] COMMON_DBSNP_VCF must be set when COMMON_DBSNP_ENABLED=true" >&2
    exit 1
fi

if [[ "${SPLICEAI_ENABLED}" == "true" && -z "${SPLICEAI_VCF}" ]]; then
    echo "[ERROR] SPLICEAI_VCF must be set when SPLICEAI_ENABLED=true" >&2
    exit 1
fi

mkdir -p "${OUTPUT_DIR}" "${NXF_HOME}"

export APPTAINER_TMPDIR="${SINGULARITY_TMPDIR:-/tmp}"
export APPTAINER_CACHEDIR="${SINGULARITY_CACHEDIR:-$HOME/.apptainer/cache}"

declare -a BIND_DIRS

add_bind_dir() {
    local path="$1"
    [[ -z "${path}" ]] && return 0
    local dir
    if [[ -d "${path}" ]]; then
        dir="$(cd "${path}" && pwd -P)"
    else
        dir="$(cd "$(dirname "${path}")" && pwd -P)"
    fi
    local existing
    for existing in "${BIND_DIRS[@]:-}"; do
        if [[ "${existing}" == "${dir}" ]]; then
            return 0
        fi
    done
    BIND_DIRS+=("${dir}")
}

add_bind_dir "${REPO_DIR}"
add_bind_dir "${OUTPUT_DIR}"
add_bind_dir "${SAMPLE_MANIFEST}"
add_bind_dir "${PEDIGREE}"
[[ -n "${COMMON_DBSNP_VCF}" ]] && add_bind_dir "${COMMON_DBSNP_VCF}"
[[ -n "${SPLICEAI_VCF}" ]] && add_bind_dir "${SPLICEAI_VCF}"

declare -a BIND_ARGS
for bind_dir in "${BIND_DIRS[@]}"; do
    BIND_ARGS+=(--bind "${bind_dir}:${bind_dir}")
done

declare -a NF_ARGS
NF_ARGS=(-c preflight/nextflow.config)
if [[ -n "${PREFLIGHT_CONFIG}" ]]; then
    if [[ ! -f "${PREFLIGHT_CONFIG}" ]]; then
        echo "[ERROR] PREFLIGHT_CONFIG not found: ${PREFLIGHT_CONFIG}" >&2
        exit 1
    fi
    add_bind_dir "${PREFLIGHT_CONFIG}"
    NF_ARGS+=(-c "${PREFLIGHT_CONFIG}")
fi

NF_ARGS+=(
    run preflight/main.nf
    --sample_manifest "${SAMPLE_MANIFEST}"
    --pedigree "${PEDIGREE}"
    --runtime_bin_dir "${RUNTIME_BIN_DIR}"
    --publish_family_vcfs "${PUBLISH_FAMILY_VCFS}"
    --flush_published_family_vcfs "${FLUSH_PUBLISHED_FAMILY_VCFS}"
    --common_dbsnp_enabled "${COMMON_DBSNP_ENABLED}"
    --spliceai_enabled "${SPLICEAI_ENABLED}"
    -output-dir "${OUTPUT_DIR}"
)

if [[ -n "${COMMON_DBSNP_VCF}" ]]; then
    NF_ARGS+=(--common_dbsnp_vcf "${COMMON_DBSNP_VCF}")
fi

if [[ -n "${SPLICEAI_VCF}" ]]; then
    NF_ARGS+=(--spliceai_vcf "${SPLICEAI_VCF}")
fi

exec apptainer exec \
    "${BIND_ARGS[@]}" \
    --pwd "${REPO_DIR}" \
    "${SIF_PATH}" \
    nextflow "${NF_ARGS[@]}"
