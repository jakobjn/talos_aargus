process AnnotateMitoVcf {

    input:
        tuple val(cohort), path(vcf), path(panelapp_data), path(pedigree), path(talos_config), path(mitimpact), path(mitotip), path(napogee)
        path ref_fa
        path gff3
        path clinvar
        path clinvar_tbi

    output:
        tuple val(cohort), path("${cohort}_mito_labelled.vcf.bgz")

    script:
        """
        set -euo pipefail

        bcftools norm \
            -m -any \
            -f "${ref_fa}" \
            -Ou ${vcf} \
            --no-version | \
        bcftools csq \
            --force \
            -f "${ref_fa}" \
            -g "${gff3}" \
            --local-csq \
            -C 2 \
            --threads 4 \
            -B 10 \
            --unify-chr-names 'chr,-,chr' \
            -Oz -o "${cohort}_mito_csq_annotated.vcf.bgz" \
            -

        echtvar anno \
            -e ${napogee} \
            -e ${mitimpact} \
            -e ${mitotip} \
            "${cohort}_mito_csq_annotated.vcf.bgz" \
            "${cohort}_mito_all_annotated.vcf.bgz"

        export PYTHONPATH="${projectDir}/src:\$PYTHONPATH"
        export TALOS_CONFIG=${talos_config}

        python -m talos.reformat_and_label_mito_vcf \\
            --input "${cohort}_mito_all_annotated.vcf.bgz" \\
            --output "${cohort}_mito_labelled.vcf" \\
            --pedigree ${pedigree} \\
            --panelapp ${panelapp_data} \\
            --clinvar ${clinvar}

        bgzip -f "${cohort}_mito_labelled.vcf"
        mv "${cohort}_mito_labelled.vcf.gz" "${cohort}_mito_labelled.vcf.bgz"
        """
}
