#!/usr/bin/env bash

set -euo pipefail

APPTAINER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_DIR="$(cd "${APPTAINER_DIR}/.." && pwd -P)"
BUILD_DIR="${APPTAINER_DIR}/build"
DEF_FILE="${APPTAINER_DIR}/talos_env.def"
RENDERED_DEF="${BUILD_DIR}/talos_env.rendered.def"
ENV_TAR="${APPTAINER_DIR}/assets/talos2_env.tar.gz"
ENV_SHA="${APPTAINER_DIR}/assets/talos2_env.sha256"
ENV_MANIFEST="${APPTAINER_DIR}/assets/talos2_env.manifest.txt"
SIF_PATH="${BUILD_DIR}/talos-nextflow.sif"
LOCAL_BASE="${APPTAINER_LOCAL_BASE:-}"

mkdir -p "${BUILD_DIR}"

if [[ ! -f "${ENV_TAR}" ]]; then
    echo "[ERROR] Missing staged env tar: ${ENV_TAR}" >&2
    echo "[INFO] Run: bash apptainer/fetch_env_to_folder.sh" >&2
    exit 1
fi
if [[ ! -f "${ENV_SHA}" ]]; then
    echo "[ERROR] Missing env checksum file: ${ENV_SHA}" >&2
    echo "[INFO] Run: bash apptainer/fetch_env_to_folder.sh" >&2
    exit 1
fi
if [[ ! -f "${ENV_MANIFEST}" ]]; then
    echo "[ERROR] Missing env manifest file: ${ENV_MANIFEST}" >&2
    echo "[INFO] Run: bash apptainer/fetch_env_to_folder.sh" >&2
    exit 1
fi

export APPTAINER_TMPDIR="${APPTAINER_TMPDIR:-${SINGULARITY_TMPDIR:-/tmp}}"
export APPTAINER_CACHEDIR="${APPTAINER_CACHEDIR:-${SINGULARITY_CACHEDIR:-$HOME/.apptainer/cache}}"

echo "[INFO] Verifying staged env tar checksum"
(cd "${APPTAINER_DIR}/assets" && sha256sum --check "$(basename "${ENV_SHA}")")

cp "${DEF_FILE}" "${RENDERED_DEF}"
python - <<PY
from pathlib import Path
import os

rendered = Path(r"${RENDERED_DEF}")
apptainer_dir = Path(r"${APPTAINER_DIR}")
assets_dir = apptainer_dir / "assets"
manifest = Path(r"${ENV_MANIFEST}")

env_prefix = None
for line in manifest.read_text().splitlines():
    if line.startswith("env_prefix="):
        env_prefix = line.split("=", 1)[1].strip()
        break
if not env_prefix:
    raise SystemExit("Missing env_prefix in manifest")
env_parent = os.path.dirname(env_prefix)

lines = rendered.read_text().splitlines()
rewritten = []
for line in lines:
    stripped = line.strip()
    if stripped.startswith("./assets/"):
        src, dest = stripped.split(maxsplit=1)
        abs_src = assets_dir / src.removeprefix("./assets/")
        rewritten.append(f"    {abs_src} {dest}")
    else:
        updated = line.replace("__TALOS_ENV_PREFIX__", env_prefix)
        updated = updated.replace("__TALOS_ENV_PARENT__", env_parent)
        rewritten.append(updated)
rendered.write_text("\\n".join(rewritten) + "\\n")
PY

if [[ -n "${LOCAL_BASE}" ]]; then
    if [[ ! -f "${LOCAL_BASE}" ]]; then
        echo "[ERROR] APPTAINER_LOCAL_BASE does not exist: ${LOCAL_BASE}" >&2
        exit 1
    fi
    python - <<PY
from pathlib import Path
path = Path(r"${RENDERED_DEF}")
lines = path.read_text().splitlines()
lines[0] = "Bootstrap: localimage"
lines[1] = "From: ${LOCAL_BASE}"
path.write_text("\\n".join(lines) + "\\n")
PY
    echo "[INFO] Using local Apptainer base image: ${LOCAL_BASE}"
fi

echo "[INFO] Building ${SIF_PATH} with fakeroot"
env -u HTTP_PROXY -u HTTPS_PROXY -u ALL_PROXY -u http_proxy -u https_proxy -u all_proxy \
    apptainer build --fakeroot --force "${SIF_PATH}" "${RENDERED_DEF}"

echo "[INFO] Running smoke test inside ${SIF_PATH}"
apptainer exec "${SIF_PATH}" nextflow -version
apptainer exec "${SIF_PATH}" python - <<'PY'
import importlib
for mod in ["cyvcf2", "mendelbrot", "clinvarbitration"]:
    importlib.import_module(mod)
print("smoke test ok")
PY

echo "[INFO] Build completed: ${SIF_PATH}"
