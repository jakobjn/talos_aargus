#!/usr/bin/env bash

set -euo pipefail

CONDA_ENV="${CONDA_ENV:-talos2_env}"
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
ECHTVAR_VERSION="${ECHTVAR_VERSION:-v0.2.2}"

if [[ -n "${CONDA_EXE:-}" ]]; then
    CONDA_BIN="${CONDA_EXE}"
elif command -v conda >/dev/null 2>&1; then
    CONDA_BIN="$(command -v conda)"
else
    echo "[ERROR] Could not find 'conda' on PATH. Activate conda or set CONDA_EXE first." >&2
    exit 1
fi

CONDA_BASE="$("${CONDA_BIN}" info --base)"
CONDA_SH="${CONDA_BASE}/etc/profile.d/conda.sh"

if [[ ! -f "${CONDA_SH}" ]]; then
    echo "[ERROR] Conda initialization script not found: ${CONDA_SH}" >&2
    exit 1
fi

source "${CONDA_SH}"

if ! conda env list | awk '{print $1}' | grep -qx "${CONDA_ENV}"; then
    echo "[INFO] Creating conda env '${CONDA_ENV}'"
    conda create -y -n "${CONDA_ENV}" -c conda-forge python=3.11
fi

echo "[INFO] Installing conda runtime packages into '${CONDA_ENV}'"
conda install -y -n "${CONDA_ENV}" -c conda-forge -c bioconda \
    nextflow=26.04.6 \
    bcftools \
    htslib \
    samtools \
    wget \
    pip

echo "[INFO] Installing Python dependencies from pyproject.toml into '${CONDA_ENV}'"
conda run -n "${CONDA_ENV}" python -m pip install \
    'hail~=0.2.137' \
    'clinvarbitration~=2.2.7' \
    'cloudpathlib[all]>=0.16.0' \
    'cpg-utils~=5.7' \
    'cyvcf2>=0.30.18' \
    'grpcio-status>=1.48,<1.50' \
    'httpx>=0.27.0' \
    'Jinja2>=3.1.3' \
    'mendelbrot>=0.0.3' \
    'networkx>=3' \
    'obonet>=1' \
    'pendulum>=3.1.0' \
    'pydantic>=2.5.2' \
    'python-dateutil>=2' \
    'semsimian' \
    'tabulate>=0.8.9' \
    'tenacity>=9.0.0' \
    'toml==0.10.2'

ENV_PREFIX="$(conda env list | awk -v env="${CONDA_ENV}" '$1 == env {print $NF}')"
if [[ -z "${ENV_PREFIX}" ]]; then
    echo "[ERROR] Could not determine conda prefix for '${CONDA_ENV}'" >&2
    exit 1
fi

if [[ ! -x "${ENV_PREFIX}/bin/echtvar" ]]; then
    echo "[INFO] Installing echtvar ${ECHTVAR_VERSION} into '${CONDA_ENV}'"
    curl -L --fail \
        "https://github.com/brentp/echtvar/releases/download/${ECHTVAR_VERSION}/echtvar" \
        -o "${ENV_PREFIX}/bin/echtvar"
    chmod +x "${ENV_PREFIX}/bin/echtvar"
fi

echo "[INFO] Verifying tool availability in '${CONDA_ENV}'"
conda run -n "${CONDA_ENV}" which python
if command -v nextflow >/dev/null 2>&1; then
    command -v nextflow
elif conda run -n "${CONDA_ENV}" which nextflow >/dev/null 2>&1; then
    conda run -n "${CONDA_ENV}" which nextflow
else
    echo "[WARN] nextflow was not found on PATH or inside '${CONDA_ENV}'. Install it separately if needed."
fi
conda run -n "${CONDA_ENV}" which bcftools
conda run -n "${CONDA_ENV}" which samtools
conda run -n "${CONDA_ENV}" which tabix
conda run -n "${CONDA_ENV}" which bgzip
if command -v wget >/dev/null 2>&1; then
    command -v wget
else
    conda run -n "${CONDA_ENV}" which wget
fi
conda run -n "${CONDA_ENV}" which echtvar
conda run -n "${CONDA_ENV}" python - <<'PY'
import importlib
for mod in [
    "cyvcf2",
    "pendulum",
    "pydantic",
    "httpx",
    "networkx",
    "obonet",
    "tabulate",
    "tenacity",
    "toml",
    "mendelbrot",
    "clinvarbitration",
]:
    importlib.import_module(mod)
print("python dependencies ok")
PY

echo "[INFO] '${CONDA_ENV}' is ready"
echo "[INFO] Activate with: conda activate ${CONDA_ENV}"
echo "[INFO] Nextflow will use repo source directly via PYTHONPATH=${BASE_DIR}/src"
