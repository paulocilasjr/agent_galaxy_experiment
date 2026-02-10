# Experiments Catalog

This folder is the canonical index for all use cases in this repository.

## Active Use Cases

1. Immunotherapy response with Chowell + Tabular Learner
   - experiment id: `exp_immunotherapy_chowell_tabular_learner`
   - entrypoint: `experiments/exp_immunotherapy_chowell_tabular_learner/START_HERE.md`
   - reproducibility map: `experiments/exp_immunotherapy_chowell_tabular_learner/REPRODUCE.md`
   - run index: `experiments/exp_immunotherapy_chowell_tabular_learner/summaries/run_index.tsv`
2. Skin lesion classification with HAM10000 + Image Learner
   - experiment id: `exp_skin_lesion_classification__ds_ham10000__tool_image_learner`
   - entrypoint: `experiments/exp_skin_lesion_classification__ds_ham10000__tool_image_learner/START_HERE.md`
   - reproducibility map: `experiments/exp_skin_lesion_classification__ds_ham10000__tool_image_learner/REPRODUCE.md`
   - run index: `experiments/exp_skin_lesion_classification__ds_ham10000__tool_image_learner/summaries/run_index.tsv`
3. Multimodal dataset setup with HANCOCK splits + TMA CD3/CD8 images
   - experiment id: `exp_multimodal_dataset__ds_hancock_tma__tool_multimodal`
   - entrypoint: `experiments/exp_multimodal_dataset__ds_hancock_tma__tool_multimodal/START_HERE.md`
   - reproducibility map: `experiments/exp_multimodal_dataset__ds_hancock_tma__tool_multimodal/REPRODUCE.md`
   - run index: `experiments/exp_multimodal_dataset__ds_hancock_tma__tool_multimodal/summaries/run_index.tsv`

## Separation Rules

- Keep all run artifacts under `experiments/<experiment_id>/runs/<run_id>/`.
- Keep dataset source mappings under `experiments/<experiment_id>/datasets/manifest.tsv`.
- Use `summaries/run_index.tsv` to locate all runs for one experiment.
- Do not mix APIs/configs/journals across experiment directories.
