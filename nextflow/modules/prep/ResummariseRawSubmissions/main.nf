process ResummariseRawSubmissions {
    memory 16.GB
    cpus 4

    input:
        path variant_summary
        path submission_summary
        val timestamp

    output:
        tuple path("clinvarbitration_${timestamp}.vcf.bgz"), path("clinvarbitration_${timestamp}.vcf.bgz.tbi"), emit: "vcf"

    // Generates
    // clinvarbitration_XX.vcf.bgz + index - VCF containing only pathogenic SNV entries, feeds into annotation
    script:
        """
        set -euo pipefail
        export PYTHONPATH="${projectDir}/src:\$PYTHONPATH"

        python3 -m talos.resummarise_clinvar \
            -v "${variant_summary}" \
            -s "${submission_summary}" \
            -o "clinvarbitration_${timestamp}" \
            -b "${params.clinvar_blacklist}"

        bgzip -f "clinvarbitration_${timestamp}.vcf"
        tabix -f -p vcf "clinvarbitration_${timestamp}.vcf.gz"
        mv "clinvarbitration_${timestamp}.vcf.gz" "clinvarbitration_${timestamp}.vcf.bgz"
        mv "clinvarbitration_${timestamp}.vcf.gz.tbi" "clinvarbitration_${timestamp}.vcf.bgz.tbi"

        # remove the byproduct TSV which was read into a HT
        """
}
