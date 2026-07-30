process RunHailFiltering {

    input:
        tuple val(cohort), path(vcfs), path(panelapp_data), path(check_file), path(pedigree), path(talos_config)
        path clinvar_all
        path clinvar_all_tbi
        path clinvar_pm5
        path gene_bed
        path mane

    output:
        tuple val(cohort), path("${cohort}_small_variants_labelled.vcf.bgz"), path("${cohort}_small_variants_labelled.vcf.bgz.tbi")

    script:
        def vcf_string = (vcfs.collect().size() > 1) ? vcfs.sort{ it.name } : vcfs
        """
        set -euo pipefail

        export PYTHONPATH="${projectDir}/src:\$PYTHONPATH"
        export TALOS_CONFIG=${talos_config}

        python -m talos.native_run_filtering \
            --input ${vcf_string} \
            --panelapp ${panelapp_data} \
            --pedigree ${pedigree} \
            --output ${cohort}_small_variants_labelled.vcf \
            --clinvar ${clinvar_all} \
            --pm5 ${clinvar_pm5} \
            --gene_bed ${gene_bed} \
            --mane ${mane}
        bgzip -f "${cohort}_small_variants_labelled.vcf"
        mv "${cohort}_small_variants_labelled.vcf.gz" "${cohort}_small_variants_labelled.vcf.bgz"
        tabix "${cohort}_small_variants_labelled.vcf.bgz"
        """
}
