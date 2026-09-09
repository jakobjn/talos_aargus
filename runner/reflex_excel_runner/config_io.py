from pathlib import Path

from .paths import RUNNER_CONFIG_FILE


def config_path(path: str | Path | None = None) -> Path:
    return Path(path).expanduser() if path else RUNNER_CONFIG_FILE


def load_runner_config(path: str | Path | None = None) -> dict:
    path = config_path(path)
    if not path.exists():
        return {}
    settings: dict[str, str] = {}
    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        if "=" not in line:
            raise ValueError(f"Could not parse runner.config line: {raw_line}")
        key, value = line.split("=", 1)
        settings[key.strip()] = value.strip()
    return settings


def read_runner_config_text(path: str | Path | None = None) -> str:
    path = config_path(path)
    if not path.exists():
        return ""
    return path.read_text(encoding="utf-8")


def write_runner_config_text(content: str, path: str | Path | None = None):
    config_path(path).write_text(content, encoding="utf-8")
