process StartupChecks {

    input:
        tuple val(cohort), path(vcfs), path(pedigree), path(talos_config), path(history), path(ext), path(seqr), path(mito)
        path clinvar

    output:
        tuple val(cohort), path("${cohort}_checked")

    script:
        def vcf_string = (vcfs.collect().size() > 1) ? vcfs.sort{ it.name } : vcfs

        """
        set -euo pipefail

        export PYTHONPATH="${projectDir}/src:\$PYTHONPATH"
        export TALOS_CONFIG=${talos_config}

        python -m talos.startup_checks \\
            --vcf ${vcf_string} \\
            --pedigree ${pedigree} \\
            --clinvar ${clinvar}

        echo "success" > "${cohort}_checked"
        """
}
