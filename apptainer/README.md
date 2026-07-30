## Apptainer Packaging

This folder contains a simple two-step packaging flow for the tested `talos2_env`
runtime:

1. Stage the current conda env into this folder as a tarball.
2. Build an Apptainer `.sif` from that tarball with `fakeroot`.

The resulting image is intended to run the existing Talos v11 workflow code from a
bound checkout of this repository. The software environment is baked into the image;
the repository, `large_files`, and `processed_annotations` stay outside the image.

### Files

- `fetch_env_to_folder.sh`
  Creates `apptainer/assets/talos2_env.tar.gz` from the current conda env.

- `talos_env.def`
  Definition file used by `apptainer build --fakeroot`.

- `build_sif.sh`
  Builds `apptainer/build/talos-nextflow.sif` from the staged env tarball and runs a
  lightweight smoke test inside the container.

### Typical flow

```bash
cd /path/to/talos
bash apptainer/fetch_env_to_folder.sh
bash apptainer/build_sif.sh
```

If the build host cannot reach Docker Hub but you already have a local Apptainer base image,
point the build at it:

```bash
APPTAINER_LOCAL_BASE=/path/to/ubuntu-base.sif bash apptainer/build_sif.sh
```

Then run the bundled Nextflow example through the top-level wrapper:

```bash
bash ./run_nextflow_example_apptainer.sh
```

The standalone preflight workflow can also be run inside the same SIF:

```bash
bash ./preflight/example_preflight_apptainer.sh
```

And the synthetic full-chain preflight plus Talos example:

```bash
bash ./preflight/example_with_talos_apptainer.sh
```

### Notes

- The env tar is restored to the same prefix it had on the build host.
- That prefix is read from `apptainer/assets/talos2_env.manifest.txt` during the
  build, so no user-specific path is hardcoded in the committed definition file.
- This avoids conda relocation issues when using a plain tarball.
- The image does not bundle `large_files` or `processed_annotations`.
- The test wrapper binds the current repo checkout into the container and executes
  the Talos v11 TSV-driven workflow from there.
- The build script strips `HTTP_PROXY` and related variables for the Apptainer build
  command, because broken cluster proxy settings are a common failure mode.
