# Prompt Log
timestamp_utc: 2026-02-08T04:59:24Z
step: 5
goal: Compare test-split metrics across four run report HTML outputs and render comparison figure.

## prompt
Read the html files that are the report files generated as output from each run and create a figure (png)  to compare the Test split results from each run for accuracy, ROC-AUC, precision, recall, and F1-score. 
Organize it as a table where each row is a metric, columns are the runs (name each run as: Chowell_train_only, Chowell_train_only, Chowell_train_test, Chowell_train_test_ProbThres.

## response_summary
Downloaded each report dataset, extracted embedded HTML from zip-formatted outputs, parsed the test-split metrics table, and generated the requested PNG comparison table. Saved CSV/JSON with extracted values.

## artifacts_created
- artifacts/immunotherapy_20260207_121552/outputs/reports/test_split_metrics_comparison.png
- artifacts/immunotherapy_20260207_121552/outputs/reports/test_split_metrics_by_run.csv
- artifacts/immunotherapy_20260207_121552/outputs/reports/test_split_metrics_by_run.json
- artifacts/immunotherapy_20260207_121552/metadata/06_report_dataset_states.tsv
- artifacts/immunotherapy_20260207_121552/metadata/06_metrics_comparison_summary.json
