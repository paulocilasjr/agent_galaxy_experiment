# Multimodal Learner Configuration

- tool_id: `toolshed.g2.bx.psu.edu/repos/goeckslab/multimodal_learner/multimodal_learner/0.1.5`
- history: `Agent-Multimodal` (`bbd44e69cb8906b5ce223e9a81174ae0`)
- training dataset: `HANCOCK_train_split.csv` (`f9cad7b01a472135214deb0f5acedc0b`)
- test dataset: `HANCOCK_test_split.csv` (`f9cad7b01a4721356b6decc42b7e78f0`)
- image archive: `tma_cores_cd3_cd8_images.zip` (`f9cad7b01a4721357c0e9f7ba4c68487`)

## Core Setup
- target column: `c3: target`
- sample id for leakage-aware split: `c1: patient_id`
- separate test dataset: enabled
- image modality: enabled
- image ZIP(s): one archive provided (contains CD3/CD8 image files)
- missing image strategy: drop rows with missing images
- text backbone: `microsoft/deberta-v3-base`
- image backbone: `swin_base_patch4_window7_224.ms_in22k_ft_in1k`
- quality preset: `medium_quality`
- eval metric: `roc_auc`
- random seed: `42`
- time limit: `7200` seconds
- deterministic mode: enabled

## Payload
- exact request JSON: `configs/04_multimodal_learner_request.json`
