from __future__ import annotations

import polars as pl
import plotly.express as px


def histogram(frame: pl.DataFrame, column: str):
    """Create a Plotly histogram from a Polars DataFrame column.

    Args:
        frame: Polars DataFrame containing the data.
        column: Column name to visualize.

    Returns:
        A plotly.graph_objs._figure.Figure instance.
    """
    return px.histogram(frame.to_pandas(), x=column)


__all__ = ["histogram"]
