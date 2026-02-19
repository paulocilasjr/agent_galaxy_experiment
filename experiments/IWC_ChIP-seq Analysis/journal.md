# IWC_ChIP-seq Analysis Journal

- Timestamp (UTC): 2026-02-18T15:10:16Z
- Constraint followed: no project files were read except `.env` (for Galaxy credentials).
- Galaxy server: `https://usegalaxy.org`

## 1. Experiment Setup

- Created experiment directory: `IWC_ChIP-seq Analysis`
- Created Galaxy history: `IWC_ChIP-seq`
- History ID: `bbd44e69cb8906b5a74b1a30aafedb83`
- History URL: `https://usegalaxy.org/histories/view?id=bbd44e69cb8906b5a74b1a30aafedb83`

## 2. Input Data Upload

- Uploaded via Galaxy `tools/fetch` API into `IWC_ChIP-seq`:
  - `https://zenodo.org/record/1324070/files/wt_H3K4me3_read1.fastq.gz`
    - Dataset ID: `f9cad7b01a4721357251f707d7e5d015`
    - State: `ok`
  - `https://zenodo.org/record/1324070/files/wt_H3K4me3_read2.fastq.gz`
    - Dataset ID: `f9cad7b01a4721350e70bfbe29bb88d3`
    - State: `ok`

## 3. IWC Workflow Discovery and Selection

- Searched published workflows in Galaxy API for IWC ChIP-seq workflows.
- Selected workflow:
  - Name: `ChIP-seq Analysis: Paired-End Read Processing (release v1.0)`
  - Owner: `iwc`
  - Shared workflow ID: `2060fa13feff512b`
- Verified compatibility:
  - Has a required `data_collection_input` with `collection_type = list:paired`.

## 4. Workflow Load + Run Configuration

- Imported selected workflow into account:
  - Imported workflow ID: `94d3ee0fc769143b`
- Built paired input collection:
  - Collection name: `wt_H3K4me3_reads_list_paired`
  - Collection ID: `239d876b8b4f7e91`
  - Type: `list:paired` (containing one paired element with `forward=read1`, `reverse=read2`)
- Invocation configured with runtime parameters:
  - `PE fastq input` = `239d876b8b4f7e91`
  - `Percentage of bad quality bases per read` = `70`
  - `Reference genome` = `mm10`
  - `Effective genome size` = `1870000000`
  - `Normalize profile` = `true`
- Primary invocation ID: `2ca0bcda7a418ad4`
- Invocation status (workflow-scoped endpoint): `scheduled` with `12` materialized steps.
- Jobs summary for primary invocation: populated state `ok`, with executed jobs in `ok`.

## 5. Run Results (History Content Snapshot)

- Total history contents observed after run: `50`
- History overall state: `ok`
- No datasets in `error`, `queued`, or `running`.
- Key generated outputs present in `ok` state include:
  - `fastp` reports and filtered paired reads
  - `bowtie2` BAM + mapping stats
  - filtered BAM
  - `MACS2` peaks (`xls`, `narrowPeak`, `summits`) and coverage outputs
  - `MultiQC` report + plots
  - final coverage `bigwig`

## 6. Notes

- Two additional exploratory invocations were created while validating API behavior:
  - `4ba10dedcefe86a9`
  - `fb0841ee43c052a3`
- Primary completed run for this experiment is invocation: `2ca0bcda7a418ad4`.

## 7. Comparison: `chipseq-pe.ga` vs Completed Galaxy Run

- Comparison timestamp (UTC): `2026-02-18T15:21:28Z`
- Local workflow file inspected: `IWC_ChIP-seq Analysis/chipseq-pe.ga`
- Completed Galaxy invocation compared: `2ca0bcda7a418ad4` (jobs summary shows `ok` jobs)
- Galaxy workflow used for run (from invocation report title): `imported: ChIP-seq Analysis: Paired-End Read Processing (release v1.0)`
- Verdict: **they are not the same workflow definition**.

### Equal

- Both are paired-end ChIP-seq workflows and require a paired collection input (`PE fastq input`).
- Shared downstream steps are present in both:
  - `Bowtie2 map on reference`
  - `filter MAPQ30 concordent pairs`
  - `Call Peaks with MACS2`
  - `summary of MACS2`
  - `Bigwig from MACS2`
  - `MultiQC`
- Run parameter intent overlaps for genome and peak-calling context:
  - reference genome
  - effective genome size
  - profile normalization

### Different

- Workflow metadata differs:
  - Local file: `name = ChIP-seq Analysis: Paired-End Read Processing`, `release = 0.14`, `steps = 13`
  - Executed workflow: `name = ChIP-seq Analysis: Paired-End Read Processing (release v1.0)`, `steps = 12`
- Preprocessing strategy changed:
  - Local file uses `Cutadapt (remove adapter + bad quality bases)` with two explicit adapter parameters:
    - `adapter_forward`
    - `adapter_reverse`
  - Executed workflow uses `Fastp (remove adapter and bad quality reads)` with one quality parameter:
    - `Percentage of bad quality bases per read` (run value `70`)
- Input parameter labels differ:
  - Local: `reference_genome`, `effective_genome_size`, `normalize_profile` (snake_case)
  - Executed: `Reference genome`, `Effective genome size`, `Normalize profile` (title-case labels)
- Tool/version differences in shared steps:
  - Bowtie2:
    - Local: `toolshed.g2.bx.psu.edu/repos/devteam/bowtie2/bowtie2/2.5.3+galaxy1`
    - Executed: `toolshed.g2.bx.psu.edu/repos/devteam/bowtie2/bowtie2/2.5.4+galaxy0`
  - text-processing grep step (`summary of MACS2`):
    - Local: `toolshed.g2.bx.psu.edu/repos/bgruening/text_processing/tp_grep_tool/9.5+galaxy0`
    - Executed: `toolshed.g2.bx.psu.edu/repos/bgruening/text_processing/tp_grep_tool/9.5+galaxy2`

### Artifacts Written for Audit

- `IWC_ChIP-seq Analysis/chipseq-pe.vs-executed.json` (structured comparison)

## 8. Full Replay from Start Using Local `chipseq-pe.ga` + Final Output Comparison

- Replay request date context: 2026-02-18
- Goal: re-run from scratch with local workflow file and compare final outputs against prior baseline run.
- Baseline reference kept for comparison:
  - history: `IWC_ChIP-seq` (`bbd44e69cb8906b5a74b1a30aafedb83`)
  - invocation: `2ca0bcda7a418ad4`

### 8.1 Reproducible Artifact Structure Created

- Added run-style folders to mirror other project examples:
  - `IWC_ChIP-seq Analysis/commands`
  - `IWC_ChIP-seq Analysis/prompts`
  - `IWC_ChIP-seq Analysis/configs`
  - `IWC_ChIP-seq Analysis/metadata`
  - `IWC_ChIP-seq Analysis/api`
  - `IWC_ChIP-seq Analysis/outputs`
- Added run metadata file:
  - `IWC_ChIP-seq Analysis/run_manifest.yaml`
- Added reproducible command scripts:
  - `IWC_ChIP-seq Analysis/commands/01_replay_local_ga_from_scratch.sh`
  - `IWC_ChIP-seq Analysis/commands/02_compare_local_vs_baseline.sh`

### 8.2 Start-from-Beginning Execution with Local `.ga`

- Created new Galaxy history:
  - name: `IWC_ChIP-seq-local-ga-20260218_161836Z`
  - id: `bbd44e69cb8906b5b8fba8bcb2057dda`
  - create_time: `2026-02-18T16:18:36.274056`
- Uploaded input FASTQs from URL:
  - `wt_H3K4me3_read1.fastq.gz` -> `f9cad7b01a4721354bf8f827bf5df1a5`
  - `wt_H3K4me3_read2.fastq.gz` -> `f9cad7b01a4721351533342561fcdc18`
- Created paired collection:
  - collection id: `d78fa2cadd1fb771`
- Imported local workflow file:
  - source: `IWC_ChIP-seq Analysis/chipseq-pe.ga`
  - imported workflow id: `b6a88c16f02c8f8e`
- Invoked local workflow with runtime parameters:
  - invocation id: `7f6d92f66b786b5c`
  - adapter_forward: `AGATCGGAAGAGCACACGTCTGAACTCCAGTCAC`
  - adapter_reverse: `AGATCGGAAGAGCGTCGTGTAGGGAAAGAGTGT`
  - reference_genome: `mm10`
  - effective_genome_size: `1870000000`
  - normalize_profile: `true`
- Completion status:
  - jobs_summary populated_state: `ok`
  - jobs_summary states: `ok=7`
  - local run reached terminal success

### 8.3 Final Output Comparison (Baseline v1.0 vs Local `.ga`)

- Comparison artifacts:
  - `IWC_ChIP-seq Analysis/outputs/local_vs_baseline_comparison.json`
  - `IWC_ChIP-seq Analysis/outputs/local_vs_baseline_comparison.csv`
  - `IWC_ChIP-seq Analysis/outputs/local_vs_baseline_comparison.md`
- Main result:
  - outputs are **not identical**
  - narrowPeak SHA256 mismatch:
    - baseline: `dbd2d34eb1f16e631c2952bdfeabb9a82e98045ce3444b600da21448a3df9a88`
    - local: `e868fd64979dc908968d4e87555ae6c18b1919491c9f9c7842a17ad2fd40da3d`
- Key numeric differences:
  - overall alignment rate (%): baseline `98.63`, local `98.68` (delta `+0.05`)
  - narrowPeak peak count: baseline `13`, local `11` (delta `-2`)
  - summits line count: baseline `13`, local `11` (delta `-2`)
  - bigWig file size bytes: baseline `568174`, local `557494` (delta `-10680`)

### 8.4 Final Equivalence Answer

- Same pipeline purpose and same output categories were produced.
- Final biological result files are **similar in type but not the same in value/content**.
