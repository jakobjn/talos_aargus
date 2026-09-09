#!/usr/bin/env bash

set -euo pipefail

usage() {
    cat >&2 <<'EOF'
Usage:
  bash preflight/create_family_bundle.sh --proband <proband_vcf.gz> [--mother <mother_vcf.gz>] [--father <father_vcf.gz>] [--fast true|false]

Notes:
  - A timestamped bundle is written under trio_runs/, which is ignored by Git.
EOF
    exit 1
}

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_DIR="$(cd "${BASE_DIR}/.." && pwd -P)"
AUH_ROOT="$(cd "${REPO_DIR}/../.." && pwd -P)"
FIX_PERMISSIONS="${REPO_DIR}/scripts/fix_permissions.sh"
SHARED_RESOURCE_DIR="${SHARED_RESOURCE_DIR:-${AUH_ROOT}/resources}"
SHARED_ENV_DIR="${SHARED_ENV_DIR:-${AUH_ROOT}/env/talos2_env}"
RUNTIME_BIN_DIR="${RUNTIME_BIN_DIR:-${SHARED_ENV_DIR}/bin}"
BCFTOOLS_BIN="${BCFTOOLS_BIN:-${RUNTIME_BIN_DIR}/bcftools}"
COMMON_DBSNP_VCF="${COMMON_DBSNP_VCF:-${SHARED_RESOURCE_DIR}/20260518_common_resource.vcf.gz}"
SPLICEAI_VCF="${SPLICEAI_VCF:-${SHARED_RESOURCE_DIR}/spliceai_scores_KGA_AUH_GRCh_38_Homo_sapiens_converted.vcf.gz}"
PROCESSED_ANNOTATIONS_DIR="${PROCESSED_ANNOTATIONS_DIR:-${REPO_DIR}/processed_annotations}"
TALOS_CONFIG_PATH="${TALOS_CONFIG_PATH:-${REPO_DIR}/nextflow/inputs/config.toml}"
SIF_PATH="${SIF_PATH:-${REPO_DIR}/apptainer/build/talos-nextflow.sif}"
OUTPUT_ROOT="${OUTPUT_ROOT:-${REPO_DIR}/trio_runs}"

mkdir -p "${OUTPUT_ROOT}"

PROBAND_VCF=''
MOTHER_VCF=''
FATHER_VCF=''
FAST_MODE='false'

while [[ $# -gt 0 ]]; do
    case "$1" in
        --proband)
            [[ $# -ge 2 ]] || usage
            PROBAND_VCF="$2"
            shift 2
            ;;
        --mother)
            [[ $# -ge 2 ]] || usage
            MOTHER_VCF="$2"
            shift 2
            ;;
        --father)
            [[ $# -ge 2 ]] || usage
            FATHER_VCF="$2"
            shift 2
            ;;
        --fast)
            [[ $# -ge 2 ]] || usage
            FAST_MODE="$2"
            shift 2
            ;;
        *)
            echo "[ERROR] Unknown argument: $1" >&2
            usage
            ;;
    esac
done

[[ -n "${PROBAND_VCF}" ]] || {
    echo "[ERROR] --proband is required" >&2
    usage
}

if [[ "${FAST_MODE}" != "true" && "${FAST_MODE}" != "false" ]]; then
    echo "[ERROR] --fast must be either true or false" >&2
    usage
fi

for path_var in BCFTOOLS_BIN TALOS_CONFIG_PATH; do
    value="${!path_var}"
    if [[ ! -e "${value}" ]]; then
        echo "[ERROR] Missing required path for ${path_var}: ${value}" >&2
        exit 1
    fi
done

if [[ -n "${COMMON_DBSNP_VCF}" && ! -e "${COMMON_DBSNP_VCF}" ]]; then
    echo "[ERROR] COMMON_DBSNP_VCF was set but does not exist: ${COMMON_DBSNP_VCF}" >&2
    exit 1
fi

if [[ -n "${SPLICEAI_VCF}" && ! -e "${SPLICEAI_VCF}" ]]; then
    echo "[ERROR] SPLICEAI_VCF was set but does not exist: ${SPLICEAI_VCF}" >&2
    exit 1
fi

if [[ -n "${COMMON_DBSNP_VCF}" ]]; then
    COMMON_DBSNP_ENABLED='true'
    COMMON_DBSNP_CONFIG_VALUE="'${COMMON_DBSNP_VCF}'"
else
    COMMON_DBSNP_ENABLED='false'
    COMMON_DBSNP_CONFIG_VALUE='null'
fi

if [[ -n "${SPLICEAI_VCF}" ]]; then
    SPLICEAI_ENABLED='true'
    SPLICEAI_CONFIG_VALUE="'${SPLICEAI_VCF}'"
else
    SPLICEAI_ENABLED='false'
    SPLICEAI_CONFIG_VALUE='null'
fi

sample_name_from_vcf() {
    local vcf="$1"
    "${BCFTOOLS_BIN}" query -l "${vcf}"
}

prepare_fast_vcf() {
    local source_vcf="$1"
    local target_vcf="$2"
    local tmp_vcf=''
    tmp_vcf="$(mktemp "${target_vcf}.XXXXXX.raw.vcf")"

    "${BCFTOOLS_BIN}" view -h "${source_vcf}" > "${tmp_vcf}"
    "${BCFTOOLS_BIN}" view -H "${source_vcf}" | sed -n '1p' >> "${tmp_vcf}"
    "${BCFTOOLS_BIN}" view -Oz -o "${target_vcf}" "${tmp_vcf}"

    "${BCFTOOLS_BIN}" index -t -f "${target_vcf}"
    rm -f "${tmp_vcf}"
}

resolve_abs_path() {
    local path="$1"
    if [[ -z "${path}" ]]; then
        printf ''
        return 0
    fi
    realpath "${path}"
}

PROBAND_VCF="$(resolve_abs_path "${PROBAND_VCF}")"
MOTHER_VCF="$(resolve_abs_path "${MOTHER_VCF}")"
FATHER_VCF="$(resolve_abs_path "${FATHER_VCF}")"

if [[ ! -f "${PROBAND_VCF}" ]]; then
    echo "[ERROR] Proband VCF not found: ${PROBAND_VCF}" >&2
    exit 1
fi

if [[ -n "${MOTHER_VCF}" && ! -f "${MOTHER_VCF}" ]]; then
    echo "[ERROR] Mother VCF not found: ${MOTHER_VCF}" >&2
    exit 1
fi

if [[ -n "${FATHER_VCF}" && ! -f "${FATHER_VCF}" ]]; then
    echo "[ERROR] Father VCF not found: ${FATHER_VCF}" >&2
    exit 1
fi

PROBAND_SAMPLE="$(sample_name_from_vcf "${PROBAND_VCF}" | tr -d '\n')"
MOTHER_SAMPLE=''
FATHER_SAMPLE=''

if [[ -n "${MOTHER_VCF}" ]]; then
    MOTHER_SAMPLE="$(sample_name_from_vcf "${MOTHER_VCF}" | tr -d '\n')"
fi

if [[ -n "${FATHER_VCF}" ]]; then
    FATHER_SAMPLE="$(sample_name_from_vcf "${FATHER_VCF}" | tr -d '\n')"
fi

TIMESTAMP="$(date '+%Y%m%d_%H%M%S')"
SAFE_PROBAND="$(printf '%s' "${PROBAND_SAMPLE}" | tr '/[:space:]' '__')"
BUNDLE_DIR="${OUTPUT_ROOT}/${TIMESTAMP}_${SAFE_PROBAND}"
mkdir -p "${BUNDLE_DIR}"

COHORT_NAME="${TIMESTAMP}_${SAFE_PROBAND}"
FAST_VCF_DIR="${BUNDLE_DIR}/source_vcfs"
mkdir -p "${FAST_VCF_DIR}"

manifest_vcf_for() {
    local role="$1"
    local source_vcf="$2"
    local sample_name="$3"
    if [[ "${FAST_MODE}" != "true" ]]; then
        printf '%s' "${source_vcf}"
        return 0
    fi
    local safe_name
    safe_name="$(printf '%s' "${sample_name}" | tr '/[:space:]' '__')"
    local target_vcf="${FAST_VCF_DIR}/${role}_${safe_name}.vcf.gz"
    prepare_fast_vcf "${source_vcf}" "${target_vcf}"
    printf '%s' "${target_vcf}"
}

cat > "${BUNDLE_DIR}/sample_manifest.tsv" <<EOF
sample_id	vcf_path
EOF

PROBAND_MANIFEST_VCF="$(manifest_vcf_for PROBAND "${PROBAND_VCF}" "${PROBAND_SAMPLE}")"
printf '%s\t%s\n' "${PROBAND_SAMPLE}" "${PROBAND_MANIFEST_VCF}" >> "${BUNDLE_DIR}/sample_manifest.tsv"

if [[ -n "${MOTHER_SAMPLE}" ]]; then
    MOTHER_MANIFEST_VCF="$(manifest_vcf_for MOTHER "${MOTHER_VCF}" "${MOTHER_SAMPLE}")"
    printf '%s\t%s\n' "${MOTHER_SAMPLE}" "${MOTHER_MANIFEST_VCF}" >> "${BUNDLE_DIR}/sample_manifest.tsv"
fi

if [[ -n "${FATHER_SAMPLE}" ]]; then
    FATHER_MANIFEST_VCF="$(manifest_vcf_for FATHER "${FATHER_VCF}" "${FATHER_SAMPLE}")"
    printf '%s\t%s\n' "${FATHER_SAMPLE}" "${FATHER_MANIFEST_VCF}" >> "${BUNDLE_DIR}/sample_manifest.tsv"
fi

FATHER_ID="${FATHER_SAMPLE:-0}"
MOTHER_ID="${MOTHER_SAMPLE:-0}"

cat > "${BUNDLE_DIR}/pedigree.ped" <<EOF
${COHORT_NAME}	${PROBAND_SAMPLE}	${FATHER_ID}	${MOTHER_ID}	1	2
EOF

if [[ -n "${FATHER_SAMPLE}" ]]; then
    printf '%s\t%s\t0\t0\t1\t1\n' "${COHORT_NAME}" "${FATHER_SAMPLE}" >> "${BUNDLE_DIR}/pedigree.ped"
fi

if [[ -n "${MOTHER_SAMPLE}" ]]; then
    printf '%s\t%s\t0\t0\t2\t1\n' "${COHORT_NAME}" "${MOTHER_SAMPLE}" >> "${BUNDLE_DIR}/pedigree.ped"
fi

cat > "${BUNDLE_DIR}/preflight.local.config" <<EOF
params {
    runtime_bin_dir = '${RUNTIME_BIN_DIR}'

    publish_family_vcfs = false
    flush_published_family_vcfs = false

    common_dbsnp_enabled = ${COMMON_DBSNP_ENABLED}
    common_dbsnp_vcf = ${COMMON_DBSNP_CONFIG_VALUE}

    spliceai_enabled = ${SPLICEAI_ENABLED}
    spliceai_vcf = ${SPLICEAI_CONFIG_VALUE}
}
EOF

cat > "${BUNDLE_DIR}/run_full_slurm.sh" <<EOF
#!/usr/bin/env bash
#SBATCH --job-name=talos_bundle
#SBATCH --output=${BUNDLE_DIR}/slurm_%j.out
#SBATCH --error=${BUNDLE_DIR}/slurm_%j.err
#SBATCH --chdir=${BUNDLE_DIR}
#SBATCH --time=08:00:00
#SBATCH --cpus-per-task=4
#SBATCH --mem=16G

set -euo pipefail

BASE_DIR="${BUNDLE_DIR}"
REPO_DIR="${REPO_DIR}"
FIX_PERMISSIONS="${FIX_PERMISSIONS}"

SIF_PATH="\${SIF_PATH:-${SIF_PATH}}"
PREFLIGHT_CONFIG="\${PREFLIGHT_CONFIG:-\${BASE_DIR}/preflight.local.config}"
SAMPLE_MANIFEST="\${SAMPLE_MANIFEST:-\${BASE_DIR}/sample_manifest.tsv}"
PEDIGREE="\${PEDIGREE:-\${BASE_DIR}/pedigree.ped}"
PREFLIGHT_OUTPUT_DIR="\${PREFLIGHT_OUTPUT_DIR:-\${BASE_DIR}/preflight_results}"
TALOS_OUTPUT_DIR="\${TALOS_OUTPUT_DIR:-\${BASE_DIR}/talos_outputs}"
TALOS_INPUT_TSV="\${TALOS_INPUT_TSV:-\${BASE_DIR}/talos_input.tsv}"
COHORT_NAME="\${COHORT_NAME:-${COHORT_NAME}}"
PROCESSED_ANNOTATIONS_DIR="\${PROCESSED_ANNOTATIONS_DIR:-${PROCESSED_ANNOTATIONS_DIR}}"
TALOS_CONFIG_PATH="\${TALOS_CONFIG_PATH:-${TALOS_CONFIG_PATH}}"
TALOS_HISTORY_PATH="\${TALOS_HISTORY_PATH:-\${REPO_DIR}/nextflow/assets/NO_HISTORY}"
TALOS_EXT_IDS_PATH="\${TALOS_EXT_IDS_PATH:-\${REPO_DIR}/nextflow/assets/NO_FILE}"
TALOS_SEQR_MAP_PATH="\${TALOS_SEQR_MAP_PATH:-\${REPO_DIR}/nextflow/assets/NO_SEQR_FILE}"
TALOS_MITO_PATH="\${TALOS_MITO_PATH:-\${REPO_DIR}/nextflow/assets/NO_MITO}"
NXF_HOME="\${NXF_HOME:-\${REPO_DIR}/.nextflow-apptainer}"

mkdir -p "\${PREFLIGHT_OUTPUT_DIR}" "\${TALOS_OUTPUT_DIR}" "\${NXF_HOME}"

PREFLIGHT_CONFIG="\${PREFLIGHT_CONFIG}" \\
SAMPLE_MANIFEST="\${SAMPLE_MANIFEST}" \\
PEDIGREE="\${PEDIGREE}" \\
OUTPUT_DIR="\${PREFLIGHT_OUTPUT_DIR}" \\
SIF_PATH="\${SIF_PATH}" \\
bash "\${REPO_DIR}/preflight/run_preflight_apptainer.sh"

COHORT_VCF="\${PREFLIGHT_OUTPUT_DIR}/cohort_merged.vcf.gz"
if [[ ! -f "\${COHORT_VCF}" ]]; then
    COHORT_VCF="\${PREFLIGHT_OUTPUT_DIR}/cohort_merged_spliceai.vcf.gz"
fi

if [[ ! -f "\${COHORT_VCF}" ]]; then
    echo "[ERROR] Preflight cohort VCF not found in \${PREFLIGHT_OUTPUT_DIR}" >&2
    exit 1
fi

cat > "\${TALOS_INPUT_TSV}" <<EOI
cohort	path	type	pedigree	config	history	ext_ids	seqr_map	mito
\${COHORT_NAME}	\${COHORT_VCF}	vcf	\${PEDIGREE}	\${TALOS_CONFIG_PATH}	\${TALOS_HISTORY_PATH}	\${TALOS_EXT_IDS_PATH}	\${TALOS_SEQR_MAP_PATH}	\${TALOS_MITO_PATH}
EOI

export APPTAINER_TMPDIR="\${SINGULARITY_TMPDIR:-/tmp}"
export APPTAINER_CACHEDIR="\${SINGULARITY_CACHEDIR:-\$HOME/.apptainer/cache}"

apptainer exec \\
    --bind "\${REPO_DIR}:\${REPO_DIR}" \\
    --bind "\${BASE_DIR}:\${BASE_DIR}" \\
    --pwd "\${REPO_DIR}" \\
    "\${SIF_PATH}" \\
    nextflow -c nextflow.config run main.nf \\
        --input_tsv "\${TALOS_INPUT_TSV}" \\
        --processed_annotations "\${PROCESSED_ANNOTATIONS_DIR}" \\
        -output-dir "\${TALOS_OUTPUT_DIR}" \\
        -resume

if [[ -x "\${FIX_PERMISSIONS}" ]]; then
    bash "\${FIX_PERMISSIONS}" "\${BASE_DIR}" "\${PREFLIGHT_OUTPUT_DIR}" "\${TALOS_OUTPUT_DIR}"
fi
EOF

chmod +x "${BUNDLE_DIR}/run_full_slurm.sh"

echo "[INFO] Created bundle: ${BUNDLE_DIR}"
echo "[INFO] Fast mode: ${FAST_MODE}"
echo "[INFO] Run with: bash ${BUNDLE_DIR}/run_full_slurm.sh"
echo "[INFO] Or submit with: sbatch ${BUNDLE_DIR}/run_full_slurm.sh"
