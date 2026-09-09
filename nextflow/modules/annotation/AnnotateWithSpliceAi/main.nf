process AnnotateWithSpliceAi {
    memory 4.GB
    cpus 1

    input:
        tuple val(cohort), path(vcf)
        path spliceai_vcf
        path spliceai_vcf_idx

    output:
        tuple val(cohort), path("${vcf.simpleName}_spliceai.vcf.bgz")

    script:
    """
    set -euo pipefail

    if [[ ! -f "${vcf}.tbi" && ! -f "${vcf}.csi" ]]; then
        bcftools index -t -f "${vcf}"
    fi

    bcftools annotate \
        -a "${spliceai_vcf}" \
        -c INFO/SpliceAI \
        -Oz -o "${vcf.simpleName}_spliceai.vcf.bgz" \
        "${vcf}"

    bcftools index -t -f "${vcf.simpleName}_spliceai.vcf.bgz"
    """
}
