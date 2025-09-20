# mise Kaggle タスク README

このディレクトリには、Kaggle 用の開発環境を素早く用意し、日常作業をコマンド一発で回せるようにする mise タスク群が含まれています。プロジェクトの初期化、データのダウンロード、ノートブックの起動、学習、提出までをカバーします。

## 前提条件

- mise（タスクランナー）
- uv（Python パッケージ/環境管理）
- Python（推奨: 3.11 以上。`kaggle-init` でピン留め可能）
- Kaggle 資格情報（環境変数 `KAGGLE_USERNAME`/`KAGGLE_KEY` もしくは `~/.kaggle/kaggle.json` を 0600 権限で配置）
- 任意: direnv（`.venv`/`.env` の自動読み込み）
- 任意: GPU 環境（CUDA/ROCm を自動検出）

## 最短クイックスタート

1) Kaggle プロジェクトの雛形を生成
   例: タイタニックを `titanic-baseline` という名前で作成
   - `mise run kaggle-init titanic --name titanic-baseline --open`
   - 生成物はカレントディレクトリ直下に作られます。

2) 生成されたプロジェクトへ移動して依存関係を同期
   - `cd titanic-baseline`Add README for mise Kaggle task setup and usage
   - `uv sync`（初回のみ）
   - 任意: `direnv allow`

3) EDA ノートブック（marimo）を起動
   - `mise run nb-serve`
   - ブラウザでエディタが開きます。

4) ベースライン学習を実行
   - `mise run train`

5) 提出（検証と送信）
   - `mise run kaggle-submit --file submission.csv --message "first try"`

## タスク一覧

- kaggle-init
  - 用途: Kaggle プロジェクトの雛形を作成し、依存関係をセットアップ（GPU/CPU 自動判定、marimo ノート等を生成）
  - 使い方: `mise run kaggle-init <competition-slug> [options]`
  - 主なオプション:
    - `--name <project-name>` プロジェクト名（省略時はスラッグ名）
    - `--py <version>` Python バージョン（例: `3.11`）
    - `--theme <auto|light|dark>` 生成ノートのテーマ
    - `--open` 生成後に marimo エディタを起動
    - `--gpu` / `--cpu` デバイス固定（未指定時は自動検出）
    - `--add <dep1,dep2,...>` 追加パッケージ
    - `--no-download` データの自動ダウンロードをスキップ
    - `--keep-zip` ZIP を削除しない
    - `--force` 既存ファイルの上書き（バックアップ作成）

- kaggle-download
  - 用途: 競技データの再ダウンロードと安全な展開
  - 使い方: `mise run kaggle-download <competition-slug> [options]`
  - 主なオプション:
    - `--project <dir>` 対象プロジェクト（デフォルト: カレント）
    - `--force` 既存の展開結果をバックアップして上書き
    - `--keep-zip` ZIP を削除しない

- nb-serve
  - 用途: marimo エディタで `notebooks/eda.py` を開く
  - 使い方: `mise run nb-serve -- [options]`
  - 主なオプション:
    - `--agent {claude|gemini}` marimo のエージェントブリッジを起動（任意）
    - `--agent-port <port>` エージェントのポート
  - 環境変数:
    - `MiseMarimoPort` エディタのポート（既定: 2718）

- train
  - 用途: ベースライン学習パイプラインを実行（XGBoost/PyTorch スケルトン）
  - 使い方: `mise run train`

- kaggle-submit
  - 用途: `submission.csv` 等を検証して提出
  - 使い方: `mise run kaggle-submit [options]`
  - 主なオプション:
    - `--slug <slug>` 競技スラッグ（プロジェクトから推測できない場合に指定）
    - `--file <path>` 提出ファイル（デフォルト: `submission.csv`）
    - `--message <msg>` 送信メッセージ
    - `--project <dir>` 対象プロジェクト

## ディレクトリ/生成物の概要（雛形）

- `configs/` 設定（`config.yaml`, `logging.yaml`）
- `data/` データ階層（`raw/`, `interim/`, `processed/`, `external/`）
- `notebooks/` marimo ノート（`eda.py`, `train.py`）
- `src/` ヘルパー/モデル実装（`data.py`, `features.py`, `models.py`, `viz.py`, `paths.py`）
- `runs/` 学習成果物（モデル/メトリクス等）
- `logs/` タスクや初期化のログ
- `.env.example` → `.env` にコピーして秘密情報を設定可能
- `.envrc` direnv 設定（自動で `.venv`/`.env` を有効化）

## Kaggle 認証

- 環境変数を推奨: `KAGGLE_USERNAME`, `KAGGLE_KEY`
- または `~/.kaggle/kaggle.json`（権限は 0600）
- スクリプトは権限の調整を自動で試みます。

## ヒント/トラブルシュート

- 依存同期: `uv sync`（ネットワークがない環境では後で再実行）
- 追加パッケージ: `uv add <package>`
- GPU について:
  - CUDA/ROCm を自動検出。うまく入らない場合は CPU 版にフォールバックします。
- うまく動かないときは `logs/` の最新ログを確認してください。
