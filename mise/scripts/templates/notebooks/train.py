import marimo

__generated_with = "${MARIMO_VERSION}"
app = marimo.App()


@app.cell
def __():
    import sys
    from pathlib import Path

    try:
        project_root = Path(__file__).resolve().parent.parent
    except NameError:
        project_root = Path.cwd().parent
    if str(project_root) not in sys.path:
        sys.path.append(str(project_root))
    return project_root


@app.cell
def __():
    """
    Training notebook for quick experimentation with XGBoost on a synthetic dataset.

    Parameters:
      - TASK: "classification" or "regression"
      - TEST_SIZE: train/test split ratio
      - RANDOM_STATE: RNG seed for reproducibility
      - USE_GPU: attempt to use GPU ("gpu_hist") if available; will gracefully fallback
                 to CPU ("hist") if not supported by your XGBoost wheel.
    """
    TASK = "classification"  # "classification" | "regression"
    TEST_SIZE = 0.2
    RANDOM_STATE = 42
    USE_GPU = False
    return RANDOM_STATE, TASK, TEST_SIZE, USE_GPU


@app.cell
def __(RANDOM_STATE, TASK, TEST_SIZE):
    import xgboost as xgb
    from sklearn.metrics import log_loss as _log_loss, mean_squared_error
    from sklearn.model_selection import train_test_split

    from src.models import synthetic_dataset, xgb_tree_method

    return (
        RANDOM_STATE,
        TASK,
        TEST_SIZE,
        _log_loss,
        mean_squared_error,
        synthetic_dataset,
        train_test_split,
        xgb,
        xgb_tree_method,
    )


@app.cell
def __(TASK, USE_GPU, xgb_tree_method):
    """
    Resolve tree_method for XGBoost.
    By default we use CPU ("hist") to avoid dependency on GPU-enabled wheels.
    If USE_GPU is True, we try to use "gpu_hist" when possible.
    """
    # Default to CPU to maximize compatibility
    resolved_device = "cuda" if USE_GPU else "cpu"
    tree_method = xgb_tree_method(resolved_device)
    if not USE_GPU:
        # Force hist for CPU-only installs
        tree_method = "hist"
    tree_method
    return resolved_device, tree_method


@app.cell
def __(
    RANDOM_STATE,
    TASK,
    TEST_SIZE,
    mean_squared_error,
    synthetic_dataset,
    train_test_split,
):
    """
    Prepare dataset and split.
    """
    X, y = synthetic_dataset(TASK)
    X_train, X_test, y_train, y_test = train_test_split(
        X, y, test_size=TEST_SIZE, random_state=RANDOM_STATE
    )
    X.shape, X_train.shape, X_test.shape
    return X, X_test, X_train, y, y_test, y_train


@app.cell
def __(
    TASK,
    X_test,
    X_train,
    mean_squared_error,
    tree_method,
    y_test,
    y_train,
    xgb,
    _log_loss,
):
    """
    Train XGBoost and evaluate.
    - classification: logloss
    - regression: RMSE
    Includes a fallback to CPU 'hist' if GPU tree_method is unsupported.
    """
    # log_loss is provided via a previous cell

    params = dict(
        tree_method=tree_method,
        n_estimators=300,
        max_depth=6,
        learning_rate=0.05,
        subsample=0.8,
        colsample_bytree=0.8,
        n_jobs=0,
        random_state=42,
    )

    booster = None
    metric_value = None
    metric_name = None

    try:
        if TASK == "regression":
            booster = xgb.XGBRegressor(**params)
        else:
            booster = xgb.XGBClassifier(**params)
        booster.fit(X_train, y_train)
    except Exception as e:
        # Fallback to CPU hist if GPU not supported by the installed wheel
        print(f"Training with tree_method='{tree_method}' failed: {e!r}")
        params["tree_method"] = "hist"
        print("Falling back to tree_method='hist' (CPU).")
        if TASK == "regression":
            booster = xgb.XGBRegressor(**params)
        else:
            booster = xgb.XGBClassifier(**params)
        booster.fit(X_train, y_train)

    if TASK == "regression":
        preds = booster.predict(X_test)
        metric_value = float(mean_squared_error(y_test, preds, squared=False))
        metric_name = "rmse"
    else:
        preds = booster.predict_proba(X_test)[:, 1]
        metric_value = float(_log_loss(y_test, preds))
        metric_name = "logloss"

    print(f"Validation {metric_name}: {metric_value:.4f}")
    metric_name, metric_value, booster
    return booster, metric_name, metric_value, preds


@app.cell
def __(TASK, X_test, preds):
    """
    Optional visualization for classification: histogram of predicted probabilities.
    Skipped for regression.
    """
    if TASK == "classification":
        import plotly.express as px
        import polars as pl

        s = pl.Series("pred", preds)
        fig = px.histogram(
            x=s.to_list(), nbins=50, title="Predicted probability distribution"
        )
        fig
    else:
        print("Regression task: skipping probability histogram.")


if __name__ == "__main__":
    app.run()
