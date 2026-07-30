process MAP_SAMPLE_SHEET {
    cpus 1
    memory 2.GB

    input:
    path samplelist_xlsx

    output:
    path 'sample_manifest.tsv', emit: manifest
    path 'pedigree.ped', emit: pedigree
    path 'mapping_report.tsv', emit: report

    script:
    def mappingRoots = params.mapping_roots ? "--mapping-roots '${params.mapping_roots}'" : ''
    """
    set -euo pipefail

    python "${projectDir}/bin/map_samplelist_to_manifest.py" \
      --samplelist "${samplelist_xlsx}" \
      --department "${params.department}" \
      --manifest-output sample_manifest.tsv \
      --pedigree-output pedigree.ped \
      --report-output mapping_report.tsv \
      ${mappingRoots}
    """
}
