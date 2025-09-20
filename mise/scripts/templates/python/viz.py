from __future__ import annotations

import polars as pl
import plotly.graph_objects as go


def histogram(frame: pl.DataFrame, column: str):
    """Create a Plotly histogram from a Polars DataFrame column.

    Args:
        frame: Polars DataFrame containing the data.
        column: Column name to visualize.

    Returns:
        A plotly.graph_objs._figure.Figure instance.
    """
    return go.Figure(go.Histogram(x=frame.get_column(column).to_list()))


__all__ = ["histogram"]
