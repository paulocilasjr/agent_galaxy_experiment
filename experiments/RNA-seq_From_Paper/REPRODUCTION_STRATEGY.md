# Reproduction Strategy: RNA-seq_From_Paper (anton_2025)

## Source paper
- Title: Standardizing RNA-seq Analysis of Fungal Pathogens Using BRC-Analytics and Agentic AI: A Candidozyma auris Case Study
- PDF: `article/anton_2025.pdf`
- DOI: `10.64898/2025.12.30.697050`
- Main scope to reproduce: re-analysis of two published RNA-seq studies plus validation against published differential expression outputs.

## Exact datasets to use
- Study 1 (Santana et al., 2023): BioProject `PRJNA904261`
- Study 2 (Wang et al., 2024): BioProject `PRJNA1086003`
- Reference genome: `Candidozyma auris` B8441, `GCA_002759435.3`
- Annotation mapping source: GTF for `GCA_002759435.3` using `old_locus_tag` to map older v2 IDs to v3 IDs.

## Exact sample groupings (from paper Table 3)
- Santana / `AR0382_WT`: `SRR22376031`, `SRR22376032`
- Santana / `AR0387_WT`: `SRR22376029`, `SRR22376030`
- Santana / `tnSWI1`: `SRR22376027`, `SRR22376028`
- Wang / `AR0382_in_vitro`: `SRR28790270`, `SRR28790272`, `SRR28790274`
- Wang / `AR0387_in_vitro`: `SRR28790276`, `SRR28790278`, `SRR28790280`
- Wang / `AR0382_in_vivo`: `SRR28791430`, `SRR28791431`, `SRR28791432`
- Wang / `AR0387_in_vivo`: `SRR28791433`, `SRR28791434`, `SRR28791437`, `SRR28791438`

## Exact tools and analysis stack
- Platform: Galaxy Main (`https://usegalaxy.org`) via BRC-Analytics context.
- Counting workflow: IWC RNA-seq paired-end workflow (paper cites Zenodo `10.5281/zenodo.8354569`).
- Counting workflow operations:
- `fastp` for adapter trimming and quality filtering.
- Minimum read length after filtering: `15 bp`.
- `STAR` alignment with ENCODE-style settings and gene-level counting.
- `MultiQC` for aggregated QC report.
- Strand-specific `bigWig` coverage track generation.
- Differential expression tool: `DESeq2 (v2.11.40.8+galaxy0)` in Galaxy.
- Reproducibility/provenance requirement:
- Prefer Galaxy native tools for collection transforms (`__FILTER_FROM_FILE__`, `__RELABEL_FROM_FILE__`, `__APPLY_RULES__`) instead of direct collection edits via API.
- If using an agent, require `GALAXY_API_KEY` and keep all prompts/commands logged.

## Reproduction procedure (paper-faithful)
1. Create a run folder in this experiment (same style as other experiments), with subfolders for `commands`, `configs`, `api`, `outputs`, `metadata`, and `prompts`.
2. Download/import all SRR runs listed above into Galaxy and run the same counting workflow on every sample against `GCA_002759435.3`.
3. Build condition-specific collections exactly as in Table 3.
4. Run DESeq2 comparisons exactly as reported:
- Santana comparison A: `AR0382_WT` vs `tnSWI1`.
- Santana comparison B: `AR0382_WT` vs `AR0387_WT`.
- Wang comparison A: `AR0382_in_vitro` vs `AR0387_in_vitro`.
- Wang comparison B: `AR0382_in_vivo` vs `AR0387_in_vivo`.
5. Use paper-matching DE filtering/interpretation:
- Wang study threshold: `FDR < 0.01` and `|log2FC| >= 1`.
- Santana study: paper says Galaxy DESeq2 defaults were used to match published analysis.
6. Reconcile gene IDs between published outputs (older annotation IDs) and current workflow outputs:
- Build mapping from `old_locus_tag` in `GCA_002759435.3` GTF.
- Do not use fold-change-similarity matching for gene identity (paper documents this as incorrect).
7. Compare reproduced DE results against the published supplementary DE tables for each comparison and compute:
- Pearson correlation / `R^2`
- Direction agreement (% same sign of log2FC)
- Mean log2FC difference
8. Generate validation figures (paper-style scatter plots with `y=x`) and summary tables.

## Validation targets reported by the paper
- Santana: `R^2 = 0.94` (tnSWI1 vs AR0382), `R^2 = 0.89` (AR0387 vs AR0382), direction agreement `99%` and `97%`.
- Wang: `R^2 = 0.98` (in vitro) and `R^2 = 0.9998` (in vivo), both with `100%` direction agreement.
- Key marker concordance to verify:
- `SCF1` close match in both studies.
- `ALS4112` close match in Wang comparisons.

## Required artifacts to keep (experiment style)
- `article/anton_2025_extracted_text.txt` (paper text extraction artifact).
- `configs/rna_seq_from_paper_master.ga` (master Galaxy workflow chaining IWC `rnaseq-pe` and `rnaseq-de`).
- Per-run:
- `run_manifest.yaml`
- `journal.md`
- `commands/*.sh`
- `configs/*.json` and any mapping TSV/CSV
- `api/*.json` (request/response traces and job polling)
- `metadata/*.json` and `git_commit.txt`
- `outputs/`:
- Raw DESeq2 outputs (all 4 comparisons)
- ID mapping tables (`old_locus_tag` -> current ID)
- Comparison tables against paper supplementary outputs
- Validation plots and metrics summaries

## Canonical public references from the paper
- Santana reanalysis history: `https://usegalaxy.org/u/cartman/h/prjna904261-perm`
- Wang reanalysis history: `https://usegalaxy.org/u/cartman/h/prjna1086003-perm`
- Additional cited Galaxy history link in references: `https://usegalaxy.org/u/cartman/h/prjna904261-final`
- IWC workflows: `https://iwc.galaxyproject.org`
- IWC repo: `https://github.com/galaxyproject/iwc`

## Notes on exactness
- The paper uses `GCA_002759435.3` for re-analysis even though original publications used older annotation IDs; preserve this design.
- Exact replication requires the supplementary DE tables from Santana and Wang papers for direct comparison inputs.
- Preserve all intermediate artifacts and provenance logs; this is a core result of the paper, not just an implementation detail.
- Execute `configs/rna_seq_from_paper_master.ga` once per comparison using:
- changed-condition FASTQ collection + reference-condition FASTQ collection,
- reference genome `GCA_002759435.3`,
- matching GTF annotation.
