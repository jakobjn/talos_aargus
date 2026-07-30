process FILTER_COMMON_DBSNP {
    cpus 1
    memory 2.GB

    input:
    tuple val(sample_id), path(vcf), path(vcf_idx)
    path resource_vcf

    output:
    tuple val(sample_id), path("${sample_id}.vcf.gz"), path("${sample_id}.vcf.gz.tbi"), emit: vcfs

    script:
    """
    set -euo pipefail

    tmp_dir="\$(mktemp -d)"
    trap 'rm -rf "\${tmp_dir}"' EXIT

    if [[ ! -f "${resource_vcf}.tbi" && ! -f "${resource_vcf}.csi" ]]; then
      bcftools index -t -f "${resource_vcf}"
    fi

    bcftools isec \
      -C \
      -c none \
      -p "\${tmp_dir}" \
      "${vcf}" \
      "${resource_vcf}"

    if [[ -f "\${tmp_dir}/0000.vcf" ]]; then
      bcftools view -Oz -o "${sample_id}.vcf.gz" "\${tmp_dir}/0000.vcf"
    elif [[ -f "\${tmp_dir}/0000.vcf.gz" ]]; then
      cp -f "\${tmp_dir}/0000.vcf.gz" "${sample_id}.vcf.gz"
    else
      echo "bcftools isec did not produce expected output" >&2
      exit 1
    fi

    bcftools index -t -f "${sample_id}.vcf.gz"
    """
}
