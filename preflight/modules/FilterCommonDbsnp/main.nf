process FILTER_COMMON_DBSNP {
    cpus 1
    memory 2.GB

    input:
    tuple path(vcf), path(vcf_idx)
    path resource_vcf
    path resource_vcf_idx

    output:
    tuple path('cohort_merged.vcf.gz'), path('cohort_merged.vcf.gz.tbi'), emit: vcf

    script:
    """
    set -euo pipefail

    tmp_dir="\$(mktemp -d)"
    trap 'rm -rf "\${tmp_dir}"' EXIT

    bcftools isec \
      -C \
      -c none \
      -p "\${tmp_dir}" \
      "${vcf}" \
      "${resource_vcf}"

    if [[ -f "\${tmp_dir}/0000.vcf" ]]; then
      bcftools view -Oz -o cohort_merged.vcf.gz "\${tmp_dir}/0000.vcf"
    elif [[ -f "\${tmp_dir}/0000.vcf.gz" ]]; then
      cp -f "\${tmp_dir}/0000.vcf.gz" cohort_merged.vcf.gz
    else
      echo "bcftools isec did not produce expected output" >&2
      exit 1
    fi

    bcftools index -t -f cohort_merged.vcf.gz
    """
}
