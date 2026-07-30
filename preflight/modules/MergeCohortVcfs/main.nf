process MERGE_COHORT_VCFS {
    cpus 2
    memory 8.GB

    input:
    path family_vcfs

    output:
    tuple path('cohort_merged.vcf.gz'), path('cohort_merged.vcf.gz.tbi'), emit: vcf

    script:
    """
    set -euo pipefail

    tmp_merge_dir="\$(mktemp -d)"
    trap 'rm -rf "\${tmp_merge_dir}"' EXIT

    declare -A SEEN_SAMPLES=()
    merge_inputs=()

    for vcf in ${family_vcfs.sort { it.name }.join(' ')}; do
      if [[ ! -f "\${vcf}.tbi" && ! -f "\${vcf}.csi" ]]; then
        bcftools index -t -f "\${vcf}"
      fi

      mapfile -t sample_names < <(bcftools query -l "\${vcf}")
      keep_samples=()
      duplicate_samples=()

      for sample_name in "\${sample_names[@]}"; do
        if [[ -n "\${SEEN_SAMPLES[\${sample_name}]:-}" ]]; then
          duplicate_samples+=("\${sample_name}")
        else
          keep_samples+=("\${sample_name}")
          SEEN_SAMPLES["\${sample_name}"]=1
        fi
      done

      if [[ "\${#keep_samples[@]}" -eq 0 ]]; then
        continue
      fi

      if [[ "\${#duplicate_samples[@]}" -eq 0 ]]; then
        merge_inputs+=("\${vcf}")
        continue
      fi

      filtered_vcf="\${tmp_merge_dir}/\$(basename "\${vcf}")"
      keep_csv="\$(IFS=,; echo "\${keep_samples[*]}")"

      bcftools view \
        --samples "\${keep_csv}" \
        --output-type z \
        --output-file "\${filtered_vcf}" \
        "\${vcf}"
      bcftools index -t -f "\${filtered_vcf}"

      merge_inputs+=("\${filtered_vcf}")
    done

    if [[ "\${#merge_inputs[@]}" -eq 0 ]]; then
      echo "No cohort merge inputs remain after deduplication" >&2
      exit 1
    fi

    if [[ "\${#merge_inputs[@]}" -eq 1 ]]; then
      cp -f "\${merge_inputs[0]}" cohort_merged.vcf.gz
    else
      bcftools merge \
        --missing-to-ref \
        --output-type z \
        --output cohort_merged.vcf.gz \
        "\${merge_inputs[@]}"
    fi

    bcftools index -t -f cohort_merged.vcf.gz
    """
}
