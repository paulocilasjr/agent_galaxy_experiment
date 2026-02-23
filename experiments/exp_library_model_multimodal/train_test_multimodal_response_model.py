#!/usr/bin/env python3
"""Train/test a multimodal model (tabular + CD3/CD8 image features) for target prediction."""

from __future__ import annotations

import argparse
import io
import json
import pickle
import re
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
from sklearn.ensemble import RandomForestClassifier
from sklearn.impute import SimpleImputer
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
        choices=["metadata_fast", "pixels"],
        default="metadata_fast",
        help=(
            "Image feature mode: 'metadata_fast' uses ZIP-entry metadata only "
            "(fast); 'pixels' reads/decompresses image bytes (slow/heavy)."
        ),
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


def image_features_from_zipinfo(image_name: str, info: zipfile.ZipInfo) -> np.ndarray:
    # Lightweight image modality features derived from ZIP metadata + filename structure.
    size_mb = float(info.file_size) / (1024.0 * 1024.0)
    comp_mb = float(info.compress_size) / (1024.0 * 1024.0)
    comp_ratio = float(info.compress_size) / max(float(info.file_size), 1.0)
    crc_norm = float(info.CRC & 0xFFFFFFFF) / float(2**32)
    name_len = float(len(image_name))
    digit_count = float(sum(ch.isdigit() for ch in image_name))

    is_cd3 = 1.0 if "_CD3_" in image_name else 0.0
    is_cd8 = 1.0 if "_CD8_" in image_name else 0.0

    block = x = y = patient = 0.0
    m = re.search(r"block(\d+)_x(\d+)_y(\d+)_patient(\d+)", image_name, flags=re.IGNORECASE)
    if m:
        block = float(m.group(1))
        x = float(m.group(2))
        y = float(m.group(3))
        patient = float(m.group(4))

    year, month, day, hour, minute, second = info.date_time
    year_norm = float(year - 2000)
    month_norm = float(month)
    day_norm = float(day)
    hour_norm = float(hour)
    minute_norm = float(minute)
    second_norm = float(second)

    return np.array(
        [
            size_mb,
            comp_mb,
            comp_ratio,
            crc_norm,
            name_len,
            digit_count,
            block,
            x,
            y,
            patient,
            is_cd3,
            is_cd8,
            year_norm,
            month_norm,
            day_norm,
            hour_norm,
            minute_norm,
            second_norm,
        ],
        dtype=np.float32,
    )


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
    feature_cache_path = args.data_dir / f"image_feature_cache_{args.image_feature_mode}.pkl"

    download_if_needed(TRAIN_URL, train_csv, force=args.force_redownload)
    download_if_needed(TEST_URL, test_csv, force=args.force_redownload)

    train_df = pd.read_csv(train_csv)
    test_df = pd.read_csv(test_csv)

    required_cols = [args.target_col, args.cd3_col, args.cd8_col]
    ensure_required_columns(train_df, required_cols, "train_df")
    ensure_required_columns(test_df, required_cols, "test_df")

    y_train = train_df[args.target_col].astype(int).to_numpy()
    y_test = test_df[args.target_col].astype(int).to_numpy()

    excluded = {
        args.target_col,
        args.cd3_col,
        args.cd8_col,
        "patient_id",
        "split",
        "icd_codes",
    }
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
        print(
            f"[images] Need to build features for {len(missing_images)} images from remote ZIP "
            f"(mode={args.image_feature_mode})"
        )
        with HTTPRangeReader(IMAGE_ZIP_URL) as reader:
            with zipfile.ZipFile(reader) as zip_file:
                basename_lookup = build_basename_lookup(zip_file)
                unresolved = [name for name in missing_images if name not in basename_lookup]
                if unresolved:
                    if args.image_feature_mode == "pixels":
                        feature_dim = 13 + int(args.hist_bins)
                    else:
                        feature_dim = 18
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
                    if args.image_feature_mode == "pixels":
                        image_bytes = zip_file.read(member)
                        image_feature_cache[basename] = image_features_from_bytes(
                            image_bytes=image_bytes,
                            image_size=args.image_size,
                            hist_bins=args.hist_bins,
                        )
                    else:
                        info = zip_file.getinfo(member)
                        image_feature_cache[basename] = image_features_from_zipinfo(
                            image_name=basename,
                            info=info,
                        )
                    if idx % 100 == 0 or idx == len(missing_images):
                        print(f"[images] Processed {idx}/{len(missing_images)}")
        with feature_cache_path.open("wb") as fh:
            pickle.dump(image_feature_cache, fh)
        print(f"[cache] Saved image feature cache to {feature_cache_path}")
    else:
        print("[images] All required image features already cached")

    def assemble_image_matrix(df: pd.DataFrame) -> np.ndarray:
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

    x_img_train = assemble_image_matrix(train_df)
    x_img_test = assemble_image_matrix(test_df)
    x_train = np.hstack([x_tab_train, x_img_train]).astype(np.float32)
    x_test = np.hstack([x_tab_test, x_img_test]).astype(np.float32)
    print(f"[data] Multimodal train matrix: {x_train.shape}, test matrix: {x_test.shape}")

    imputer = SimpleImputer(strategy="median")
    x_train_imp = imputer.fit_transform(x_train)
    x_test_imp = imputer.transform(x_test)

    model = RandomForestClassifier(
        n_estimators=600,
        min_samples_leaf=2,
        random_state=42,
        n_jobs=-1,
        class_weight="balanced_subsample",
    )
    model.fit(x_train_imp, y_train)

    p_train = model.predict_proba(x_train_imp)[:, 1]
    p_test = model.predict_proba(x_test_imp)[:, 1]

    train_metrics = compute_split_metrics(y_train, p_train, args.threshold)
    test_metrics = compute_split_metrics(y_test, p_test, args.threshold)

    metrics = {
        "model": "RandomForestClassifier",
        "target_col": args.target_col,
        "train_rows": int(len(y_train)),
        "test_rows": int(len(y_test)),
        "tabular_feature_count": int(len(tabular_cols)),
        "image_feature_count_per_sample": int(x_img_train.shape[1]),
        "total_feature_count": int(x_train.shape[1]),
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
