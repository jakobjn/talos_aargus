# Preflight

This is a standalone Nextflow port of the older AUH preflight draft.

It is intentionally kept outside the main Talos workflow for now.

## Current scope

The pipeline is manifest-driven and keeps the old preflight stages separate:

1. optional `samplelist.xlsx` mapping into a manifest and pedigree
2. single-sample VCF preparation
3. optional exact common-dbSNP subtraction
4. pedigree-driven family merging
5. cohort merge
6. optional SpliceAI annotation

## What changed from the Bash draft

- no Slurm wrapper scripts
- no spinner / progress UI
- no mandatory `VCF_symlinks` directory
- no required `individual_vcfs_raw` and `individual_vcfs` dual output trees
- no mandatory archive copy of the pre-SpliceAI cohort VCF

The main persistent checkpoint between stages is the prepared manifest:

- `prepared_manifest.tsv`

## Inputs

Use one of these modes:

1. direct manifest mode

```bash
nextflow run preflight/main.nf \
  -c preflight/nextflow.config \
  -c preflight/local.config \
  --sample_manifest preflight/examples/first_trio/sample_manifest.tsv \
  --pedigree preflight/examples/first_trio/pedigree.ped \
  -output-dir preflight/results
```

2. Excel mapping mode

```bash
nextflow run preflight/main.nf \
  -c preflight/nextflow.config \
  -c preflight/local.config \
  --samplelist_xlsx /path/to/samplelist.xlsx \
  --department KGA \
  -output-dir preflight/results
```

Excel mode writes:

- `sample_manifest.tsv`
- `pedigree.ped`
- `mapping_report.tsv`

The direct manifest format is:

```tsv
sample_id	vcf_path
```

The committed example uses only generic role-based names. Replace the
placeholder VCF paths with real files before running.

## Local runtime config

The standalone preflight workflow can use a local runtime staged under
`preflight/runtime/`.

`preflight/local.config` currently points to:

```groovy
params.runtime_bin_dir = "${projectDir}/runtime/talos2_env/bin"
```

That keeps runtime lookup explicit without requiring shell activation. The older
`tool_bin_dir` parameter is still accepted as a fallback, but `runtime_bin_dir`
is now the preferred name.

## Optional resources

Common dbSNP subtraction:

```bash
--common_dbsnp_enabled true
--common_dbsnp_vcf /path/to/common_resource.vcf.gz
```

SpliceAI annotation:

```bash
--spliceai_enabled true
--spliceai_vcf /path/to/spliceai_resource.vcf.gz
```

The local config in this AUH checkout is wired to a shared sibling resource
folder:

- `../../../resources/20260518_common_resource.vcf.gz`
- `../../../resources/spliceai_scores_KGA_AUH_GRCh_38_Homo_sapiens_converted.vcf.gz`

## Example Calls

Synthetic smoke test:

```bash
bash preflight/example_preflight.sh
```

Synthetic Apptainer smoke test:

```bash
bash preflight/example_preflight_apptainer.sh
```

Synthetic preflight plus Talos smoke test:

```bash
bash preflight/example_with_talos_apptainer.sh
```

Real family bundle generation:

```bash
bash preflight/create_family_bundle.sh \
  --proband /path/to/PROBAND.vcf.gz \
  --mother /path/to/MOTHER.vcf.gz \
  --father /path/to/FATHER.vcf.gz
```

Fast smoke mode:

```bash
bash preflight/create_family_bundle.sh \
  --proband /path/to/PROBAND.vcf.gz \
  --mother /path/to/MOTHER.vcf.gz \
  --father /path/to/FATHER.vcf.gz \
  --fast true
```

Run the generated bundle directly:

```bash
bash trio_runs/<bundle_name>/run_full_slurm.sh
```

Or submit it through Slurm:

```bash
sbatch trio_runs/<bundle_name>/run_full_slurm.sh
```

## Family VCF publishing

Family VCFs are kept as internal workflow intermediates either way.

By default they are not published into the visible output directory.

To publish them:

```bash
--publish_family_vcfs true
```

To remove previously published family VCF outputs before a run:

```bash
--flush_published_family_vcfs true
```

This flush only affects the published `family_vcfs/` output folder. It does not
clear Nextflow `work/` directories or resume cache state.

## Example

`preflight/examples/first_trio/` contains the first trio extracted from the
current KGA pedigree as a concrete starting point. The manifest uses placeholder
VCF paths and must be edited before running.

Shell entrypoints:

- `example_preflight.sh`
- `example_preflight_apptainer.sh`
- `example_with_talos_apptainer.sh`
- `run_preflight_apptainer.sh`
