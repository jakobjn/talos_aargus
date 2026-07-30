process BUILD_FAMILY_MERGE_PLAN {
    cpus 1
    memory 1.GB

    input:
    path pedigree
    path prepared_manifest

    output:
    path 'family_merge_plan.tsv', emit: plan

    script:
    """
    set -euo pipefail

    python "${projectDir}/bin/build_family_merge_plan.py" \
      --pedigree "${pedigree}" \
      --manifest "${prepared_manifest}" \
      --output family_merge_plan.tsv
    """
}
