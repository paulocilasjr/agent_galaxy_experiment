# RNA-seq From Paper: Tool-Equivalent DE Reanalysis Report

- generated_utc: `2026-02-21T05:07:47Z`
- galaxy_url: `https://usegalaxy.org`
- history_name: `RNA-seq_From_Paper_tool_based_20260221_044329Z`
- history_id: `bbd44e69cb8906b5a20b7aa8c26f841e`

## Execution Method

- Created a new Galaxy history and uploaded the same count tables and GTF used in the paper histories.
- Workflow invocations for `rnaseq-de-filtering-plotting.ga` remained in `state=new` with 0 populated steps on this account.
- Executed the same tool chain directly via API per contrast: DESeq2 -> deg_annotate -> volcanoplot.

## Comparison Against Published Values

| comparison | observed DEG count (thresholded) | published DEG count | observed SCF1 log2FC | published SCF1 log2FC | observed ALS4112 log2FC | published ALS4112 log2FC | published R2 | published direction agreement |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| santana_tnSWI1_vs_AR0382_WT | 250 | None | -6.8171283762745 | -6.68 | None | None | 0.94 | 99.0 |
| santana_AR0387_WT_vs_AR0382_WT | 195 | None | -7.34628167084277 | -7.25 | None | None | 0.89 | 97.0 |
| wang_AR0382_in_vitro_vs_AR0387_in_vitro | 73 | 76 | 8.66891252958882 | 8.61 | None | 5.07 | 0.98 | 100.0 |
| wang_AR0382_in_vivo_vs_AR0387_in_vivo | 259 | 259 | 4.52531699402796 | 4.47 | None | 2.56 | 0.9998 | 100.0 |

## Notes

- Published R2/direction-agreement values come from Anton et al. 2025 and are included for reference.
- Exact recomputation of published R2 requires the publication supplementary fold-change tables as explicit inputs.
- `ALS4112` may remain unresolved if absent from this GTF annotation's `gene_name` attribute values.
