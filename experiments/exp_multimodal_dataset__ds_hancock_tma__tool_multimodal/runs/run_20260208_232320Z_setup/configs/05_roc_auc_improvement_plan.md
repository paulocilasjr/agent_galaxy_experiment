# ROC-AUC Improvement Plan (Next Setup)

## Why Previous Run Failed

- Failure type: infrastructure/runtime (not model quality)
- Error: NCCL distributed backend crash during multi-GPU initialization:
  - `ncclUnhandledCudaError: operation not supported`
- Consequence:
  - no valid metric JSON produced
  - no ROC-AUC to compare from attempt 1

## Proposed Next Setup

Use request payload:
- `configs/05_multimodal_learner_request_roc_auc_improved_single_gpu.json`

Main changes from failed attempt:
1. Force single GPU in hyperparameters:
   - `env.num_gpus: 1`
2. Increase training quality:
   - `preset = best_quality`
   - `time_limit = 21600`
3. Keep ROC-AUC as optimization target:
   - `eval_metric = roc_auc`
4. Tune core optimization defaults:
   - `validation_size = 0.15`
   - `epochs = 40`
   - `learning_rate = 2e-05`
   - `batch_size = 8`
5. Try stronger image backbone for pathology-style inputs:
   - `caformer_s18.sail_in22k_ft_in1k`

## Submission Command

- `commands/04_submit_next_setup_roc_auc_improved.sh`
