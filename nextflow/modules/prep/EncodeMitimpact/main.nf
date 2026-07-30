process EncodeMitimpact {

    input:
        path tsv

    output:
        tuple path("mitimpact.vcf.gz"), path("mitimpact.zip")

    script:
        """
        set -euo pipefail
        export PYTHONPATH="${projectDir}/src:\$PYTHONPATH"

        python -m talos.annotation_scripts.parse_mitimpact \
            --input ${tsv} \
            --output mitimpact.vcf.gz

        echtvar encode mitimpact.zip ${projectDir}/echtvar/mitimpact_config.json mitimpact.vcf.gz
        """
}
