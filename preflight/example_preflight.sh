#!/usr/bin/env bash

set -euo pipefail

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_DIR="$(cd "${BASE_DIR}/.." && pwd -P)"
AUH_ROOT="$(cd "${REPO_DIR}/../.." && pwd -P)"

RUNTIME_BIN_DIR="${RUNTIME_BIN_DIR:-${AUH_ROOT}/env/talos2_env/bin}"
NEXTFLOW_BIN="${NEXTFLOW_BIN:-${RUNTIME_BIN_DIR}/nextflow}"
BCFTOOLS_BIN="${BCFTOOLS_BIN:-${RUNTIME_BIN_DIR}/bcftools}"
WORK_ROOT="${WORK_ROOT:-/tmp/preflight_test_run}"
RESULTS_DIR="${RESULTS_DIR:-${WORK_ROOT}/results}"
INPUT_DIR="${WORK_ROOT}/inputs"
RESOURCE_DIR="${WORK_ROOT}/resources"

for exe in "${NEXTFLOW_BIN}" "${BCFTOOLS_BIN}"; do
    if [[ ! -x "${exe}" ]]; then
        echo "Required executable not found: ${exe}" >&2
        exit 1
    fi
done

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

"${BCFTOOLS_BIN}" view -Oz -o "${INPUT_DIR}/PROBAND.vcf.gz" "${INPUT_DIR}/PROBAND.vcf"
"${BCFTOOLS_BIN}" index -t -f "${INPUT_DIR}/PROBAND.vcf.gz"
"${BCFTOOLS_BIN}" view -Oz -o "${INPUT_DIR}/FATHER.vcf.gz" "${INPUT_DIR}/FATHER.vcf"
"${BCFTOOLS_BIN}" index -t -f "${INPUT_DIR}/FATHER.vcf.gz"
"${BCFTOOLS_BIN}" view -Oz -o "${INPUT_DIR}/MOTHER.vcf.gz" "${INPUT_DIR}/MOTHER.vcf"
"${BCFTOOLS_BIN}" index -t -f "${INPUT_DIR}/MOTHER.vcf.gz"
"${BCFTOOLS_BIN}" view -Oz -o "${RESOURCE_DIR}/common.vcf.gz" "${RESOURCE_DIR}/common.vcf"
"${BCFTOOLS_BIN}" index -t -f "${RESOURCE_DIR}/common.vcf.gz"
"${BCFTOOLS_BIN}" view -Oz -o "${RESOURCE_DIR}/spliceai.vcf.gz" "${RESOURCE_DIR}/spliceai.vcf"
"${BCFTOOLS_BIN}" index -t -f "${RESOURCE_DIR}/spliceai.vcf.gz"

cat > "${INPUT_DIR}/sample_manifest.tsv" <<EOF
sample_id	vcf_path
PROBAND	${INPUT_DIR}/PROBAND.vcf.gz
FATHER	${INPUT_DIR}/FATHER.vcf.gz
MOTHER	${INPUT_DIR}/MOTHER.vcf.gz
EOF

env -u HTTP_PROXY -u HTTPS_PROXY -u ALL_PROXY -u http_proxy -u https_proxy -u all_proxy \
    NXF_DISABLE_CHECK_LATEST=true \
    "${NEXTFLOW_BIN}" \
    -c "${BASE_DIR}/nextflow.config" \
    -c "${BASE_DIR}/local.config" \
    run "${BASE_DIR}/main.nf" \
    --sample_manifest "${INPUT_DIR}/sample_manifest.tsv" \
    --pedigree "${BASE_DIR}/examples/first_trio/pedigree.ped" \
    --runtime_bin_dir "${RUNTIME_BIN_DIR}" \
    --common_dbsnp_enabled true \
    --common_dbsnp_vcf "${RESOURCE_DIR}/common.vcf.gz" \
    --spliceai_enabled true \
    --spliceai_vcf "${RESOURCE_DIR}/spliceai.vcf.gz" \
    -output-dir "${RESULTS_DIR}"

echo "preflight example completed"
echo "results: ${RESULTS_DIR}"
