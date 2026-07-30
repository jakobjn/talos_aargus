process PREPARE_SINGLE_SAMPLE_VCF {
    cpus 1
    memory 2.GB

    input:
    tuple val(sample_id), path(vcf)

    output:
    tuple val(sample_id), path("${sample_id}.vcf.gz"), path("${sample_id}.vcf.gz.tbi"), emit: vcfs

    script:
    """
    set -euo pipefail

    bcftools view -Ou "${vcf}" \
      | bcftools annotate -x FORMAT/AF,FORMAT/VAF,FORMAT/VAF1 \
      | bcftools view -Oz -o "${sample_id}.vcf.gz"

    bcftools index -t -f "${sample_id}.vcf.gz"
    """
}

