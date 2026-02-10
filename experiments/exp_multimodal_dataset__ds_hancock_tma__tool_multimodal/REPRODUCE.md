# Reproduce: HANCOCK + TMA Multimodal Setup

## Use Case Scope
- dataset tables:
  - `HANCOCK_train_split.csv`
  - `HANCOCK_test_split.csv`
- image archive:
  - `tma_cores_cd3_cd8_images.zip`
- Galaxy history:
  - `Agent-Multimodal`

## Read Order
1. `experiments/exp_multimodal_dataset__ds_hancock_tma__tool_multimodal/START_HERE.md`
2. `experiments/exp_multimodal_dataset__ds_hancock_tma__tool_multimodal/datasets/manifest.tsv`
3. `experiments/exp_multimodal_dataset__ds_hancock_tma__tool_multimodal/summaries/run_index.tsv`
4. `experiments/exp_multimodal_dataset__ds_hancock_tma__tool_multimodal/runs/run_20260208_232320Z_setup/journal.md`
5. `experiments/exp_multimodal_dataset__ds_hancock_tma__tool_multimodal/runs/run_20260208_232320Z_setup/configs/03_fetch_targets.json`

## Key Artifacts
- command:
  - `experiments/exp_multimodal_dataset__ds_hancock_tma__tool_multimodal/runs/run_20260208_232320Z_setup/commands/01_create_history_and_upload_urls.sh`
- model setup command:
  - `experiments/exp_multimodal_dataset__ds_hancock_tma__tool_multimodal/runs/run_20260208_232320Z_setup/commands/02_configure_and_run_multimodal_learner.sh`
- monitor/download command:
  - `experiments/exp_multimodal_dataset__ds_hancock_tma__tool_multimodal/runs/run_20260208_232320Z_setup/commands/03_monitor_and_download_outputs.sh`
- next setup command (ROC-AUC improvement):
  - `experiments/exp_multimodal_dataset__ds_hancock_tma__tool_multimodal/runs/run_20260208_232320Z_setup/commands/04_submit_next_setup_roc_auc_improved.sh`
- optimization-override fix rerun command:
  - `experiments/exp_multimodal_dataset__ds_hancock_tma__tool_multimodal/runs/run_20260208_232320Z_setup/commands/05_submit_rerun_fix_optimization_override.sh`
- monitor latest attempt + download outputs command:
  - `experiments/exp_multimodal_dataset__ds_hancock_tma__tool_multimodal/runs/run_20260208_232320Z_setup/commands/06_monitor_and_download_latest_attempt.sh`
- submit next ROC-AUC tuning command (prepared):
  - `experiments/exp_multimodal_dataset__ds_hancock_tma__tool_multimodal/runs/run_20260208_232320Z_setup/commands/07_submit_next_tuning_roc_auc_backbone.sh`
- upload IDs:
  - `experiments/exp_multimodal_dataset__ds_hancock_tma__tool_multimodal/runs/run_20260208_232320Z_setup/metadata/uploaded_dataset_ids.json`
- multimodal run IDs:
  - `experiments/exp_multimodal_dataset__ds_hancock_tma__tool_multimodal/runs/run_20260208_232320Z_setup/metadata/multimodal_learner_execution_ids.json`
- run manifest:
  - `experiments/exp_multimodal_dataset__ds_hancock_tma__tool_multimodal/runs/run_20260208_232320Z_setup/run_manifest.yaml`
- improvement plan:
  - `experiments/exp_multimodal_dataset__ds_hancock_tma__tool_multimodal/runs/run_20260208_232320Z_setup/configs/05_roc_auc_improvement_plan.md`
- fixed payload for AutoGluon compatibility:
  - `experiments/exp_multimodal_dataset__ds_hancock_tma__tool_multimodal/runs/run_20260208_232320Z_setup/configs/06_multimodal_learner_request_fix_optimization_override.json`
- latest metrics summary:
  - `experiments/exp_multimodal_dataset__ds_hancock_tma__tool_multimodal/runs/run_20260208_232320Z_setup/outputs/06_attempt3_metrics_summary.md`
- next tuning payload and plan:
  - `experiments/exp_multimodal_dataset__ds_hancock_tma__tool_multimodal/runs/run_20260208_232320Z_setup/configs/07_multimodal_learner_request_next_tuning_roc_auc_backbone.json`
  - `experiments/exp_multimodal_dataset__ds_hancock_tma__tool_multimodal/runs/run_20260208_232320Z_setup/configs/07_next_tuning_plan.md`
