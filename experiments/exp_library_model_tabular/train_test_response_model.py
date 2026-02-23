#!/usr/bin/env python3
"""Train and evaluate a response prediction model on provided train/test TSV files."""

from __future__ import annotations

import argparse
import json
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
import pandas as pd
from sklearn.impute import SimpleImputer
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import (
    accuracy_score,
    average_precision_score,
    balanced_accuracy_score,
    brier_score_loss,
    classification_report,
    confusion_matrix,
    f1_score,
    matthews_corrcoef,
    precision_recall_curve,
    precision_score,
    recall_score,
    roc_auc_score,
    roc_curve,
)
from sklearn.pipeline import Pipeline
from sklearn.preprocessing import StandardScaler


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Train on Chowell train split and evaluate on test split."
    )
    parser.add_argument(
        "--train",
        type=Path,
        default=Path("experiments/exp_library_model_tabular/Chowell_train_Response.tsv"),
        help="Training TSV path.",
    )
    parser.add_argument(
        "--test",
        type=Path,
        default=Path("experiments/exp_library_model_tabular/Chowell_test_Response.tsv"),
        help="Test TSV path.",
    )
    parser.add_argument(
        "--target",
        type=str,
        default="Response",
        help="Target column name.",
    )
    parser.add_argument(
        "--threshold",
        type=float,
        default=0.5,
        help="Decision threshold for converting probability to class label.",
    )
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=Path("experiments/exp_library_model_tabular/artifacts"),
        help="Directory for metrics, plots, and predictions.",
    )
    return parser.parse_args()


def load_split(path: Path, target: str) -> tuple[pd.DataFrame, pd.Series]:
    df = pd.read_csv(path, sep="\t")
    if target not in df.columns:
        raise ValueError(f"Target column '{target}' not found in {path}")
    x = df.drop(columns=[target])
    y = df[target].astype(int)
    return x, y


def build_model() -> Pipeline:
    return Pipeline(
        steps=[
            ("imputer", SimpleImputer(strategy="median")),
            ("scaler", StandardScaler()),
            (
                "classifier",
                LogisticRegression(
                    max_iter=2000,
                    solver="liblinear",
                    random_state=42,
                ),
            ),
        ]
    )


def compute_metrics(y_true: pd.Series, y_prob: pd.Series, y_pred: pd.Series) -> dict:
    metrics = {
        "roc_auc": float(roc_auc_score(y_true, y_prob)),
        "pr_auc": float(average_precision_score(y_true, y_prob)),
        "accuracy": float(accuracy_score(y_true, y_pred)),
        "balanced_accuracy": float(balanced_accuracy_score(y_true, y_pred)),
        "precision": float(precision_score(y_true, y_pred, zero_division=0)),
        "recall": float(recall_score(y_true, y_pred, zero_division=0)),
        "f1": float(f1_score(y_true, y_pred, zero_division=0)),
        "mcc": float(matthews_corrcoef(y_true, y_pred)),
        "brier_score": float(brier_score_loss(y_true, y_prob)),
        "confusion_matrix": confusion_matrix(y_true, y_pred).tolist(),
        "classification_report": classification_report(
            y_true, y_pred, output_dict=True, zero_division=0
        ),
    }
    return metrics


def save_curves(
    y_true: pd.Series,
    y_prob: pd.Series,
    outdir: Path,
    roc_auc: float,
    pr_auc: float,
) -> None:
    fpr, tpr, _ = roc_curve(y_true, y_prob)
    precision, recall, _ = precision_recall_curve(y_true, y_prob)

    plt.figure(figsize=(7, 6))
    plt.plot(fpr, tpr, label=f"ROC AUC = {roc_auc:.4f}", linewidth=2)
    plt.plot([0, 1], [0, 1], linestyle="--", linewidth=1, color="gray")
    plt.xlabel("False Positive Rate")
    plt.ylabel("True Positive Rate")
    plt.title("ROC Curve")
    plt.legend(loc="lower right")
    plt.tight_layout()
    plt.savefig(outdir / "roc_curve.png", dpi=160)
    plt.close()

    plt.figure(figsize=(7, 6))
    plt.plot(recall, precision, label=f"PR AUC = {pr_auc:.4f}", linewidth=2)
    plt.xlabel("Recall")
    plt.ylabel("Precision")
    plt.title("Precision-Recall Curve")
    plt.legend(loc="lower left")
    plt.tight_layout()
    plt.savefig(outdir / "pr_curve.png", dpi=160)
    plt.close()


def main() -> None:
    args = parse_args()
    args.output_dir.mkdir(parents=True, exist_ok=True)

    x_train, y_train = load_split(args.train, args.target)
    x_test, y_test = load_split(args.test, args.target)

    missing_in_test = [c for c in x_train.columns if c not in x_test.columns]
    if missing_in_test:
        raise ValueError(f"Test split is missing columns: {missing_in_test}")

    x_test = x_test[x_train.columns]

    model = build_model()
    model.fit(x_train, y_train)

    y_prob = pd.Series(model.predict_proba(x_test)[:, 1], index=y_test.index, name="y_prob")
    y_pred = (y_prob >= args.threshold).astype(int).rename("y_pred")

    metrics = compute_metrics(y_test, y_prob, y_pred)
    metrics.update(
        {
            "train_path": str(args.train),
            "test_path": str(args.test),
            "target": args.target,
            "threshold": args.threshold,
            "n_train": int(len(y_train)),
            "n_test": int(len(y_test)),
            "positive_rate_train": float(y_train.mean()),
            "positive_rate_test": float(y_test.mean()),
        }
    )

    save_curves(
        y_true=y_test,
        y_prob=y_prob,
        outdir=args.output_dir,
        roc_auc=metrics["roc_auc"],
        pr_auc=metrics["pr_auc"],
    )

    preds = pd.DataFrame(
        {
            "row_index": y_test.index,
            "y_true": y_test.values,
            "y_prob": y_prob.values,
            "y_pred": y_pred.values,
        }
    )
    preds.to_csv(args.output_dir / "test_predictions.tsv", sep="\t", index=False)

    (args.output_dir / "metrics.json").write_text(json.dumps(metrics, indent=2, sort_keys=True))

    print("Evaluation complete")
    print(f"ROC-AUC: {metrics['roc_auc']:.6f}")
    print(f"PR-AUC: {metrics['pr_auc']:.6f}")
    print(f"Accuracy: {metrics['accuracy']:.6f}")
    print(f"F1: {metrics['f1']:.6f}")
    print(f"Recall: {metrics['recall']:.6f}")
    print(f"Precision: {metrics['precision']:.6f}")
    print(f"Saved artifacts to: {args.output_dir}")


if __name__ == "__main__":
    main()
