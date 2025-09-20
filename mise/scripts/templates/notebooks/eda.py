import marimo

__generated_with = "${MARIMO_VERSION}"
app = marimo.App()


@app.cell
def __():
    import sys
    from pathlib import Path as _Path

    try:
        project_root = _Path(__file__).resolve().parent.parent
    except NameError:
        # Fallback for environments where __file__ is not defined
        project_root = _Path.cwd().parent
    if str(project_root) not in sys.path:
        sys.path.append(str(project_root))
    return project_root


@app.cell
def __(app=app):
    """
    Configure notebook theme and matplotlib style based on template variable THEME.
    Available: auto | light | dark
    """
    import matplotlib.pyplot as plt

    theme = "${THEME}"
    if theme != "auto":
        # marimo <=0.7 compatibility: set_theme may not exist
        try:
            app.set_theme(theme)
        except AttributeError:
            pass
        if theme == "dark":
            plt.style.use("dark_background")
        else:
            plt.style.use("default")
    return theme


@app.cell
def __(theme):
    """
    Load common libs and show project data paths.
    """
    import os

    import numpy as np
    import polars as pl
    from rich.console import Console

    from src.paths import DATA_RAW, DATA_INTERIM, DATA_PROCESSED

    console = Console()
    console.rule("[bold cyan]Project Paths")
    console.print(f"[green]DATA_RAW     :[/] {DATA_RAW}")
    console.print(f"[green]DATA_INTERIM:[/] {DATA_INTERIM}")
    console.print(f"[green]DATA_PROCESSED:[/] {DATA_PROCESSED}")
    console.print(f"[green]Theme:[/] {theme}")
    return DATA_INTERIM, DATA_PROCESSED, DATA_RAW, console, np, os, pl


@app.cell
def __(DATA_RAW, console, pl):
    """
    Discover and load the first CSV in data/raw for a quick look.
    """
    csvs = sorted(DATA_RAW.rglob("*.csv"))
    parquet = sorted(DATA_RAW.rglob("*.parquet"))
    file_path = None

    if csvs:
        file_path = csvs[0]
        console.print(f"[yellow]Loading CSV:[/] {file_path}")
        frame = pl.read_csv(file_path)
    elif parquet:
        file_path = parquet[0]
        console.print(f"[yellow]Loading Parquet:[/] {file_path}")
        frame = pl.read_parquet(file_path)
    else:
        console.print("[red]No CSV or Parquet files found in data/raw.[/]")
        frame = pl.DataFrame()

    return file_path, frame


@app.cell
def __(console, file_path, frame, pl):
    """
    Show shape, dtypes, preview, and basic describe.
    """
    if frame.is_empty():
        console.print("[red]Empty frame. Skipping summary.[/]")
        summary = pl.DataFrame()
        head = pl.DataFrame()
        info = {"rows": 0, "cols": 0}
    else:
        info = {"rows": frame.height, "cols": frame.width}
        console.rule("[bold cyan]Overview")
        console.print(f"[green]Rows:[/] {info['rows']}  [green]Cols:[/] {info['cols']}")
        console.print("[green]Dtypes:[/]")
        console.print(dict(zip(frame.columns, [str(t) for t in frame.dtypes])))
        head = frame.head(10)
        try:
            summary = frame.describe()
        except Exception:
            # Polars may fail describe on some types; fallback to minimal stats
            numeric = [c for c, t in zip(frame.columns, frame.dtypes) if t.is_numeric()]
            summary = (
                frame.select(
                    [pl.col(numeric).mean().alias("mean_" + c) for c in numeric]
                )
                if numeric
                else pl.DataFrame()
            )

    head, summary, info, file_path
    return head, info, summary


@app.cell
def __(console, frame, pl):
    """
    Find a numeric column for demo visualization.
    """
    if frame.is_empty():
        console.print("[yellow]No data for visualization.[/]")
        numeric_col = None
    else:
        numeric_cols = [
            c for c, t in zip(frame.columns, frame.dtypes) if t.is_numeric()
        ]
        numeric_col = numeric_cols[0] if numeric_cols else None
        if numeric_col:
            console.print(f"[green]Selected numeric column:[/] {numeric_col}")
        else:
            console.print("[yellow]No numeric columns found for histogram.[/]")
    return numeric_col


@app.cell
def __(frame, numeric_col, pl):
    """
    Plotly histogram helper: returns a figure or None.
    """
    import plotly.express as px

    fig = None
    if numeric_col and not frame.is_empty():
        # Use Polars Series as a list for Plotly
        fig = px.histogram(
            x=frame.get_column(numeric_col).to_list(),
            nbins=50,
            title=f"Histogram: {numeric_col}",
        )
        fig
    fig
    return fig


@app.cell
def __():
    """
    Torch environment quick check.
    """
    try:
        import torch  # type: ignore

        available = torch.cuda.is_available()
        cuda = getattr(torch.version, "cuda", None)
        hip = getattr(torch.version, "hip", None)
        print(f"torch.cuda.is_available(): {available}")
        print(f"torch.version.cuda: {cuda}")
        print(f"torch.version.hip: {hip}")
    except Exception as e:
        print(f"torch not available: {e!r}")


if __name__ == "__main__":
    app.run()
