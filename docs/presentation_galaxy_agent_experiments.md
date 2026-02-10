# Galaxy Agent Experiments: Codex Performance Presentation

## Slide 1 - Goal
Evaluate how Codex performed in three Galaxy experiment setups and answer the same questions in this order:
1. Is Codex able to upload files? How?
2. Is the Codex Agent able to run setup Galaxy tools and execute them?
3. What is the importance of the prompt regarding tool setup?
4. What difficulties does the agent find?
5. Are mistakes easy to identify and fix?
6. Is the agent capable of creating artifacts that make reproducibility easier?
7. What can be improved?
8. What must the user pay attention to when using agents for Galaxy experiments?

## Slide 2 - Evidence Used
- Tabular run journal and prompts: `/Users/4475918/Projects/agent_galaxy_experiment/artifacts/immunotherapy_20260207_121552/journal.md`
- Image run journal and prompts: `/Users/4475918/Projects/agent_galaxy_experiment/experiments/exp_skin_lesion_classification__ds_ham10000__tool_image_learner/runs/run_20260208_051553Z_setup/journal.md`
- Multimodal run journal and prompts: `/Users/4475918/Projects/agent_galaxy_experiment/experiments/exp_multimodal_dataset__ds_hancock_tma__tool_multimodal/runs/run_20260208_232320Z_setup/journal.md`

---

## Slide 3 - Tabular Learner (Detailed Prompt)
### Prompt level
Very detailed and stepwise. The user explicitly defined tool, datasets, separate test usage, and target column.
Evidence: `/Users/4475918/Projects/agent_galaxy_experiment/artifacts/immunotherapy_20260207_121552/prompts/03_tool_setup_prompt.md`

### Q1) Upload files?
Yes. Via Galaxy fetch API (`/api/tools/fetch`) for URL datasets.
Evidence: `/Users/4475918/Projects/agent_galaxy_experiment/artifacts/immunotherapy_20260207_121552/commands/02_create_history_and_upload.sh`

### Q2) Run setup and tool?
Yes. Tool build + submit + polling were automated and completed (`ok`) across corrected runs.
Evidence: `/Users/4475918/Projects/agent_galaxy_experiment/artifacts/immunotherapy_20260207_121552/commands/04_execute_tabular_learner.sh`

### Q3) Importance of prompt quality?
High. Even detailed prompts did not fully prevent conditional-field serialization mistakes; explicit corrective prompts quickly converged to the right payload.
Evidence: `/Users/4475918/Projects/agent_galaxy_experiment/artifacts/immunotherapy_20260207_121552/prompts/04b_fix_test_dataset_and_rerun.md`

### Q4) Main difficulties?
Galaxy conditional input encoding (`has_test_file`) and API payload shape.
Evidence: `/Users/4475918/Projects/agent_galaxy_experiment/artifacts/immunotherapy_20260207_121552/api/03_upload_fetch_attempt1_error.json`

### Q5) Easy to identify/fix?
Mostly yes. Job metadata exposed wrong resolved params (`has_test_file=no`) and fix was validated with job command + params.
Evidence: `/Users/4475918/Projects/agent_galaxy_experiment/artifacts/immunotherapy_20260207_121552/api/05c_job_details_full_final.json`

### Q6) Reproducibility artifacts?
Strong. Prompt logs, commands, configs, API snapshots, execution summaries, and metrics comparison PNG/CSV/JSON.
Evidence: `/Users/4475918/Projects/agent_galaxy_experiment/artifacts/immunotherapy_20260207_121552/metadata/06_metrics_comparison_summary.json`

### Q7) What to improve?
- Add automatic schema-to-payload validator before submission.
- Add post-submit assertion checks for key params (`has_test_file`, selected columns).

### Q8) User attention points
- Verify resolved params from job metadata, not only payload intent.
- Require explicit confirmation for conditionals in prompts.

---

## Slide 4 - Image Learner (Tool-Details Omitted, Dataset Handling Explicit)
### Prompt level
Moderately specified: strong dataset/splitting instructions, less explicit tool API conditional details.
Evidence: `/Users/4475918/Projects/agent_galaxy_experiment/experiments/exp_skin_lesion_classification__ds_ham10000__tool_image_learner/runs/run_20260208_051553Z_setup/prompts/03_setup_and_run_image_learner.md`

### Q1) Upload files?
Yes. Both local upload (`upload1`, multipart) and URL fetch upload were executed.
Evidence: `/Users/4475918/Projects/agent_galaxy_experiment/experiments/exp_skin_lesion_classification__ds_ham10000__tool_image_learner/runs/run_20260208_051553Z_setup/commands/01_create_history_and_upload_inputs.sh`

### Q2) Run setup and tool?
Yes. Tool was configured and run three attempts; first two failed, third reached running with corrected resolved params.
Evidence: `/Users/4475918/Projects/agent_galaxy_experiment/experiments/exp_skin_lesion_classification__ds_ham10000__tool_image_learner/runs/run_20260208_051553Z_setup/metadata/image_learner_attempts_summary.json`

### Q3) Importance of prompt quality?
Very high. Missing explicit conditional semantics caused fallback to defaults (`label` expected), despite correct conceptual intent.
Evidence: `/Users/4475918/Projects/agent_galaxy_experiment/experiments/exp_skin_lesion_classification__ds_ham10000__tool_image_learner/runs/run_20260208_051553Z_setup/api/15_image_learner_job_status_poll_2.json`

### Q4) Main difficulties?
Nested conditional controls (`__current_case__`) and need for flattened key style (`column_override|...`) for robust override behavior.
Evidence: `/Users/4475918/Projects/agent_galaxy_experiment/experiments/exp_skin_lesion_classification__ds_ham10000__tool_image_learner/runs/run_20260208_051553Z_setup/commands/05_rerun_image_learner_override_yes_flattened.sh`

### Q5) Easy to identify/fix?
Partly. Error messages were clear (`Missing required column(s) in metadata: label`), but fixing required Galaxy-specific payload knowledge.
Evidence: `/Users/4475918/Projects/agent_galaxy_experiment/experiments/exp_skin_lesion_classification__ds_ham10000__tool_image_learner/runs/run_20260208_051553Z_setup/api/27_image_learner_job_status_fixed_poll_3.json`

### Q6) Reproducibility artifacts?
Strong. Attempt-by-attempt payloads, status snapshots, and corrected submissions are preserved.
Evidence: `/Users/4475918/Projects/agent_galaxy_experiment/experiments/exp_skin_lesion_classification__ds_ham10000__tool_image_learner/runs/run_20260208_051553Z_setup/configs/04c_image_learner_request_flattened_conditionals.json`

### Q7) What to improve?
- Auto-detect and enforce conditional cases from build schema.
- Add a preflight test that confirms intended resolved params before full training.

### Q8) User attention points
- Always verify that “overwrite columns” is truly active in resolved job params.
- Ask the agent to show final resolved `params` and command line before long runs.

---

## Slide 5 - Multimodal Learner (Vague Prompt)
### Prompt level
Most vague: “find a tool and set it up accordingly” with desired output objective.
Evidence: `/Users/4475918/Projects/agent_galaxy_experiment/experiments/exp_multimodal_dataset__ds_hancock_tma__tool_multimodal/runs/run_20260208_232320Z_setup/prompts/02_find_and_run_model_tool.md`

### Q1) Upload files?
Yes. Multiple URL datasets uploaded through `/api/tools/fetch`.
Evidence: `/Users/4475918/Projects/agent_galaxy_experiment/experiments/exp_multimodal_dataset__ds_hancock_tma__tool_multimodal/runs/run_20260208_232320Z_setup/commands/01_create_history_and_upload_urls.sh`

### Q2) Run setup and tool?
Yes. Agent selected Multimodal Learner, executed multiple reruns, monitored jobs, and auto-downloaded outputs.
Evidence: `/Users/4475918/Projects/agent_galaxy_experiment/experiments/exp_multimodal_dataset__ds_hancock_tma__tool_multimodal/runs/run_20260208_232320Z_setup/commands/06_monitor_and_download_latest_attempt.sh`

### Q3) Importance of prompt quality?
Extremely high. Vague prompt increased autonomy burden: tool selection, parameter choices, and iterative recovery were all agent-inferred.
Evidence: `/Users/4475918/Projects/agent_galaxy_experiment/experiments/exp_multimodal_dataset__ds_hancock_tma__tool_multimodal/runs/run_20260208_232320Z_setup/journal.md`

### Q4) Main difficulties?
- Infrastructure/runtime issue (NCCL distributed error).
- Tool-wrapper compatibility issue (AutoGluon `optimization` override KeyError).
Evidence: `/Users/4475918/Projects/agent_galaxy_experiment/experiments/exp_multimodal_dataset__ds_hancock_tma__tool_multimodal/runs/run_20260208_232320Z_setup/outputs/evaluation_summary.md`

### Q5) Easy to identify/fix?
Mixed.
- NCCL error: identifiable from logs, fix path available (single-GPU/deterministic adjustments).
- Optimization KeyError: identifiable but required deeper wrapper-level workaround (`customize_defaults=no`).
Evidence: `/Users/4475918/Projects/agent_galaxy_experiment/experiments/exp_multimodal_dataset__ds_hancock_tma__tool_multimodal/runs/run_20260208_232320Z_setup/metadata/multimodal_learner_execution_ids.json`

### Q6) Reproducibility artifacts?
Very strong. Full attempt lineage, configs per attempt, monitor/download scripts, metrics extraction, next-tuning plan.
Evidence: `/Users/4475918/Projects/agent_galaxy_experiment/experiments/exp_multimodal_dataset__ds_hancock_tma__tool_multimodal/runs/run_20260208_232320Z_setup/metadata/multimodal_outputs_download_summary.json`

### Q7) What to improve?
- Add agent guardrails for GPU strategy fallback (multi-GPU -> single-GPU on NCCL errors).
- Add compatibility checks against deprecated override keys before submit.
- Add prompt template requiring minimum tool constraints (metric, compute mode, failure policy).

### Q8) User attention points
- Ask for explicit fallback policies in the prompt (runtime crash handling, parameter rollback rules).
- Require attempt registry and status gates before each rerun.

---

## Slide 6 - Cross-Experiment Comparison
| Dimension | Tabular (detailed) | Image (partial) | Multimodal (vague) |
|---|---|---|---|
| Prompt specificity | High | Medium | Low |
| Upload complexity | URL fetch | Local + URL | URL fetch (3 inputs) |
| Failure type | Payload conditional binding | Conditional case resolution | Infra + wrapper compatibility |
| Recovery effort | Low-medium | Medium | High |
| Final evidence maturity | High | High (in-progress run) | Very high (multi-attempt lineage) |

## Slide 7 - Main Conclusion
- Codex can upload files and execute Galaxy tools reliably.
- Performance depends strongly on prompt specificity, especially for conditional tool inputs.
- Reproducibility artifact generation is a major strength (commands, payloads, logs, journals, metrics).
- With vague prompts, Codex still progresses, but cost is more retries and greater need for guardrails.

## Slide 8 - Practical Recommendations for Future Runs
1. Start prompts with a strict template: tool id/version, required conditional toggles, target/split columns, metric, compute constraints, and fallback policy.
2. Require a preflight check stage: build schema parse + resolved params assertion before full run.
3. Enforce automatic attempt registry updates after every submit/poll/download.
4. Add standardized “error-to-fix playbook” for common Galaxy conditional and runtime failures.

