#!/usr/bin/env bash

set -euo pipefail

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_DIR="$(cd "${BASE_DIR}/.." && pwd -P)"

SIF_PATH="${SIF_PATH:-${REPO_DIR}/apptainer/build/talos-nextflow.sif}"
WORK_ROOT="${WORK_ROOT:-/tmp/preflight_test_run}"
RESULTS_DIR="${RESULTS_DIR:-${WORK_ROOT}/results}"
INPUT_DIR="${WORK_ROOT}/inputs"
RESOURCE_DIR="${WORK_ROOT}/resources"

if [[ ! -f "${SIF_PATH}" ]]; then
    echo "[ERROR] Missing SIF: ${SIF_PATH}" >&2
    echo "[INFO] Build it with: bash ./build_apptainer_frontend.sh" >&2
    exit 1
fi

rm -rf "${WORK_ROOT}"
mkdir -p "${INPUT_DIR}" "${RESOURCE_DIR}" "${RESULTS_DIR}"

cat > "${INPUT_DIR}/PROBAND.vcf" <<'EOF'
##fileformat=VCFv4.2
##contig=<ID=1>
##FORMAT=<ID=GT,Number=1,Type=String,Description="Genotype">
#CHROM	POS	ID	REF	ALT	QUAL	FILTER	INFO	FORMAT	PROBAND
1	1000	.	A	G	.	PASS	.	GT	0/1
1	2000	.	C	T	.	PASS	.	GT	0/1
EOF

cat > "${INPUT_DIR}/FATHER.vcf" <<'EOF'
##fileformat=VCFv4.2
##contig=<ID=1>
##FORMAT=<ID=GT,Number=1,Type=String,Description="Genotype">
#CHROM	POS	ID	REF	ALT	QUAL	FILTER	INFO	FORMAT	FATHER
1	1000	.	A	G	.	PASS	.	GT	0/0
1	2000	.	C	T	.	PASS	.	GT	0/1
EOF

cat > "${INPUT_DIR}/MOTHER.vcf" <<'EOF'
##fileformat=VCFv4.2
##contig=<ID=1>
##FORMAT=<ID=GT,Number=1,Type=String,Description="Genotype">
#CHROM	POS	ID	REF	ALT	QUAL	FILTER	INFO	FORMAT	MOTHER
1	1000	.	A	G	.	PASS	.	GT	0/1
1	2000	.	C	T	.	PASS	.	GT	0/0
EOF

cat > "${RESOURCE_DIR}/common.vcf" <<'EOF'
##fileformat=VCFv4.2
##contig=<ID=1>
#CHROM	POS	ID	REF	ALT	QUAL	FILTER	INFO
1	2000	.	C	T	.	PASS	.
EOF

cat > "${RESOURCE_DIR}/spliceai.vcf" <<'EOF'
##fileformat=VCFv4.2
##contig=<ID=1>
##INFO=<ID=SpliceAI,Number=.,Type=String,Description="Synthetic SpliceAI annotation">
#CHROM	POS	ID	REF	ALT	QUAL	FILTER	INFO
1	1000	.	A	G	.	PASS	SpliceAI=A|GENE1|0.01|0.00|0.00|0.00
EOF

export APPTAINER_TMPDIR="${SINGULARITY_TMPDIR:-/tmp}"
export APPTAINER_CACHEDIR="${SINGULARITY_CACHEDIR:-$HOME/.apptainer/cache}"

apptainer exec \
    --bind "${REPO_DIR}:${REPO_DIR}" \
    --bind "${WORK_ROOT}:${WORK_ROOT}" \
    --pwd "${REPO_DIR}" \
    "${SIF_PATH}" \
    bash -lc "\
      set -euo pipefail; \
      bcftools view -Oz -o '${INPUT_DIR}/PROBAND.vcf.gz' '${INPUT_DIR}/PROBAND.vcf'; \
      bcftools index -t -f '${INPUT_DIR}/PROBAND.vcf.gz'; \
      bcftools view -Oz -o '${INPUT_DIR}/FATHER.vcf.gz' '${INPUT_DIR}/FATHER.vcf'; \
      bcftools index -t -f '${INPUT_DIR}/FATHER.vcf.gz'; \
      bcftools view -Oz -o '${INPUT_DIR}/MOTHER.vcf.gz' '${INPUT_DIR}/MOTHER.vcf'; \
      bcftools index -t -f '${INPUT_DIR}/MOTHER.vcf.gz'; \
      bcftools view -Oz -o '${RESOURCE_DIR}/common.vcf.gz' '${RESOURCE_DIR}/common.vcf'; \
      bcftools index -t -f '${RESOURCE_DIR}/common.vcf.gz'; \
      bcftools view -Oz -o '${RESOURCE_DIR}/spliceai.vcf.gz' '${RESOURCE_DIR}/spliceai.vcf'; \
      bcftools index -t -f '${RESOURCE_DIR}/spliceai.vcf.gz'"

cat > "${INPUT_DIR}/sample_manifest.tsv" <<EOF
sample_id	vcf_path
PROBAND	${INPUT_DIR}/PROBAND.vcf.gz
FATHER	${INPUT_DIR}/FATHER.vcf.gz
MOTHER	${INPUT_DIR}/MOTHER.vcf.gz
EOF

SAMPLE_MANIFEST="${INPUT_DIR}/sample_manifest.tsv" \
PEDIGREE="${BASE_DIR}/examples/first_trio/pedigree.ped" \
OUTPUT_DIR="${RESULTS_DIR}" \
COMMON_DBSNP_ENABLED=true \
COMMON_DBSNP_VCF="${RESOURCE_DIR}/common.vcf.gz" \
SPLICEAI_ENABLED=true \
SPLICEAI_VCF="${RESOURCE_DIR}/spliceai.vcf.gz" \
SIF_PATH="${SIF_PATH}" \
bash "${BASE_DIR}/run_preflight_apptainer.sh"

echo "preflight apptainer example completed"
echo "results: ${RESULTS_DIR}"
