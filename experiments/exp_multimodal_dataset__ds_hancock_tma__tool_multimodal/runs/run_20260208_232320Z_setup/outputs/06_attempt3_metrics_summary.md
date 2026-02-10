# Attempt 3 Metrics Summary (ROC-AUC-Focused)

Source file:
- `outputs/multimodal_metric_results_attempt_3_fix_optimization_override.json`

Requested metrics:
- ROC-AUC
- Accuracy
- Precision
- Recall
- F1-score

## Metrics by split

| Split | ROC-AUC | Accuracy | Precision | Recall | F1-score |
|---|---:|---:|---:|---:|---:|
| Train | 0.8745 | 0.8530 | 0.9375 | 0.3371 | 0.4959 |
| Validation | 0.8086 | 0.8000 | 0.7500 | 0.1304 | 0.2222 |
| Test | 0.7694 | 0.7895 | 0.8571 | 0.1818 | 0.3000 |

## Quick interpretation

- Test ROC-AUC (`0.7694`) is below validation ROC-AUC (`0.8086`) by ~`0.0392`, suggesting moderate generalization gap.
- Precision is high on test (`0.8571`), but recall is low (`0.1818`), yielding a modest F1 (`0.3000`).
- This indicates the classifier is conservative at default decision behavior; ranking quality is usable but has room to improve for ROC-AUC.

## Note

- `test_external` metrics are empty in this artifact; the relevant evaluation metrics are under `test`.
