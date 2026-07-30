process ANNOTATE_COHORT_SPLICEAI {
    cpus 1
    memory 4.GB

    input:
    tuple path(cohort_vcf), path(cohort_vcf_idx)
    path spliceai_vcf

    output:
    tuple path('cohort_merged_spliceai.vcf.gz'), path('cohort_merged_spliceai.vcf.gz.tbi'), emit: vcf

    script:
    """
    set -euo pipefail

    if [[ ! -f "${spliceai_vcf}.tbi" && ! -f "${spliceai_vcf}.csi" ]]; then
      bcftools index -t -f "${spliceai_vcf}"
    fi

    bcftools annotate \
      -a "${spliceai_vcf}" \
      -c INFO/SpliceAI \
      -Oz -o cohort_merged_spliceai.vcf.gz \
      "${cohort_vcf}"

    bcftools index -t -f cohort_merged_spliceai.vcf.gz
    """
}
