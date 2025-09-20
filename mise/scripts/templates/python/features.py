from __future__ import annotations

import polars as pl


def identity_features(frame: pl.DataFrame) -> pl.DataFrame:
    """Return the input frame unchanged as a placeholder."""
    return frame.clone()


__all__ = ["identity_features"]
