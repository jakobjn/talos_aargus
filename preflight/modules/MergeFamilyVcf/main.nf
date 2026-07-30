process MERGE_FAMILY_VCF {
    cpus 1
    memory 2.GB

    input:
    tuple val(family_id), val(proband_id), val(output_name), path(input_vcfs)

    output:
    tuple val(family_id), path("${output_name}.vcf.gz"), path("${output_name}.vcf.gz.tbi"), emit: family_vcfs

    script:
    def sortedInputs = input_vcfs.sort { it.name }
    """
    set -euo pipefail

    for staged_vcf in ${sortedInputs.join(' ')}; do
      if [[ ! -f "\${staged_vcf}.tbi" && ! -f "\${staged_vcf}.csi" ]]; then
        bcftools index -t -f "\${staged_vcf}"
      fi
    done

    if [[ "${sortedInputs.size()}" -eq 1 ]]; then
      cp -f "${sortedInputs[0]}" "${output_name}.vcf.gz"
      if [[ -f "${sortedInputs[0]}.tbi" ]]; then
        cp -f "${sortedInputs[0]}.tbi" "${output_name}.vcf.gz.tbi"
      else
        bcftools index -t -f "${output_name}.vcf.gz"
      fi
    else
      bcftools merge \
        --missing-to-ref \
        --output-type z \
        --output "${output_name}.vcf.gz" \
        ${sortedInputs.join(' ')}

      bcftools index -t -f "${output_name}.vcf.gz"
    fi
    """
}
