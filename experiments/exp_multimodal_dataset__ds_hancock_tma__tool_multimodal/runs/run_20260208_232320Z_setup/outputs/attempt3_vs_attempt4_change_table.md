# Attempt 3 vs Attempt 4 Change Table

| Category | Field | Attempt 3 | Attempt 4 | Change/Note |
|---|---|---:|---:|---|
| Config | backbone_image | caformer_s18.sail_in22k_ft_in1k | caformer_b36.sail_in22k_ft_in1k_384 | Changed |
| Config | missing_image_strategy | True | False | Changed |
| Config | time_limit (sec) | 21600 | 43200 | Changed |
| Config | preset | best_quality | best_quality | Same |
| Config | eval_metric | roc_auc | roc_auc | Same |
| Config | random_seed | 42 | 42 | Same |
| Data Prep | cleanup train rows | 520 | 533 | After image-missing handling |
| Data Prep | cleanup test rows | 133 | 134 | After image-missing handling |
| Data Prep | train rows dropped (missing images) | 13 | 0 | A4 filled placeholders instead of dropping |
| Data Prep | test rows dropped (missing images) | 1 | 0 | A4 filled placeholders instead of dropping |
| Data Prep | train rows filled with placeholder | 0 | 13 | A3 drops missing rows |
| Data Prep | test rows filled with placeholder | 0 | 1 | A3 drops missing rows |
| Runtime | final train split size | 415 | 426 | Train rows used by model |
| Runtime | final val split size | 105 | 107 | Validation rows used by model |
| Runtime | trainable parameters (M) | 210.000000 | 282.000000 | Model capacity |
| Metrics | fit_summary val_roc_auc | 0.772534 | 0.574866 | Validation summary score |
| Metrics | fit_summary training_time (sec) | 1520.979108 | 1253.198044 | Training wall-time |
| Metrics (train) | ROC-AUC | 0.874543 | 0.759024 |  |
| Metrics (train) | PR-AUC | 0.727128 | 0.509981 |  |
| Metrics (val) | ROC-AUC | 0.808590 | 0.661765 |  |
| Metrics (val) | PR-AUC | 0.548320 | 0.325981 |  |
| Metrics (test) | ROC-AUC | 0.769394 | 0.650765 |  |
| Metrics (test) | PR-AUC | 0.585923 | 0.390479 |  |
| Metrics (test) | Accuracy | 0.789474 | 0.753731 |  |
| Metrics (test) | Precision | 0.857143 | 0.000000 |  |
| Metrics (test) | Recall_(Sensitivity/TPR) | 0.181818 | 0.000000 |  |
| Metrics (test) | F1-Score | 0.300000 | 0.000000 |  |
| Metrics (test) | MCC | 0.332347 | 0.000000 |  |
| Metrics (test) | LogLoss | 0.478200 | 0.539312 |  |
