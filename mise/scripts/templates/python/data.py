from __future__ import annotations

import argparse
import logging
import time
from pathlib import Path
from typing import Iterable

import polars as pl

LOGGER = logging.getLogger("src.data")


def download_competition(
    slug: str,
    out_dir: Path,
    keep_zip: bool = False,
    force: bool = False,
    retries: int = 3,
) -> Path:
    """Download a Kaggle competition archive to out_dir and extract it.

    - Downloads <slug>.zip into out_dir
    - Extracts into out_dir/<slug>
    - Backs up existing directory when force=True
    - Removes the zip when keep_zip is False
    """
    out_dir.mkdir(parents=True, exist_ok=True)
    archive = out_dir / f"{slug}.zip"
    if archive.exists() and not force:
        LOGGER.info("Archive %s already exists; skipping download.", archive)
    else:
        if archive.exists():
            archive.unlink()
        cmd = [
            "kaggle",
            "competitions",
            "download",
            "-c",
            slug,
            "-p",
            str(out_dir),
        ]
        delay = 1
        for attempt in range(1, retries + 1):
            LOGGER.info("Download attempt %d/%d", attempt, retries)
            result = subprocess_run(cmd)
            if result == 0:
                break
            if attempt == retries:
                raise RuntimeError(f"Kaggle download failed after {retries} attempts")
            LOGGER.warning("Download failed; retrying in %s seconds", delay)
            time.sleep(delay)
            delay *= 2

    dest_dir = out_dir / slug
    if dest_dir.exists() and force:
        backup = dest_dir.with_suffix(".bak")
        if backup.exists():
            if backup.is_dir():
                import shutil

                shutil.rmtree(backup)
            else:
                backup.unlink()
        dest_dir.rename(backup)
        dest_dir = out_dir / slug
    dest_dir.mkdir(parents=True, exist_ok=True)
    unzip_safe(archive, dest_dir)
    if not keep_zip and archive.exists():
        archive.unlink()
    return dest_dir


def subprocess_run(cmd: list[str]) -> int:
    import subprocess

    return subprocess.run(cmd, check=False).returncode


def unzip_safe(zip_path: Path, dest_dir: Path) -> None:
    import zipfile

    if not zip_path.exists():
        raise FileNotFoundError(zip_path)
    dest_dir.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(zip_path) as zf:
        for member in zf.infolist():
            resolved = (dest_dir / member.filename).resolve()
            if not str(resolved).startswith(str(dest_dir.resolve())):
                raise RuntimeError(f"Blocked path traversal: {member.filename}")
        zf.extractall(dest_dir)


def validate_submission(path: Path, expected_columns: Iterable[str] | None = None) -> bool:
    """Validate a CSV submission file.

    Checks:
      - File exists
      - Columns match expected set (if provided)
      - No null values
      - At least one row
    """
    path = path.expanduser().resolve()
    if not path.exists():
        raise FileNotFoundError(path)
    df = pl.read_csv(path)
    if expected_columns and set(df.columns) != set(expected_columns):
        raise ValueError(f"Columns mismatch: {df.columns} vs {expected_columns}")
    nulls = df.null_count().select(pl.sum(pl.all())).row(0)[0]
    if nulls > 0:
        raise ValueError("Submission contains null values")
    if df.height == 0:
        raise ValueError("Submission is empty")
    LOGGER.info("Submission %s validated (%d rows, %d columns)", path, df.height, df.width)
    return True


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--download", dest="slug", help="Competition slug to download")
    parser.add_argument("--out", dest="out", default="data/raw", help="Output directory for downloads")
    parser.add_argument("--keep-zip", action="store_true", help="Keep downloaded zip archive")
    parser.add_argument("--force", action="store_true", help="Overwrite existing data directory if exists")
    parser.add_argument("--retries", type=int, default=3, help="Number of retries for Kaggle download")
    args = parser.parse_args()
    logging.basicConfig(level=logging.INFO)
    if args.slug:
        download_competition(
            slug=args.slug,
            out_dir=Path(args.out),
            keep_zip=args.keep_zip,
            force=args.force,
            retries=args.retries,
        )


if __name__ == "__main__":  # pragma: no cover
    main()
