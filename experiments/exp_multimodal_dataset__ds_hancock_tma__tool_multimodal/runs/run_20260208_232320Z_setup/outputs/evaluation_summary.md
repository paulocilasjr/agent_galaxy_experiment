# Evaluation Summary

## Run Outcome
- job_id: `bbd44e69cb8906b538f7c3278b60f690`
- status: `error`
- reason: NCCL distributed initialization failure on 2-GPU DDP path (`ncclUnhandledCudaError: operation not supported`)

## Metric Availability
- `outputs/multimodal_metric_results.json` is empty due training crash.
- No valid ROC-AUC was produced for this attempt.

## Data/Setup Validation
- target column mapping resolved correctly: `target` (column 3)
- separate test dataset was applied
- sample ID leakage-aware split was applied (`patient_id`, column 1)
- image modality was detected and image columns inferred (`CD3_image_path`, `CD8_image_path`)

## Recommended Next Setup For Better ROC-AUC
- use single-GPU execution to avoid NCCL DDP crash
- increase quality/time budget (`best_quality`, longer `time_limit`)
- keep optimization metric as ROC-AUC
- tune optimization defaults (epochs/lr/batch size)
- request file: `configs/05_multimodal_learner_request_roc_auc_improved_single_gpu.json`
