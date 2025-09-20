from __future__ import annotations

import json
import logging
import time
from pathlib import Path
from typing import Any, Dict, Tuple

import numpy as np
import torch
import xgboost as xgb
import yaml
from sklearn.datasets import make_classification, make_regression
from sklearn.metrics import log_loss, mean_squared_error

from .paths import CONFIG_DIR, RUNS_DIR

LOGGER = logging.getLogger("src.models")


def load_config() -> Dict[str, Any]:
    """Load experiment config from configs/config.yaml."""
    config_path = CONFIG_DIR / "config.yaml"
    with config_path.open("r", encoding="utf8") as fp:
        return yaml.safe_load(fp)


def resolve_device(preferred: str) -> str:
    """Resolve the training device based on config and runtime availability.

    preferred:
      - "cpu"    -> always cpu
      - "cuda"   -> cuda if available, else cpu
      - "rocm"   -> rocm if available, else cpu
      - "auto"   -> prioritize cuda, then rocm, else cpu
    """
    hip = getattr(torch.version, "hip", None)
    prefer = (preferred or "auto").lower()

    if prefer == "cpu":
        return "cpu"
    if prefer == "cuda":
        return "cuda" if torch.cuda.is_available() else "cpu"
    if prefer == "rocm":
        return "rocm" if hip else "cpu"

    # auto
    if torch.cuda.is_available():
        return "cuda"
    if hip:
        return "rocm"
    return "cpu"


def xgb_tree_method(device: str) -> str:
    """Choose XGBoost tree method depending on device."""
    return "gpu_hist" if device in {"cuda", "rocm"} else "hist"


def synthetic_dataset(task: str) -> Tuple[np.ndarray, np.ndarray]:
    """Create a small synthetic dataset for sanity checks."""
    rng = np.random.default_rng(42)
    if task == "regression":
        X, y = make_regression(
            n_samples=512,
            n_features=16,
            noise=0.1,
            random_state=int(rng.integers(0, 1_000_000)),
        )
        return X, y
    X, y = make_classification(
        n_samples=512,
        n_features=16,
        n_informative=8,
        n_redundant=2,
        n_classes=2,
        random_state=int(rng.integers(0, 1_000_000)),
    )
    return X, y


def train_xgboost(config: Dict[str, Any], device: str, run_dir: Path) -> Dict[str, Any]:
    """Train a tiny XGBoost model on the synthetic dataset."""
    params = config.get("xgboost", {})
    task = config.get("task", "classification")
    X, y = synthetic_dataset(task)
    tree_method = xgb_tree_method(device)
    model_kwargs = dict(
        tree_method=tree_method,
        n_estimators=params.get("n_estimators", 500),
        max_depth=params.get("max_depth", 6),
        learning_rate=params.get("learning_rate", 0.05),
        subsample=params.get("subsample", 0.8),
        colsample_bytree=params.get("colsample_bytree", 0.8),
        random_state=config.get("seed", 42),
        n_jobs=0,
    )
    if task == "regression":
        booster = xgb.XGBRegressor(**model_kwargs)
    else:
        booster = xgb.XGBClassifier(**model_kwargs)
    LOGGER.info("Training XGBoost with tree_method=%s", tree_method)
    booster.fit(X, y)

    model_dir = run_dir / "models"
    model_dir.mkdir(parents=True, exist_ok=True)
    model_path = model_dir / "xgb.model"
    booster.save_model(model_path)
    LOGGER.info("Saved XGBoost model to %s", model_path)

    if task == "regression":
        preds = booster.predict(X)
        metric_value = float(mean_squared_error(y, preds, squared=False))
        return {"rmse": metric_value}
    preds = booster.predict_proba(X)[:, 1]
    return {"logloss": float(log_loss(y, preds))}


def train_torch(config: Dict[str, Any], device: str, run_dir: Path) -> Dict[str, Any]:
    """Train a tiny PyTorch MLP on the synthetic dataset."""
    torch.manual_seed(int(config.get("seed", 42)))
    torch_device = torch.device("cuda" if device in {"cuda", "rocm"} and torch.cuda.is_available() else "cpu")
    LOGGER.info("Training PyTorch baseline on %s", torch_device)

    X, y = synthetic_dataset(config.get("task", "classification"))
    X_tensor = torch.tensor(X, dtype=torch.float32, device=torch_device)

    if config.get("task", "classification") == "regression":
        y_tensor = torch.tensor(y, dtype=torch.float32, device=torch_device).unsqueeze(1)
        model = torch.nn.Sequential(
            torch.nn.Linear(X_tensor.shape[1], 64),
            torch.nn.ReLU(),
            torch.nn.Linear(64, 1),
        ).to(torch_device)
        criterion = torch.nn.MSELoss()
    else:
        y_tensor = torch.tensor(y, dtype=torch.long, device=torch_device)
        model = torch.nn.Sequential(
            torch.nn.Linear(X_tensor.shape[1], 64),
            torch.nn.ReLU(),
            torch.nn.Linear(64, 2),
        ).to(torch_device)
        criterion = torch.nn.CrossEntropyLoss()

    optimizer = torch.optim.Adam(model.parameters(), lr=1e-3)
    model.train()
    last_metric = 0.0
    for epoch in range(5):
        optimizer.zero_grad()
        outputs = model(X_tensor)
        loss = criterion(outputs, y_tensor)
        loss.backward()
        optimizer.step()
        last_metric = float(loss.item())
        LOGGER.info("Epoch %d loss %.4f", epoch + 1, last_metric)

    model_dir = run_dir / "models"
    model_dir.mkdir(parents=True, exist_ok=True)
    torch_path = model_dir / "torch.pt"
    torch.save(model.state_dict(), torch_path)
    LOGGER.info("Saved torch model to %s", torch_path)

    metric_name = "train_loss" if config.get("task", "classification") == "classification" else "train_mse"
    return {metric_name: last_metric}


def main() -> None:
    logging.basicConfig(level=logging.INFO)
    config = load_config()
    device = resolve_device(config.get("device", "auto"))
    run_dir = RUNS_DIR / time.strftime("%Y%m%d-%H%M%S")
    run_dir.mkdir(parents=True, exist_ok=True)

    metrics = {
        "xgboost": train_xgboost(config, device, run_dir),
        "torch": train_torch(config, device, run_dir),
    }
    metrics_path = run_dir / "metrics.json"
    metrics_path.write_text(json.dumps(metrics, indent=2), encoding="utf8")
    LOGGER.info("Run complete. Metrics written to %s", metrics_path)


if __name__ == "__main__":  # pragma: no cover
    main()
