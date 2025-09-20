from __future__ import annotations

from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parents[1]
DATA_DIR = PROJECT_ROOT / "data"
DATA_RAW = DATA_DIR / "raw"
DATA_EXTERNAL = DATA_DIR / "external"
DATA_INTERIM = DATA_DIR / "interim"
DATA_PROCESSED = DATA_DIR / "processed"
CONFIG_DIR = PROJECT_ROOT / "configs"
NOTEBOOKS_DIR = PROJECT_ROOT / "notebooks"
RUNS_DIR = PROJECT_ROOT / "runs"
LOGS_DIR = PROJECT_ROOT / "logs"

__all__ = [
    "PROJECT_ROOT",
    "DATA_DIR",
    "DATA_RAW",
    "DATA_EXTERNAL",
    "DATA_INTERIM",
    "DATA_PROCESSED",
    "CONFIG_DIR",
    "NOTEBOOKS_DIR",
    "RUNS_DIR",
    "LOGS_DIR",
]
