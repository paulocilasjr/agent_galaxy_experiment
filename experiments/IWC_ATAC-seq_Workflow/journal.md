# IWC_ATAC-seq_Workflow Journal

- Timestamp (UTC): 2026-02-19T22:59:48Z
- Galaxy server: `https://usegalaxy.org`

## 1. Workflow Resolution
- Requested page workflow name: `ATAC-seq Analysis: Chromatin Accessibility Profiling`
- Selected published Galaxy workflow: `ATACseq (release v1.0)`
- Shared workflow ID: `5d1208bd49f97aeb`
- Imported workflow ID: `3c6701c2fd1648ba`

## 2. History + Inputs
- Created history: `IWC_ATAC-seq` (`bbd44e69cb8906b5f82e2be34946c688`)
- Uploaded R1: `https://zenodo.org/record/3862793/files/SRR891268_chr22_enriched_R1.fastq.gz` -> `f9cad7b01a472135406a979cdc5fefd2`
- Uploaded R2: `https://zenodo.org/record/3862793/files/SRR891268_chr22_enriched_R2.fastq.gz` -> `f9cad7b01a4721357d95bf1ba68e0675`
- Created collection (`list:paired`): `2a74605db3af17c0`

## 3. Invocation
- Invocation ID: `09aedfb38199c089`
- Runtime parameters used (IWC example):
  - `reference_genome = hg19`
  - `effective_genome_size = 2700000000`
  - `bin_size = 1000`
- Final jobs summary: `{"id": "09aedfb38199c089", "model": "WorkflowInvocation", "populated_state": "ok", "states": {"ok": 27}}`

## 4. Saved Artifacts
- Workflow file: `experiments/IWC_ATAC-seq_Workflow/outputs/ATACseq_release_v1_0_imported.ga`
- Invocation request: `experiments/IWC_ATAC-seq_Workflow/api/12_invocation_request.json`
- Invocation report: `experiments/IWC_ATAC-seq_Workflow/api/13_invocation_report.json`
- Invocation steps detail: `experiments/IWC_ATAC-seq_Workflow/api/15_invocation_steps_detail.json`
- Final history contents snapshot: `experiments/IWC_ATAC-seq_Workflow/api/14_history_contents_final.json`
- Mapping stats downloaded: `experiments/IWC_ATAC-seq_Workflow/outputs/mapping_stats.txt`
- MACS2 narrowPeak downloaded: `experiments/IWC_ATAC-seq_Workflow/outputs/macs2_narrowpeak.bed`
- MultiQC report downloaded: `experiments/IWC_ATAC-seq_Workflow/outputs/multiqc_report.html`
