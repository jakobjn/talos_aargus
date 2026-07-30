process EncodeMitotip {

    input:
        path tsv

    output:
        tuple path("mitotip.vcf.gz"), path("mitotip.zip")

    script:
        """
        set -euo pipefail
        export PYTHONPATH="${projectDir}/src:\$PYTHONPATH"

        python -m talos.annotation_scripts.parse_mitotip \
            --input ${tsv} \
            --output mitotip.vcf.gz

        echtvar encode mitotip.zip ${projectDir}/echtvar/mitotip_config.json mitotip.vcf.gz
        """
}
