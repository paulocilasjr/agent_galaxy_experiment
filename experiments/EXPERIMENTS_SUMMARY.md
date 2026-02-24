# Experiments Summary (All Experiment Directories)

This file consolidates the current experiment state across all directories in `experiments/`.
Each section contains: dataset used, tools/strategies, end-to-end workflow, and result metrics (with comparisons where available).

## Built_ML_workflow

Dataset used:
- `Chowell_train_Response.tsv`, `Chowell_test_Response.tsv`, `Chowell_test_No_Response.tsv`, `MSK1_Response.tsv`, `MSK1_No_Response.tsv` from Zenodo `https://zenodo.org/records/13885908`.

Tools and strategies:
- Galaxy `Pipeline Builder` + sklearn model tools (`model fit/predict`, confusion matrix, ROC/PR plotting).
- Two run strategies:
- `run_20260218_180758Z_setup`: baseline pipeline.
- `run_20260218_202848Z_hyperparam_search`: inserts `SearchCV` between pipeline builder and prediction (`C` grid: `0.01,0.1,1,10,100`; `max_iter`: `1000,2000,4000`).

Workflow end-to-end:
1. Create Galaxy history and upload five TSV cohorts.
2. Build tabular ML pipeline in Galaxy.
3. Fit model (or SearchCV+tuned model in run 2).
4. Predict on Chowell test and MSK1 test.
5. Generate confusion/ROC/PR outputs and extract reusable `.ga` workflow.

Results metrics and comparison:

| Run | Cohort | Accuracy | TP | TN | FP | FN |
|---|---|---:|---:|---:|---:|---:|
| setup | Chowell test | 0.2990 | 127 | 27 | 361 | 0 |
| setup | MSK1 test | 0.2759 | 115 | 10 | 327 | 1 |
| hyperparam_search | Chowell test | 0.8000 | 34 | 378 | 10 | 93 |
| hyperparam_search | MSK1 test | 0.7285 | 24 | 306 | 31 | 92 |

Key interpretation:
- Hyperparameter search improved accuracy strongly vs setup on both cohorts.

## IWC_ATAC-seq_Workflow

Dataset used:
- Paired-end FASTQ from Zenodo:
- `https://zenodo.org/record/3862793/files/SRR891268_chr22_enriched_R1.fastq.gz`
- `https://zenodo.org/record/3862793/files/SRR891268_chr22_enriched_R2.fastq.gz`
- Runtime genome parameters: `hg19`, effective genome size `2,700,000,000`, bin size `1000`.

Tools and strategies:
- Imported and executed published Galaxy workflow `ATACseq (release v1.0)` from IWC context.
- Standard ATAC pipeline steps inside workflow (QC, alignment, peak calling, MultiQC).

Workflow end-to-end:
1. Create history and upload paired FASTQ URLs.
2. Build `list:paired` collection.
3. Import IWC ATAC workflow and bind runtime parameters.
4. Invoke workflow and monitor to completion.
5. Download key outputs (`.ga`, mapping stats, narrowPeak, MultiQC).

Results metrics:
- Invocation jobs summary: `27` jobs in `ok` state.
- Mapping stats (`outputs/mapping_stats.txt`):
- Total paired reads: `280,964`
- Overall alignment rate: `98.93%`

## IWC_ChIP-seq Analysis

Dataset used:
- `https://zenodo.org/record/1324070/files/wt_H3K4me3_read1.fastq.gz`
- `https://zenodo.org/record/1324070/files/wt_H3K4me3_read2.fastq.gz`
- Parameters: `mm10`, effective genome size `1,870,000,000`, profile normalization enabled.

Tools and strategies:
- Two execution tracks on same data:
- Baseline: imported IWC workflow release v1.0.
- Local replay: project-local `.ga` (`chipseq-pe.ga`).
- Then direct output-level comparison (`local_vs_baseline_comparison`).

Workflow end-to-end:
1. Upload paired FASTQ and create paired collection.
2. Run baseline IWC workflow.
3. Run local `.ga` workflow.
4. Compare peak/mapping/bigWig outputs between runs.

Results metrics and comparison (baseline vs local):

| Metric | Baseline | Local | Delta |
|---|---:|---:|---:|
| Overall alignment rate (%) | 98.63 | 98.68 | +0.05 |
| NarrowPeak peak count | 13 | 11 | -2 |
| Summits line count | 13 | 11 | -2 |
| BigWig file size (bytes) | 568174 | 557494 | -10680 |
| NarrowPeak SHA256 identical | true/false | false | mismatch |

Key interpretation:
- Local replay is not output-identical to baseline (peak counts and hashes differ).

## RNA-seq_From_Paper

Dataset used:
- BioProjects: `PRJNA904261` and `PRJNA1086003`.
- Reanalysis used `19` count tables + `Candidozyma auris` GTF (`GCA_002759435.3`) from paper-associated Galaxy histories.

Tools and strategies:
- Intended workflow-equivalent execution for paper reproduction.
- Practical execution path: direct Galaxy tool chain per contrast:
- `DESeq2` -> `deg_annotate` -> `volcanoplot`.

Workflow end-to-end:
1. Create dedicated Galaxy history for paper reproduction.
2. Upload count tables + annotation.
3. Run 4 differential-expression contrasts.
4. Generate annotated DE outputs and volcano plots.
5. Compare observed DE values against published values from Anton et al. 2025.

Results metrics and comparison:

| Comparison | Observed DEG Count | Published DEG Count | Observed SCF1 log2FC | Published SCF1 log2FC | Published R2 | Published Direction Agreement (%) |
|---|---:|---:|---:|---:|---:|---:|
| santana_tnSWI1_vs_AR0382_WT | 250 | N/A | -6.8171 | -6.68 | 0.94 | 99.0 |
| santana_AR0387_WT_vs_AR0382_WT | 195 | N/A | -7.3463 | -7.25 | 0.89 | 97.0 |
| wang_AR0382_in_vitro_vs_AR0387_in_vitro | 73 | 76 | 8.6689 | 8.61 | 0.98 | 100.0 |
| wang_AR0382_in_vivo_vs_AR0387_in_vivo | 259 | 259 | 4.5253 | 4.47 | 0.9998 | 100.0 |

Key interpretation:
- Observed values closely track published fold-change summaries for SCF1 and reproduce DEG totals well for Wang contrasts.

## exp_claude_multimodal_dataset

Dataset used:
- `HANCOCK_train_split.csv` (`https://zenodo.org/records/17933596/files/HANCOCK_train_split.csv`)
- `HANCOCK_test_split.csv` (`https://zenodo.org/records/17933596/files/HANCOCK_test_split.csv`)
- `tma_cores_cd3_cd8_images.zip` (`https://zenodo.org/records/17727354/files/tma_cores_cd3_cd8_images.zip`)

Tools and strategies:
- Galaxy Multimodal Learner (AutoGluon multimodal stack: tabular + text + image).
- Iterative run tuning (`run2`, `run3`, `run5`) with changed optimization/training and image backbone.
- `run5` uses `caformer_b36.sail_in22k_ft_in1k_384` backbone.

Workflow end-to-end:
1. Verify API connectivity and create history.
2. Upload train/test CSVs and large image zip.
3. Inspect schema and define target/features.
4. Submit multimodal training configs.
5. Iterate tuned runs and collect test metrics.

Results metrics comparison (test split):

| Run | Accuracy | ROC-AUC | PR-AUC | F1-Score | MCC |
|---|---:|---:|---:|---:|---:|
| run2 | 0.7537 | 0.7139 | 0.6032 | 0.0000 | 0.0000 |
| run3 | 0.6194 | 0.7582 | 0.6211 | 0.4848 | 0.2684 |
| run5 | 0.6791 | 0.8053 | 0.5719 | 0.5567 | 0.3897 |

Key interpretation:
- Best ranking quality (ROC-AUC) among captured runs is `run5` (`0.8053`).

## exp_immunotherapy_chowell_tabular_learner

Dataset used:
- `Chowell_train.tsv` (`https://zenodo.org/records/17781688/files/Chowell_train.tsv`)
- `Chowell_test.tsv` (`https://zenodo.org/records/17781688/files/Chowell_test.tsv`)

Tools and strategies:
- Galaxy `Tabular Learner 0.1.4`.
- Four run phases:
- Run1/Run2: train-only behavior (test dataset not correctly bound initially).
- Run3: corrected test dataset binding via pipe-notation conditionals.
- Run4: same as Run3 + probability threshold set to `0.25`.

Workflow end-to-end:
1. Create history and upload train/test tables via `fetch`.
2. Configure tabular learner target (`Response`).
3. Execute and inspect job metadata.
4. Correct conditional payload to force separate test dataset usage.
5. Execute threshold-tuned run and compare extracted test metrics from reports.

Results metrics comparison (test split):

| Run Label | Accuracy | ROC-AUC | Precision | Recall | F1-score |
|---|---:|---:|---:|---:|---:|
| Chowell_train_only (run1) | 0.728 | 0.713 | 0.607 | 0.200 | 0.301 |
| Chowell_train_only (run2) | 0.728 | 0.713 | 0.607 | 0.200 | 0.301 |
| Chowell_train_test (run3) | 0.796 | 0.760 | 0.712 | 0.291 | 0.413 |
| Chowell_train_test_ProbThres (run4, threshold=0.25) | 0.674 | 0.760 | 0.407 | 0.709 | 0.517 |

Key interpretation:
- Correct test binding improved ROC/accuracy vs train-only runs.
- Threshold `0.25` shifted behavior toward higher recall and higher F1, with lower accuracy.

## exp_library_model_multimodal

Dataset used:
- `HANCOCK_train_split.csv`, `HANCOCK_test_split.csv` (local cached copies of Zenodo Hancock splits).
- `tma_cores_cd3_cd8_images.zip` image corpus via URL in script constants.

Tools and strategies:
- Local Python tri-modal modeling script:
- Tabular block + image block (raw pixel-derived features or patient-embedding mode).
- Text block (`icd_codes`) via TF-IDF.
- Stacked strategy (`ExtraTrees` numeric/image + logistic text + logistic meta learner).

Workflow end-to-end:
1. Load or download Hancock train/test splits.
2. Build image features from raw CD3/CD8 pixels (or patient-linked embeddings).
3. Build text TF-IDF features from ICD codes.
4. Train selected strategy and evaluate train/test.
5. Write metrics, ROC/PR plots, and prediction tables.

Current artifact metrics (`artifacts/metrics.json`):
- Image mode: `pixels`
- Model strategy: `stacked_et_text`
- Test ROC-AUC: `0.804980498049805`
- Test PR-AUC: `0.7067912398074042`
- Test accuracy: `0.8059701492537313`
- Test F1: `0.6060606060606061`

Historical in-experiment strategy benchmark (`strategy_benchmark/summary.tsv`):

| Strategy | Test ROC-AUC | Test PR-AUC |
|---|---:|---:|
| stack_char35_et1500 | 0.792679 | 0.689498 |
| stack_word12_et1500 | 0.791779 | 0.683230 |
| tri_logistic | 0.769577 | 0.594789 |

## exp_library_model_tabular

Dataset used:
- `experiments/exp_library_model_tabular/Chowell_train_Response.tsv`
- `experiments/exp_library_model_tabular/Chowell_test_Response.tsv`

Tools and strategies:
- Local Python sklearn pipeline:
- `SimpleImputer(median)` -> `StandardScaler()` -> `LogisticRegression(liblinear)`.

Workflow end-to-end:
1. Load train/test TSV with target `Response`.
2. Align feature columns between splits.
3. Train logistic model on train split.
4. Evaluate on held-out test split.
5. Save metrics JSON, ROC/PR curves, and prediction table.

Results metrics:
- ROC-AUC: `0.7523134994723597`
- PR-AUC: `0.5484020308644544`
- Accuracy: `0.7883495145631068`
- F1: `0.40437158469945356`
- Precision: `0.6607142857142857`
- Recall: `0.29133858267716534`
- MCC: `0.33557944600829237`

## exp_multimodal_dataset__ds_hancock_tma__tool_multimodal

Dataset used:
- `HANCOCK_train_split.csv` (`https://zenodo.org/records/17933596/files/HANCOCK_train_split.csv`)
- `HANCOCK_test_split.csv` (`https://zenodo.org/records/17933596/files/HANCOCK_test_split.csv`)
- `tma_cores_cd3_cd8_images.zip` (`https://zenodo.org/records/17727354/files/tma_cores_cd3_cd8_images.zip`)

Tools and strategies:
- Galaxy `Multimodal Learner 0.1.5`.
- Multi-attempt tuning sequence with error recovery:
- Attempt 1: NCCL distributed failure.
- Attempt 2: optimization override error.
- Attempt 3: fixed optimization override (successful).
- Attempt 4: backbone/missing-image strategy retune (successful but worse metrics).

Workflow end-to-end:
1. Create Galaxy history and upload Hancock train/test + image zip.
2. Configure multimodal learner with tabular+image+text columns and patient-aware split.
3. Execute and monitor attempts.
4. Download metric result artifacts for successful attempts.
5. Compare test performance across attempts and document deltas.

Results metrics comparison (test split):

| Attempt | State | ROC-AUC | PR-AUC | Accuracy | Precision | Recall | F1-Score | MCC |
|---|---|---:|---:|---:|---:|---:|---:|---:|
| attempt_1 | error | N/A | N/A | N/A | N/A | N/A | N/A | N/A |
| attempt_2_deterministic_no | error | N/A | N/A | N/A | N/A | N/A | N/A | N/A |
| attempt_3_fix_optimization_override | ok | 0.7694 | 0.5859 | 0.7895 | 0.8571 | 0.1818 | 0.3000 | 0.3323 |
| attempt_4_tuning_backbone_b36 | ok | 0.6508 | 0.3905 | 0.7537 | 0.0000 | 0.0000 | 0.0000 | 0.0000 |

Key interpretation:
- Attempt 3 is the best-performing successful Galaxy multimodal run in this directory.

## exp_skin_lesion_classification__ds_ham10000__tool_image_learner

Dataset used:
- Kaggle source reference: `https://www.kaggle.com/datasets/kmader/skin-cancer-mnist-ham10000`
- Local metadata CSV:
- `experiments/exp_skin_lesion_classification__ds_ham10000__tool_image_learner/datasets/selected_HAM10000_img_metadata_aug.csv`
- Image ZIP URL:
- `https://zenodo.org/records/18284218/files/selected_HAM10000_img_96_size.zip`

Tools and strategies:
- Galaxy `Image Learner 0.1.5`.
- Three-attempt correction sequence:
- Attempt 1: failed (`Missing required column(s): label`).
- Attempt 2: failed (conditional encoding still unresolved).
- Attempt 3: succeeded with flattened override and explicit column mapping (`image_column=8`, `target_column=3`, task `classification`).

Workflow end-to-end:
1. Upload metadata CSV + image ZIP into Galaxy history.
2. Configure image learner task and column mapping.
3. Iterate failed attempts and fix payload/conditionals.
4. Complete successful training/evaluation run (attempt 3).
5. Compare obtained report metrics against paper-reported values.

Attempt 3 test metrics (`image_learner_test_statistics_attempt3.json`):
- Accuracy: `0.7153061628341675`
- Micro accuracy: `0.716312050819397`
- ROC-AUC: `0.9322562217712402`
- Macro F1: `0.7178051880333712`
- Weighted precision: `0.7163120567375887`
- Weighted recall: `0.7163120567375887`
- Cohen’s kappa: `0.6690723464178842`

Paper-vs-run metric comparison highlights:
- Paper accuracy `97.78%` vs image learner `71.53%` (difference `-26.25` points).
- Paper precision `97.9%` vs weighted precision `71.63%` (difference `-26.27` points).
- Paper recall `97.9%` vs weighted recall `71.63%` (difference `-26.27` points).
