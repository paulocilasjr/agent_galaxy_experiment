#!/usr/bin/env python3
"""Train/test a multimodal model (tabular + CD3/CD8 image features) for target prediction."""

from __future__ import annotations

import argparse
import io
import json
import pickle
import zipfile
from collections import OrderedDict
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
import pandas as pd
import requests
from PIL import Image
from scipy import sparse
from sklearn.ensemble import ExtraTreesClassifier
from sklearn.feature_extraction.text import TfidfVectorizer
from sklearn.impute import SimpleImputer
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import (
    accuracy_score,
    average_precision_score,
    balanced_accuracy_score,
    classification_report,
    confusion_matrix,
    f1_score,
    precision_recall_curve,
    precision_score,
    recall_score,
    roc_auc_score,
    roc_curve,
)
from sklearn.model_selection import StratifiedKFold


TRAIN_URL = "https://zenodo.org/records/17933596/files/HANCOCK_train_split.csv"
TEST_URL = "https://zenodo.org/records/17933596/files/HANCOCK_test_split.csv"
IMAGE_ZIP_URL = "https://zenodo.org/records/17727354/files/tma_cores_cd3_cd8_images.zip"


class HTTPRangeReader(io.RawIOBase):
    """Seekable file-like object over HTTP using Range requests with block caching."""

    def __init__(
        self,
        url: str,
        *,
        block_size: int = 4 * 1024 * 1024,
        max_blocks: int = 96,
        timeout: int = 300,
    ) -> None:
        self.url = url
        self.block_size = block_size
        self.max_blocks = max_blocks
        self.timeout = timeout
        self.pos = 0
        self._closed = False
        self.session = requests.Session()
        head = self.session.head(url, allow_redirects=True, timeout=timeout)
        if head.status_code >= 400:
            raise RuntimeError(f"HEAD failed for {url}: {head.status_code}")
        length = head.headers.get("content-length")
        if not length:
            # Fallback: request first byte and parse content-range.
            probe = self.session.get(url, headers={"Range": "bytes=0-0"}, timeout=timeout)
            if probe.status_code not in (200, 206):
                raise RuntimeError(f"Range probe failed for {url}: {probe.status_code}")
            crange = probe.headers.get("Content-Range", "")
            if "/" not in crange:
                raise RuntimeError("Could not determine remote size from Content-Range")
            length = crange.split("/")[-1]
        self.size = int(length)
        self.cache: OrderedDict[int, bytes] = OrderedDict()

    def close(self) -> None:
        if not self._closed:
            self.session.close()
            self._closed = True
        super().close()

    def readable(self) -> bool:
        return True

    def seekable(self) -> bool:
        return True

    def tell(self) -> int:
        return self.pos

    def seek(self, offset: int, whence: int = io.SEEK_SET) -> int:
        if whence == io.SEEK_SET:
            new_pos = offset
        elif whence == io.SEEK_CUR:
            new_pos = self.pos + offset
        elif whence == io.SEEK_END:
            new_pos = self.size + offset
        else:
            raise ValueError(f"Invalid whence: {whence}")
        if new_pos < 0:
            raise ValueError("Negative seek position")
        self.pos = new_pos
        return self.pos

    def _fetch_block(self, block_index: int) -> bytes:
        if block_index in self.cache:
            self.cache.move_to_end(block_index)
            return self.cache[block_index]
        start = block_index * self.block_size
        end = min(self.size - 1, start + self.block_size - 1)
        resp = self.session.get(
            self.url,
            headers={"Range": f"bytes={start}-{end}"},
            timeout=self.timeout,
        )
        if resp.status_code not in (200, 206):
            raise RuntimeError(
                f"Range request failed ({resp.status_code}) for block {block_index} [{start}-{end}]"
            )
        data = resp.content
        self.cache[block_index] = data
        if len(self.cache) > self.max_blocks:
            self.cache.popitem(last=False)
        return data

    def read(self, n: int = -1) -> bytes:
        if self._closed:
            return b""
        if self.pos >= self.size:
            return b""
        if n is None or n < 0:
            n = self.size - self.pos
        n = min(n, self.size - self.pos)
        remaining = n
        chunks: list[bytes] = []
        while remaining > 0:
            block_index = self.pos // self.block_size
            in_block_offset = self.pos % self.block_size
            block = self._fetch_block(block_index)
            take = min(remaining, len(block) - in_block_offset)
            chunks.append(block[in_block_offset : in_block_offset + take])
            self.pos += take
            remaining -= take
        return b"".join(chunks)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Train/test multimodal model on Hancock dataset.")
    parser.add_argument(
        "--data-dir",
        type=Path,
        default=Path("experiments/exp_library_model_multimodal/data"),
        help="Directory for CSV downloads and local caches.",
    )
    parser.add_argument(
        "--artifacts-dir",
        type=Path,
        default=Path("experiments/exp_library_model_multimodal/artifacts"),
        help="Directory for outputs (metrics, plots, predictions).",
    )
    parser.add_argument(
        "--target-col",
        type=str,
        default="target",
        help="Binary target column name.",
    )
    parser.add_argument(
        "--cd3-col",
        type=str,
        default="CD3_image_path",
        help="CD3 image path column.",
    )
    parser.add_argument(
        "--cd8-col",
        type=str,
        default="CD8_image_path",
        help="CD8 image path column.",
    )
    parser.add_argument(
        "--text-col",
        type=str,
        default="icd_codes",
        help="Free-text column used for text modality features.",
    )
    parser.add_argument(
        "--text-max-features",
        type=int,
        default=5000,
        help="Max TF-IDF vocabulary size.",
    )
    parser.add_argument(
        "--text-ngram-max",
        type=int,
        default=2,
        help="Maximum n-gram size for TF-IDF text features.",
    )
    parser.add_argument(
        "--image-size",
        type=int,
        default=96,
        help="Resize images to image_size x image_size before feature extraction.",
    )
    parser.add_argument(
        "--hist-bins",
        type=int,
        default=16,
        help="Histogram bins for image intensity features.",
    )
    parser.add_argument(
        "--threshold",
        type=float,
        default=0.5,
        help="Decision threshold for class label conversion.",
    )
    parser.add_argument(
        "--image-feature-mode",
        type=str,
        choices=["pixels", "patient_embeddings"],
        default="pixels",
        help=(
            "Image feature mode: 'pixels' reads raw image bytes; "
            "'patient_embeddings' loads patient-linked image embeddings."
        ),
    )
    parser.add_argument(
        "--patient-id-col",
        type=str,
        default="patient_id",
        help="Patient ID column used to link patient-level image embeddings.",
    )
    parser.add_argument(
        "--patient-embeddings-path",
        type=Path,
        default=None,
        help=(
            "CSV/TSV file with image embeddings linked by patient ID. "
            "Required when --image-feature-mode patient_embeddings."
        ),
    )
    parser.add_argument(
        "--embedding-col-prefix",
        type=str,
        default="img_emb_",
        help="Prefix for numeric embedding columns in --patient-embeddings-path.",
    )
    parser.add_argument(
        "--embedding-vector-col",
        type=str,
        default="image_embedding",
        help=(
            "Fallback embedding column containing serialized vectors (space/comma-separated "
            "or bracketed list) when prefixed embedding columns are not present."
        ),
    )
    parser.add_argument(
        "--allow-missing-patient-embeddings",
        action="store_true",
        help="Allow missing patient IDs in embedding file and fill zeros.",
    )
    parser.add_argument(
        "--model-strategy",
        type=str,
        choices=["tri_logistic", "stacked_et_text"],
        default="stacked_et_text",
        help=(
            "Model strategy: 'tri_logistic' trains one logistic model on concatenated "
            "numeric+image+text; 'stacked_et_text' stacks an ExtraTrees numeric+image "
            "base model with a text logistic base model."
        ),
    )
    parser.add_argument(
        "--stack-cv-folds",
        type=int,
        default=5,
        help="Number of CV folds used to build out-of-fold stack features.",
    )
    parser.add_argument(
        "--et-estimators",
        type=int,
        default=1500,
        help="Number of trees for the ExtraTrees base model in stacked strategy.",
    )
    parser.add_argument(
        "--et-max-features",
        type=str,
        default="sqrt",
        help="ExtraTrees max_features setting (e.g., 'sqrt', 'log2', or float string).",
    )
    parser.add_argument(
        "--stack-text-analyzer",
        type=str,
        choices=["word", "char", "char_wb"],
        default="char_wb",
        help="Analyzer for text base model in stacked strategy.",
    )
    parser.add_argument(
        "--stack-text-ngram-min",
        type=int,
        default=3,
        help="Minimum n-gram size for stacked strategy text vectorizer.",
    )
    parser.add_argument(
        "--stack-text-ngram-max",
        type=int,
        default=5,
        help="Maximum n-gram size for stacked strategy text vectorizer.",
    )
    parser.add_argument(
        "--stack-text-max-features",
        type=int,
        default=5000,
        help="Max TF-IDF features for stacked strategy text vectorizer.",
    )
    parser.add_argument(
        "--force-redownload",
        action="store_true",
        help="Re-download train/test CSV even if present.",
    )
    return parser.parse_args()


def download_if_needed(url: str, destination: Path, force: bool = False) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    if destination.exists() and not force:
        print(f"[download] Reusing existing file: {destination}")
        return
    print(f"[download] Downloading {url} -> {destination}")
    with requests.get(url, stream=True, timeout=300) as resp:
        resp.raise_for_status()
        with destination.open("wb") as out:
            for chunk in resp.iter_content(chunk_size=1024 * 1024):
                if chunk:
                    out.write(chunk)


def image_features_from_bytes(image_bytes: bytes, image_size: int, hist_bins: int) -> np.ndarray:
    with Image.open(io.BytesIO(image_bytes)) as image:
        image = image.convert("L").resize((image_size, image_size))
        arr = np.asarray(image, dtype=np.float32) / 255.0

    flat = arr.ravel()
    pct = np.percentile(flat, [5, 25, 50, 75, 95]).astype(np.float32)

    gx = np.diff(arr, axis=1)
    gy = np.diff(arr, axis=0)
    grad = np.hypot(gx[:-1, :], gy[:, :-1]).astype(np.float32)

    lap = (
        arr[:-2, 1:-1]
        + arr[2:, 1:-1]
        + arr[1:-1, :-2]
        + arr[1:-1, 2:]
        - (4.0 * arr[1:-1, 1:-1])
    )

    hist, _ = np.histogram(flat, bins=hist_bins, range=(0.0, 1.0), density=False)
    hist = (hist.astype(np.float32) / float(flat.size)).astype(np.float32)

    stats = np.array(
        [
            float(flat.mean()),
            float(flat.std()),
            float(flat.min()),
            float(flat.max()),
            float(pct[0]),
            float(pct[1]),
            float(pct[2]),
            float(pct[3]),
            float(pct[4]),
            float(grad.mean()),
            float(grad.std()),
            float(np.percentile(grad, 90)),
            float(lap.var()),
        ],
        dtype=np.float32,
    )
    return np.concatenate([stats, hist]).astype(np.float32)


def normalize_patient_id(value: object) -> str:
    text = str(value).strip()
    if not text or text.lower() == "nan":
        raise ValueError(f"Invalid patient ID: {value!r}")
    if text.endswith(".0") and text[:-2].isdigit():
        return text[:-2]
    return text


def parse_embedding_vector(value: object) -> np.ndarray:
    if isinstance(value, np.ndarray):
        vector = value.astype(np.float32).ravel()
    elif isinstance(value, (list, tuple)):
        vector = np.asarray(value, dtype=np.float32).ravel()
    else:
        text = str(value).strip()
        if not text or text.lower() == "nan":
            raise ValueError(f"Invalid serialized embedding value: {value!r}")
        if text.startswith("[") and text.endswith("]"):
            text = text[1:-1]
        text = text.replace(",", " ")
        vector = np.fromstring(text, sep=" ", dtype=np.float32)
    if vector.size == 0:
        raise ValueError(f"Could not parse embedding vector from value: {value!r}")
    return vector.astype(np.float32)


def load_patient_embedding_map(
    path: Path,
    *,
    patient_id_col: str,
    embedding_col_prefix: str,
    embedding_vector_col: str,
) -> tuple[dict[str, np.ndarray], int]:
    if not path.exists():
        raise FileNotFoundError(f"Patient embedding file not found: {path}")

    suffix = path.suffix.lower()
    if suffix == ".csv":
        df = pd.read_csv(path)
    elif suffix in {".tsv", ".txt"}:
        df = pd.read_csv(path, sep="\t")
    else:
        raise ValueError(f"Unsupported embedding file format '{suffix}'. Use CSV or TSV.")

    if patient_id_col not in df.columns:
        raise ValueError(
            f"Embedding file {path} must contain patient ID column '{patient_id_col}'."
        )

    prefixed_columns = [c for c in df.columns if c.startswith(embedding_col_prefix)]
    if prefixed_columns:
        embedding_matrix = df[prefixed_columns].apply(pd.to_numeric, errors="coerce").to_numpy(
            dtype=np.float32
        )
        embedding_matrix = np.nan_to_num(
            embedding_matrix, nan=0.0, posinf=0.0, neginf=0.0
        ).astype(np.float32)
    elif embedding_vector_col in df.columns:
        vectors = [parse_embedding_vector(v) for v in df[embedding_vector_col].tolist()]
        embedding_dim = vectors[0].shape[0]
        for idx, vec in enumerate(vectors):
            if vec.shape[0] != embedding_dim:
                raise ValueError(
                    f"Embedding vector length mismatch at row {idx}: "
                    f"expected {embedding_dim}, got {vec.shape[0]}"
                )
        embedding_matrix = np.vstack(vectors).astype(np.float32)
    else:
        raise ValueError(
            f"Embedding file {path} must contain either columns prefixed by "
            f"'{embedding_col_prefix}' or vector column '{embedding_vector_col}'."
        )

    patient_ids = [normalize_patient_id(v) for v in df[patient_id_col].tolist()]
    grouped_embeddings: dict[str, list[np.ndarray]] = {}
    for patient_id, vector in zip(patient_ids, embedding_matrix):
        grouped_embeddings.setdefault(patient_id, []).append(vector)

    if not grouped_embeddings:
        raise ValueError(f"No patient embeddings loaded from: {path}")

    embedding_map = {
        patient_id: np.mean(np.vstack(vectors), axis=0).astype(np.float32)
        for patient_id, vectors in grouped_embeddings.items()
    }
    embedding_dim = int(next(iter(embedding_map.values())).shape[0])
    return embedding_map, embedding_dim


def assemble_patient_embedding_matrix(
    df: pd.DataFrame,
    *,
    patient_id_col: str,
    embedding_map: dict[str, np.ndarray],
    embedding_dim: int,
    allow_missing: bool,
) -> np.ndarray:
    rows: list[np.ndarray] = []
    missing: list[str] = []
    default_vector = np.zeros(embedding_dim, dtype=np.float32)

    for value in df[patient_id_col].tolist():
        patient_id = normalize_patient_id(value)
        vector = embedding_map.get(patient_id)
        if vector is None:
            missing.append(patient_id)
            rows.append(default_vector.copy())
        else:
            rows.append(vector)

    if missing and not allow_missing:
        unique_missing = sorted(set(missing))
        examples = unique_missing[:10]
        raise ValueError(
            f"Missing embeddings for {len(unique_missing)} patient IDs "
            f"(examples: {examples})."
        )
    if missing:
        unique_missing = sorted(set(missing))
        print(
            f"[embeddings] Warning: missing embeddings for {len(unique_missing)} patients "
            f"(examples: {unique_missing[:10]}). Using zero-vector placeholders."
        )

    return np.vstack(rows).astype(np.float32)


def build_basename_lookup(zip_file: zipfile.ZipFile) -> dict[str, str]:
    lookup: dict[str, str] = {}
    for info in zip_file.infolist():
        if info.is_dir():
            continue
        base = Path(info.filename).name
        if base not in lookup:
            lookup[base] = info.filename
    return lookup


def ensure_required_columns(df: pd.DataFrame, cols: list[str], name: str) -> None:
    missing = [c for c in cols if c not in df.columns]
    if missing:
        raise ValueError(f"{name} missing required columns: {missing}")


def normalize_image_ref(value: object) -> str:
    text = str(value).strip()
    if not text or text.lower() == "nan":
        raise ValueError(f"Invalid image reference value: {value!r}")
    return Path(text).name


def parse_et_max_features(value: str) -> str | float:
    if value in {"sqrt", "log2"}:
        return value
    try:
        parsed = float(value)
    except ValueError as exc:
        raise ValueError(
            f"Unsupported --et-max-features value '{value}'. Use sqrt/log2 or numeric float."
        ) from exc
    if parsed <= 0.0:
        raise ValueError("--et-max-features numeric value must be > 0")
    return parsed


def build_text_features(
    train_text: list[str],
    test_text: list[str],
    *,
    analyzer: str,
    ngram_min: int,
    ngram_max: int,
    max_features: int,
) -> tuple[sparse.csr_matrix, sparse.csr_matrix, TfidfVectorizer]:
    low = max(1, int(ngram_min))
    high = max(low, int(ngram_max))
    vectorizer_kwargs: dict[str, object] = {
        "lowercase": True,
        "strip_accents": "unicode",
        "analyzer": analyzer,
        "ngram_range": (low, high),
        "max_features": int(max_features),
    }
    if analyzer == "word":
        vectorizer_kwargs["token_pattern"] = r"(?u)\b\w+\b"

    vectorizer = TfidfVectorizer(**vectorizer_kwargs)
    x_train = vectorizer.fit_transform(train_text).tocsr().astype(np.float32)
    x_test = vectorizer.transform(test_text).tocsr().astype(np.float32)
    return x_train, x_test, vectorizer


def compute_split_metrics(
    y_true: np.ndarray,
    y_prob: np.ndarray,
    threshold: float,
) -> dict:
    y_pred = (y_prob >= threshold).astype(int)
    return {
        "roc_auc": float(roc_auc_score(y_true, y_prob)),
        "pr_auc": float(average_precision_score(y_true, y_prob)),
        "accuracy": float(accuracy_score(y_true, y_pred)),
        "balanced_accuracy": float(balanced_accuracy_score(y_true, y_pred)),
        "precision": float(precision_score(y_true, y_pred, zero_division=0)),
        "recall": float(recall_score(y_true, y_pred, zero_division=0)),
        "f1": float(f1_score(y_true, y_pred, zero_division=0)),
        "confusion_matrix": confusion_matrix(y_true, y_pred).tolist(),
        "classification_report": classification_report(
            y_true, y_pred, output_dict=True, zero_division=0
        ),
    }


def plot_roc_curves(
    y_train: np.ndarray,
    p_train: np.ndarray,
    y_test: np.ndarray,
    p_test: np.ndarray,
    out_path: Path,
) -> None:
    fpr_tr, tpr_tr, _ = roc_curve(y_train, p_train)
    fpr_te, tpr_te, _ = roc_curve(y_test, p_test)
    auc_tr = roc_auc_score(y_train, p_train)
    auc_te = roc_auc_score(y_test, p_test)

    plt.figure(figsize=(8, 6))
    plt.plot(fpr_tr, tpr_tr, label=f"Train ROC-AUC = {auc_tr:.4f}", linewidth=2)
    plt.plot(fpr_te, tpr_te, label=f"Test ROC-AUC = {auc_te:.4f}", linewidth=2)
    plt.plot([0, 1], [0, 1], linestyle="--", color="gray", linewidth=1)
    plt.xlabel("False Positive Rate")
    plt.ylabel("True Positive Rate")
    plt.title("Multimodal Model ROC Curve")
    plt.legend(loc="lower right")
    plt.tight_layout()
    plt.savefig(out_path, dpi=180)
    plt.close()


def plot_pr_curves(
    y_train: np.ndarray,
    p_train: np.ndarray,
    y_test: np.ndarray,
    p_test: np.ndarray,
    out_path: Path,
) -> None:
    precision_tr, recall_tr, _ = precision_recall_curve(y_train, p_train)
    precision_te, recall_te, _ = precision_recall_curve(y_test, p_test)
    ap_tr = average_precision_score(y_train, p_train)
    ap_te = average_precision_score(y_test, p_test)

    plt.figure(figsize=(8, 6))
    plt.plot(recall_tr, precision_tr, label=f"Train PR-AUC = {ap_tr:.4f}", linewidth=2)
    plt.plot(recall_te, precision_te, label=f"Test PR-AUC = {ap_te:.4f}", linewidth=2)
    plt.xlabel("Recall")
    plt.ylabel("Precision")
    plt.title("Multimodal Model Precision-Recall Curve")
    plt.legend(loc="lower left")
    plt.tight_layout()
    plt.savefig(out_path, dpi=180)
    plt.close()


def main() -> None:
    args = parse_args()
    args.data_dir.mkdir(parents=True, exist_ok=True)
    args.artifacts_dir.mkdir(parents=True, exist_ok=True)

    train_csv = args.data_dir / "HANCOCK_train_split.csv"
    test_csv = args.data_dir / "HANCOCK_test_split.csv"

    download_if_needed(TRAIN_URL, train_csv, force=args.force_redownload)
    download_if_needed(TEST_URL, test_csv, force=args.force_redownload)

    train_df = pd.read_csv(train_csv)
    test_df = pd.read_csv(test_csv)

    required_cols = [args.target_col, args.text_col]
    if args.image_feature_mode == "pixels":
        required_cols.extend([args.cd3_col, args.cd8_col])
    elif args.image_feature_mode == "patient_embeddings":
        required_cols.append(args.patient_id_col)
    else:
        raise ValueError(f"Unsupported image feature mode: {args.image_feature_mode}")
    ensure_required_columns(train_df, required_cols, "train_df")
    ensure_required_columns(test_df, required_cols, "test_df")

    y_train = train_df[args.target_col].astype(int).to_numpy()
    y_test = test_df[args.target_col].astype(int).to_numpy()

    excluded = {
        args.target_col,
        args.text_col,
        "split",
    }
    for optional_col in [args.cd3_col, args.cd8_col, args.patient_id_col]:
        if optional_col in train_df.columns:
            excluded.add(optional_col)
    tabular_cols = [
        c
        for c in train_df.columns
        if c in test_df.columns and c not in excluded
    ]
    train_tab = train_df[tabular_cols].apply(pd.to_numeric, errors="coerce")
    test_tab = test_df[tabular_cols].apply(pd.to_numeric, errors="coerce")
    x_tab_train = train_tab.to_numpy(dtype=np.float32)
    x_tab_test = test_tab.to_numpy(dtype=np.float32)
    print(f"[data] Tabular features: {len(tabular_cols)} columns")

    if args.image_feature_mode == "pixels":
        feature_cache_path = args.data_dir / "image_feature_cache_pixels.pkl"
        required_images = set(train_df[args.cd3_col].map(normalize_image_ref))
        required_images |= set(train_df[args.cd8_col].map(normalize_image_ref))
        required_images |= set(test_df[args.cd3_col].map(normalize_image_ref))
        required_images |= set(test_df[args.cd8_col].map(normalize_image_ref))
        print(f"[data] Unique required images from CSVs: {len(required_images)}")

        if feature_cache_path.exists():
            with feature_cache_path.open("rb") as fh:
                image_feature_cache: dict[str, np.ndarray] = pickle.load(fh)
            print(f"[cache] Loaded cached image features: {len(image_feature_cache)}")
        else:
            image_feature_cache = {}

        missing_images = sorted([name for name in required_images if name not in image_feature_cache])
        if missing_images:
            print(f"[images] Need to build pixel features for {len(missing_images)} images from remote ZIP")
            with HTTPRangeReader(IMAGE_ZIP_URL) as reader:
                with zipfile.ZipFile(reader) as zip_file:
                    basename_lookup = build_basename_lookup(zip_file)
                    unresolved = [name for name in missing_images if name not in basename_lookup]
                    if unresolved:
                        feature_dim = 13 + int(args.hist_bins)
                        placeholder = np.zeros(feature_dim, dtype=np.float32)
                        print(
                            f"[images] Warning: {len(unresolved)} image names not present in ZIP "
                            f"(examples: {unresolved[:5]}). Using zero-feature placeholders."
                        )
                        for name in unresolved:
                            image_feature_cache[name] = placeholder.copy()
                        missing_images = [name for name in missing_images if name in basename_lookup]
                    for idx, basename in enumerate(missing_images, start=1):
                        member = basename_lookup[basename]
                        image_bytes = zip_file.read(member)
                        image_feature_cache[basename] = image_features_from_bytes(
                            image_bytes=image_bytes,
                            image_size=args.image_size,
                            hist_bins=args.hist_bins,
                        )
                        if idx % 100 == 0 or idx == len(missing_images):
                            print(f"[images] Processed {idx}/{len(missing_images)}")
            with feature_cache_path.open("wb") as fh:
                pickle.dump(image_feature_cache, fh)
            print(f"[cache] Saved image feature cache to {feature_cache_path}")
        else:
            print("[images] All required image features already cached")

        def assemble_pixel_image_matrix(df: pd.DataFrame) -> np.ndarray:
            rows = []
            for _, row in df.iterrows():
                cd3_name = normalize_image_ref(row[args.cd3_col])
                cd8_name = normalize_image_ref(row[args.cd8_col])
                f_cd3 = image_feature_cache[cd3_name]
                f_cd8 = image_feature_cache[cd8_name]
                merged = np.concatenate([f_cd3, f_cd8, f_cd3 - f_cd8, np.abs(f_cd3 - f_cd8)]).astype(
                    np.float32
                )
                rows.append(merged)
            return np.vstack(rows)

        x_img_train = assemble_pixel_image_matrix(train_df)
        x_img_test = assemble_pixel_image_matrix(test_df)
        image_input_description = "raw_pixels_from_zip"
    else:
        if args.patient_embeddings_path is None:
            raise ValueError(
                "--patient-embeddings-path is required when --image-feature-mode patient_embeddings"
            )
        embedding_map, embedding_dim = load_patient_embedding_map(
            args.patient_embeddings_path,
            patient_id_col=args.patient_id_col,
            embedding_col_prefix=args.embedding_col_prefix,
            embedding_vector_col=args.embedding_vector_col,
        )
        print(
            f"[embeddings] Loaded {len(embedding_map)} patient embeddings with dimension {embedding_dim} "
            f"from {args.patient_embeddings_path}"
        )
        x_img_train = assemble_patient_embedding_matrix(
            train_df,
            patient_id_col=args.patient_id_col,
            embedding_map=embedding_map,
            embedding_dim=embedding_dim,
            allow_missing=args.allow_missing_patient_embeddings,
        )
        x_img_test = assemble_patient_embedding_matrix(
            test_df,
            patient_id_col=args.patient_id_col,
            embedding_map=embedding_map,
            embedding_dim=embedding_dim,
            allow_missing=args.allow_missing_patient_embeddings,
        )
        image_input_description = f"patient_embeddings::{args.patient_embeddings_path}"

    x_num_train = np.hstack([x_tab_train, x_img_train]).astype(np.float32)
    x_num_test = np.hstack([x_tab_test, x_img_test]).astype(np.float32)

    text_train = train_df[args.text_col].fillna("").astype(str).tolist()
    text_test = test_df[args.text_col].fillna("").astype(str).tolist()
    print(
        f"[data] Numeric multimodal block: train {x_num_train.shape}, test {x_num_test.shape} "
        f"(image mode={args.image_feature_mode})"
    )

    imputer = SimpleImputer(strategy="median")
    x_num_train_imp = imputer.fit_transform(x_num_train)
    x_num_test_imp = imputer.transform(x_num_test)

    stack_feature_count = 0
    strategy_details: dict[str, object] = {}

    if args.model_strategy == "tri_logistic":
        x_text_train, x_text_test, _ = build_text_features(
            train_text=text_train,
            test_text=text_test,
            analyzer="word",
            ngram_min=1,
            ngram_max=args.text_ngram_max,
            max_features=args.text_max_features,
        )
        print(f"[data] Text TF-IDF block: train {x_text_train.shape}, test {x_text_test.shape}")

        x_train = sparse.hstack(
            [
                sparse.csr_matrix(x_num_train_imp.astype(np.float32)),
                x_text_train,
            ],
            format="csr",
        )
        x_test = sparse.hstack(
            [
                sparse.csr_matrix(x_num_test_imp.astype(np.float32)),
                x_text_test,
            ],
            format="csr",
        )
        print(f"[data] Tri-modal matrix: train {x_train.shape}, test {x_test.shape}")

        model = LogisticRegression(
            solver="liblinear",
            C=1.0,
            max_iter=2000,
            class_weight="balanced",
            random_state=42,
        )
        model.fit(x_train, y_train)

        p_train = model.predict_proba(x_train)[:, 1]
        p_test = model.predict_proba(x_test)[:, 1]
        model_name = "LogisticRegressionTriModal"
        total_feature_count = int(x_train.shape[1])
        strategy_details = {
            "text_analyzer": "word",
            "text_ngram_min": 1,
            "text_ngram_max": int(args.text_ngram_max),
            "text_max_features": int(args.text_max_features),
        }
    elif args.model_strategy == "stacked_et_text":
        x_text_train, x_text_test, _ = build_text_features(
            train_text=text_train,
            test_text=text_test,
            analyzer=args.stack_text_analyzer,
            ngram_min=args.stack_text_ngram_min,
            ngram_max=args.stack_text_ngram_max,
            max_features=args.stack_text_max_features,
        )
        print(f"[data] Text TF-IDF block: train {x_text_train.shape}, test {x_text_test.shape}")

        folds = max(2, int(args.stack_cv_folds))
        et_max_features = parse_et_max_features(args.et_max_features)
        splitter = StratifiedKFold(n_splits=folds, shuffle=True, random_state=42)

        oof_num_img = np.zeros(len(y_train), dtype=np.float32)
        oof_text = np.zeros(len(y_train), dtype=np.float32)
        test_num_img_folds: list[np.ndarray] = []
        test_text_folds: list[np.ndarray] = []

        for fold_idx, (idx_fit, idx_val) in enumerate(splitter.split(x_num_train_imp, y_train), start=1):
            print(f"[stack] Fold {fold_idx}/{folds}")
            model_num_img = ExtraTreesClassifier(
                n_estimators=int(args.et_estimators),
                max_features=et_max_features,
                class_weight="balanced",
                random_state=100 + fold_idx,
                n_jobs=-1,
            )
            model_num_img.fit(x_num_train_imp[idx_fit], y_train[idx_fit])
            oof_num_img[idx_val] = model_num_img.predict_proba(x_num_train_imp[idx_val])[:, 1]
            test_num_img_folds.append(model_num_img.predict_proba(x_num_test_imp)[:, 1])

            model_text = LogisticRegression(
                solver="liblinear",
                C=1.0,
                max_iter=2000,
                class_weight="balanced",
                random_state=200 + fold_idx,
            )
            model_text.fit(x_text_train[idx_fit], y_train[idx_fit])
            oof_text[idx_val] = model_text.predict_proba(x_text_train[idx_val])[:, 1]
            test_text_folds.append(model_text.predict_proba(x_text_test)[:, 1])

        x_stack_train = np.column_stack([oof_num_img, oof_text]).astype(np.float32)
        x_stack_test = np.column_stack(
            [
                np.mean(np.vstack(test_num_img_folds), axis=0),
                np.mean(np.vstack(test_text_folds), axis=0),
            ]
        ).astype(np.float32)
        stack_feature_count = int(x_stack_train.shape[1])

        model = LogisticRegression(
            solver="liblinear",
            C=1.0,
            max_iter=2000,
            class_weight="balanced",
            random_state=42,
        )
        model.fit(x_stack_train, y_train)

        p_train = model.predict_proba(x_stack_train)[:, 1]
        p_test = model.predict_proba(x_stack_test)[:, 1]
        model_name = "StackedExtraTreesTextLR"
        total_feature_count = int(x_num_train_imp.shape[1] + x_text_train.shape[1])
        strategy_details = {
            "stack_cv_folds": folds,
            "et_estimators": int(args.et_estimators),
            "et_max_features": args.et_max_features,
            "text_analyzer": args.stack_text_analyzer,
            "text_ngram_min": int(args.stack_text_ngram_min),
            "text_ngram_max": int(args.stack_text_ngram_max),
            "text_max_features": int(args.stack_text_max_features),
        }
    else:
        raise ValueError(f"Unsupported model strategy: {args.model_strategy}")

    strategy_details["image_feature_mode"] = args.image_feature_mode
    strategy_details["image_input"] = image_input_description
    if args.image_feature_mode == "patient_embeddings":
        strategy_details["patient_id_col"] = args.patient_id_col
        strategy_details["patient_embeddings_path"] = str(args.patient_embeddings_path)

    train_metrics = compute_split_metrics(y_train, p_train, args.threshold)
    test_metrics = compute_split_metrics(y_test, p_test, args.threshold)

    metrics = {
        "model": model_name,
        "model_strategy": args.model_strategy,
        "image_feature_mode": args.image_feature_mode,
        "target_col": args.target_col,
        "text_col": args.text_col,
        "train_rows": int(len(y_train)),
        "test_rows": int(len(y_test)),
        "tabular_feature_count": int(len(tabular_cols)),
        "image_feature_count_per_sample": int(x_img_train.shape[1]),
        "text_feature_count": int(x_text_train.shape[1]),
        "total_feature_count": total_feature_count,
        "stack_feature_count": stack_feature_count,
        "strategy_details": strategy_details,
        "threshold": float(args.threshold),
        "train": train_metrics,
        "test": test_metrics,
        "train_positive_rate": float(y_train.mean()),
        "test_positive_rate": float(y_test.mean()),
    }

    metrics_path = args.artifacts_dir / "metrics.json"
    metrics_path.write_text(json.dumps(metrics, indent=2, sort_keys=True))

    plot_roc_curves(
        y_train=y_train,
        p_train=p_train,
        y_test=y_test,
        p_test=p_test,
        out_path=args.artifacts_dir / "roc_curve_train_test.png",
    )
    plot_pr_curves(
        y_train=y_train,
        p_train=p_train,
        y_test=y_test,
        p_test=p_test,
        out_path=args.artifacts_dir / "pr_curve_train_test.png",
    )

    pd.DataFrame(
        {"y_true": y_train, "y_prob": p_train, "y_pred": (p_train >= args.threshold).astype(int)}
    ).to_csv(args.artifacts_dir / "train_predictions.tsv", sep="\t", index=False)
    pd.DataFrame(
        {"y_true": y_test, "y_prob": p_test, "y_pred": (p_test >= args.threshold).astype(int)}
    ).to_csv(args.artifacts_dir / "test_predictions.tsv", sep="\t", index=False)

    print("")
    print("Multimodal training and evaluation complete.")
    print(f"Train ROC-AUC: {metrics['train']['roc_auc']:.6f}")
    print(f"Test ROC-AUC:  {metrics['test']['roc_auc']:.6f}")
    print(f"Train PR-AUC:  {metrics['train']['pr_auc']:.6f}")
    print(f"Test PR-AUC:   {metrics['test']['pr_auc']:.6f}")
    print(f"Artifacts: {args.artifacts_dir}")


if __name__ == "__main__":
    main()
