# Next Tuning Run Proposal (ROC-AUC)

## Objective

Increase test ROC-AUC beyond `0.7694` from attempt 3 while avoiding the known `optimization` override crash.

## Why this setup

- Attempt 3 was stable and successful with:
  - `deterministic=false`
  - `customize_defaults=no`
- We keep the stable configuration and change only high-impact levers outside the buggy optimization override path.

## Proposed changes vs attempt 3

1. Image backbone:
   - from `caformer_s18.sail_in22k_ft_in1k`
   - to `caformer_b36.sail_in22k_ft_in1k_384`
   - rationale: larger backbone can improve representation quality for image modality and ranking performance.
2. Time limit:
   - from `21600` to `43200`
   - rationale: give `best_quality` preset enough budget for stronger candidate exploration.
3. Missing image handling:
   - set `missing_image_strategy=false`
   - rationale: avoid dropping rows with missing images and preserve sample count.

## Fixed config file

- `configs/07_multimodal_learner_request_next_tuning_roc_auc_backbone.json`

## Submit command (prepared, not executed here)

- `commands/07_submit_next_tuning_roc_auc_backbone.sh`
