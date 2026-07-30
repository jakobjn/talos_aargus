process MakeClinvarbitrationPm5 {

    input:
        path annotated_snv
        val timestamp

    output:
        path "clinvarbitration_${timestamp}.pm5.tsv"

    script:
        """
        set -euo pipefail
        export PYTHONPATH="${projectDir}/src:\$PYTHONPATH"

        python3 -m talos.clinvar_by_codon \
            -i "${annotated_snv}" \
            -o "clinvarbitration_${timestamp}.pm5"
        """
}
