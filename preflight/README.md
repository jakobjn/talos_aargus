# Preflight

This is a standalone Nextflow port of the older AUH preflight draft.

It is intentionally kept outside the main Talos workflow for now.

## Current scope

The pipeline is manifest-driven and keeps the old preflight stages separate:

1. optional `samplelist.xlsx` mapping into a manifest and pedigree
2. single-sample VCF preparation
3. optional pedigree-driven family merging
4. cohort merge
5. optional exact common-dbSNP subtraction
6. optional legacy SpliceAI annotation

Preflight SpliceAI annotation is off by default. The preferred location for
precomputed SpliceAI lookup is now the main Talos annotation workflow, where it
is applied after core annotation and before Talos filtering.

## What changed from the Bash draft

- no Slurm wrapper scripts
- no spinner / progress UI
- no mandatory `VCF_symlinks` directory
- no required `individual_vcfs_raw` and `individual_vcfs` dual output trees
- no mandatory archive copy of the pre-SpliceAI cohort VCF
- preflight SpliceAI lookup is disabled by default; the main Talos annotation
  workflow is the preferred lookup point

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
  --department DEPT \
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

The standalone preflight workflow can use a shared AUH runtime under
`/faststorage/project/reanalyses_auh/env/talos2_env/`.

`preflight/local.config` currently points to:

```groovy
params.runtime_bin_dir = "/faststorage/project/reanalyses_auh/env/talos2_env/bin"
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

When enabled, common-dbSNP subtraction runs once on the merged cohort VCF,
before optional SpliceAI annotation. This keeps common variants out of the
expensive annotation step without one indexed-resource scan per sample.

SpliceAI annotation:

```bash
--spliceai_enabled true
--spliceai_vcf /path/to/spliceai_resource.vcf.gz
```

The final cohort VCF is published with the stable name `cohort_merged.vcf.gz`
whether this optional preflight SpliceAI step is enabled or disabled.

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

Family merging is disabled by default. Prepared individual VCFs are merged
directly into the cohort VCF with `--missing-to-ref`; a parent without a record
at a cohort locus is therefore still represented as `0/0` with missing
depth/GQ, as in the family-merge path.

Enable family merging when a per-proband family VCF is required:

```bash
--family_merge_enabled true
```

When enabled, family VCFs are internal workflow intermediates by default.

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

`preflight/examples/first_trio/` contains a fully synthetic role-based trio.
The manifest uses placeholder VCF paths and must be edited before running.

Shell entrypoints:

- `example_preflight.sh`
- `example_preflight_apptainer.sh`
- `example_with_talos_apptainer.sh`
- `run_preflight_apptainer.sh`
