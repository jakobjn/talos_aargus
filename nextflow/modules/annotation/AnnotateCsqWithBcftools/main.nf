process AnnotateCsqWithBcftools {
    memory 1.GB
    cpus 1

    input:
        tuple val(cohort), path(vcf), path(vcf_tbi)
        path gff3
        path reference

    output:
        tuple val(cohort), path("${vcf.simpleName}_csq.vcf.bgz")

    script:
    """
    set -euo pipefail

    bcftools csq --force -f "${reference}" \
        --greedy 1 \
        --local-csq \
        -g ${gff3} \
        --unify-chr-names 'chr,-,chr' \
        -B 20 \
        -Oz -o "${vcf.simpleName}_csq.vcf.bgz" \
        ${vcf}
    """
}
