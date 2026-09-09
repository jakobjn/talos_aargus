from pathlib import Path


APP_DIR = Path(__file__).resolve().parents[1]
PARENT_DIR = Path(__file__).resolve().parents[2]
TALOS_REPO_DIR = PARENT_DIR
WORKSPACE_DIR = APP_DIR

RUNNER_CONFIG_FILE = APP_DIR / "runner.config"
UPLOAD_ID = "excel_upload"
DEFAULT_PREFLIGHT_PROJECT_DIR = WORKSPACE_DIR
DEFAULT_PREFLIGHT_SAMPLELIST_FILENAME = "samplelist.xlsx"
PREFLIGHT_RUN_SCRIPT = APP_DIR / "run_dept_preflight_local.sh"
TALOS_RUN_SCRIPT = APP_DIR / "run_dept_talos_local.sh"
RESOURCE_SCRIPT_CANDIDATES = [
    TALOS_REPO_DIR / "large_files" / "download_resources_slurm.sh",
]
PREPARATION_PROCESSED_ANNOTATIONS = "processed_annotations"
PREPARATION_LARGE_FILES = "large_files"


def ensure_dirs():
    RUNNER_CONFIG_FILE.parent.mkdir(parents=True, exist_ok=True)
