# Local `.ga` vs Baseline IWC v1.0: Final Output Comparison

- Baseline invocation: `2ca0bcda7a418ad4` (history `bbd44e69cb8906b5a74b1a30aafedb83`)
- Local invocation: `7f6d92f66b786b5c` (history `bbd44e69cb8906b5b8fba8bcb2057dda`)

## Result Equivalence Verdict
- NarrowPeak files are different (`sha256` mismatch).

## Key Metrics
- Overall alignment rate (%): baseline `98.63`, local `98.68`, delta `0.05000000000001137`
- Peak count (narrowPeak lines): baseline `13`, local `11`, delta `-2`
- Summits line count: baseline `13`, local `11`, delta `-2`
- BigWig file size (bytes): baseline `568174`, local `557494`, delta `-10680`

## Workflow/Tool Differences Confirmed in Executed Runs
- Step order `1`: baseline `Percentage of bad quality bases per read` / `None` vs local `adapter_forward` / `None`
- Step order `2`: baseline `Reference genome` / `None` vs local `adapter_reverse` / `None`
- Step order `3`: baseline `Effective genome size` / `None` vs local `reference_genome` / `None`
- Step order `4`: baseline `Normalize profile` / `None` vs local `effective_genome_size` / `None`
- Step order `5`: baseline `Fastp (remove adapter and bad quality reads)` / `toolshed.g2.bx.psu.edu/repos/iuc/fastp/fastp/1.0.1+galaxy2` vs local `normalize_profile` / `None`
- Step order `6`: baseline `Bowtie2 map on reference` / `toolshed.g2.bx.psu.edu/repos/devteam/bowtie2/bowtie2/2.5.4+galaxy0` vs local `Cutadapt (remove adapter + bad quality bases)` / `toolshed.g2.bx.psu.edu/repos/lparsons/cutadapt/cutadapt/5.0+galaxy0`
- Step order `7`: baseline `filter MAPQ30 concordent pairs` / `toolshed.g2.bx.psu.edu/repos/devteam/samtool_filter2/samtool_filter2/1.8+galaxy1` vs local `Bowtie2 map on reference` / `toolshed.g2.bx.psu.edu/repos/devteam/bowtie2/bowtie2/2.5.3+galaxy1`
- Step order `8`: baseline `Call Peaks with MACS2` / `toolshed.g2.bx.psu.edu/repos/iuc/macs2/macs2_callpeak/2.2.9.1+galaxy0` vs local `filter MAPQ30 concordent pairs` / `toolshed.g2.bx.psu.edu/repos/devteam/samtool_filter2/samtool_filter2/1.8+galaxy1`
- Step order `9`: baseline `summary of MACS2` / `toolshed.g2.bx.psu.edu/repos/bgruening/text_processing/tp_grep_tool/9.5+galaxy2` vs local `Call Peaks with MACS2` / `toolshed.g2.bx.psu.edu/repos/iuc/macs2/macs2_callpeak/2.2.9.1+galaxy0`
- Step order `10`: baseline `Bigwig from MACS2` / `wig_to_bigWig` vs local `summary of MACS2` / `toolshed.g2.bx.psu.edu/repos/bgruening/text_processing/tp_grep_tool/9.5+galaxy0`
- Step order `11`: baseline `MultiQC` / `toolshed.g2.bx.psu.edu/repos/iuc/multiqc/multiqc/1.27+galaxy3` vs local `Bigwig from MACS2` / `wig_to_bigWig`
