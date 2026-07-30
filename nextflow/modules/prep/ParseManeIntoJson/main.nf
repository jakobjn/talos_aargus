process ParseManeIntoJson {

    input:
    	path mane_summary

    output:
        path "mane.json"

    script:
        """
        set -euo pipefail
        export PYTHONPATH="${projectDir}/src:\$PYTHONPATH"

        python -m talos.annotation_scripts.parse_mane_into_json \
            --input ${mane_summary} \
            --output mane.json \
            --format json
        """
}
