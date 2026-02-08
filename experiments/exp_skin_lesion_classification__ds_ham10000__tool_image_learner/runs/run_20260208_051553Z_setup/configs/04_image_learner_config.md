# Image Learner Configuration

- tool_id: `toolshed.g2.bx.psu.edu/repos/goeckslab/image_learner/image_learner/0.1.5`
- history: `agent-image_learner` (`bbd44e69cb8906b564fe30d18ba75f5b`)
- metadata csv dataset id: `f9cad7b01a4721356f89ac2d0ba55d36`
- image zip dataset id: `f9cad7b01a4721353cdecbe582bebf01`

## Requested Setup
- task type: `Multi-class Classification` (`task_selection.task=classification`)
- target label column: `dx` (`column_override.target_column=3`)
- image path column: `image_path` (`column_override.image_column=8`)
- sample ID leakage control split key: `lesion_id` (`sample_id_column=1`)
- model: `CAFormer S18 384` (`model_name=caformer_s18_384`)
- image resize: `384x384`
- augmentation: all available
  - `random_horizontal_flip`
  - `random_vertical_flip`
  - `random_rotate`
  - `random_blur`
  - `random_brightness`
  - `random_contrast`
- random seed: `42`
- customize defaults: `yes`
- epochs: `30`
- early stop: `30`

## Payload
- initial payload (attempt 1): `configs/04_image_learner_request.json`
  - result: failed because conditional `__current_case__` selectors were missing; tool defaulted to required column name `label`
- corrected payload (attempt 2): `configs/04b_image_learner_request_fixed_conditionals.json`
  - includes explicit `__current_case__` for `task_selection`, `column_override`, `scratch_fine_tune`, and `advanced_settings`
- corrected payload (attempt 3, active): `configs/04c_image_learner_request_flattened_conditionals.json`
  - uses flattened keys (`column_override|...`, `task_selection|...`, `advanced_settings|...`)
  - confirmed in Galaxy resolved params: `column_override={"override_columns":"true","target_column":"3","image_column":"8"}`
