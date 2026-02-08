# Tabular Learner Configuration (Step 3)

timestamp_utc: 2026-02-08T00:36:57Z
history_name: agent-tabular_learner
history_id: bbd44e69cb8906b5818b2d41fc14f7a1

tool_name: Tabular Learner
tool_id: toolshed.g2.bx.psu.edu/repos/goeckslab/tabular_learner/tabular_learner/0.1.4
tool_version: 0.1.4

## User-specified settings (latest)
- Input Dataset: `Chowell_train.tsv` (`f9cad7b01a47213515562d8d15c5db3d`)
- Do you have a separate test dataset?: `yes`
- Tabular Test Dataset: `Chowell_test.tsv` (`f9cad7b01a4721353f443ce2cb15cd33`)
- Select the target column: `c22: Response` (`target_feature=22`)
- Customize Default Settings: `yes`
- Classification Probability Threshold: `0.25`

## Delta from previous corrected run
- Changed: `advanced_settings|customize_defaults` from `false` to `true`.
- Changed: `advanced_settings|probability_threshold` from default `0.5` to `0.25`.
- Unchanged: all other model/task/data settings.

## Explicit defaults preserved (unchanged behavior)
- Task: `classification`
- Best-model metric: `Accuracy`
- Use sample ID column: `no`
- Tune hyperparameters: `false`
- Random seed: `42`
- Train size: `0.7`
- Enable cross-validation: `true` with folds `10`
- Normalize: `false`
- Feature selection: `false`
- Remove outliers: `false`
- Remove multicollinearity: `false`
- Polynomial features: `false`
- Fix imbalance: `false`

## Source files
- https://zenodo.org/records/17781688/files/Chowell_train.tsv
- https://zenodo.org/records/17781688/files/Chowell_test.tsv

## API artifacts used
- `artifacts/immunotherapy_20260207_121552/api/04_tools_search_tabular_learner.json`
- `artifacts/immunotherapy_20260207_121552/api/04_tabular_learner_build.json`
- `artifacts/immunotherapy_20260207_121552/configs/tabular_learner_request.json`
- `artifacts/immunotherapy_20260207_121552/configs/tabular_learner_request_custom_prob_025.json`

## API encoding note
- Galaxy conditional fields for this tool must use pipe notation in API payloads.
- Required keys include:
  - `test_data_choice|has_test_file` and `test_data_choice|test_file`
  - `advanced_settings|customize_defaults`
  - `advanced_settings|probability_threshold`
