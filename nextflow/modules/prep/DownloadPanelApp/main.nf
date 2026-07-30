process DownloadPanelApp {

    input:
        path mane
        val timestamp

    output:
        path "panelapp_${timestamp}.json"

    script:
        """
        set -euo pipefail
        export PYTHONPATH="${projectDir}/src:\$PYTHONPATH"

        python -m talos.download_panelapp \
            --output panelapp_${timestamp}.json \
            --mane ${mane}
        """
}
