# Next Steps For This Experiment

1. Replace placeholder dataset row in `datasets/manifest.tsv`.
2. Keep every execution under `runs/<run_id>/...`.
3. Do not place Image Learner artifacts in `artifacts/` root-level legacy paths.
4. At run completion, update:
   - `runs/<run_id>/run_manifest.yaml`
   - `runs/<run_id>/journal.md`
   - `summaries/run_index.tsv` status
