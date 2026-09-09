# One-Proband, Two-Variant Fixture

This is the runner default project. `source_vcfs/proband/v2.0/raw/` contains two
raw single-sample VCF records for an affected male proband:

- `chr20:13786479 A>G`
- `chr20:13788652 G>C` (`NDUFAF5`)

Preflight outputs, Nextflow work, logs, symlinks, and Talos reports are ignored.
The runner uses this project by default and can be switched to a different project
without changing `runner.config`.
