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

    bcftools annotate \
      -x FORMAT/AF,FORMAT/VAF,FORMAT/VAF1 \
      -Oz \
      --write-index=tbi \
      -o "${sample_id}.vcf.gz" \
      "${vcf}"
    """
}
