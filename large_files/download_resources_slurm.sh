#!/usr/bin/env bash
#SBATCH --job-name=talos_download
#SBATCH --output=talos_download_%j.out
#SBATCH --error=talos_download_%j.err
#SBATCH --time=24:00:00
#SBATCH --cpus-per-task=2
#SBATCH --mem=8G

set -euo pipefail

# Run from the large_files directory so downloaded resources land here by default.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

# Disable the interactive tmux launcher inside batch jobs.
export TALOS_DISABLE_TMUX=1

bash ./gather_files.sh
