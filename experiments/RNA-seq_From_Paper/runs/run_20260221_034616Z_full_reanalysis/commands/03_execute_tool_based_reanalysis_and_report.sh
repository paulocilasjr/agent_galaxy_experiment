#!/bin/sh
set -eu
python3 - <<'PY'
import csv
import io
import json
import time
from datetime import datetime, timezone
from pathlib import Path

import requests

run = Path("experiments/RNA-seq_From_Paper/runs/run_20260221_034616Z_full_reanalysis")
api_dir = run / "api"
cfg_dir = run / "configs"
out_dir = run / "outputs"
meta_dir = run / "metadata"
inputs_dir = run / "inputs" / "count_based"
for d in (api_dir, cfg_dir, out_dir, meta_dir, inputs_dir):
    d.mkdir(parents=True, exist_ok=True)


def load_env(path: Path):
    env = {}
    for raw in path.read_text().splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        k, v = line.split("=", 1)
        env[k.strip()] = v.strip().strip('"').strip("'")
    return env


def save_json(path: Path, obj):
    path.write_text(json.dumps(obj, indent=2, sort_keys=True) + "\n")


def req_json(method, url, headers, *, params=None, payload=None, timeout=300):
    r = requests.request(method, url, headers=headers, params=params, json=payload, timeout=timeout)
    if r.status_code >= 400:
        raise RuntimeError(f"{method} {url} failed: {r.status_code} {r.text[:500]}")
    return r.json()


def parse_float(v):
    try:
        if v is None:
            return None
        s = str(v).strip()
        if s == "" or s.lower() in ("na", "nan", "none", "null"):
            return None
        return float(s)
    except Exception:
        return None


def normalize_gene_name(v):
    return (v or "").strip().upper()


def run_tool_and_poll(
    *,
    base: str,
    headers: dict,
    history_id: str,
    tool_id: str,
    inputs: dict,
    cfg_path: Path,
    submit_path: Path,
    poll_prefix: str,
):
    payload = {"history_id": history_id, "tool_id": tool_id, "inputs": inputs}
    save_json(cfg_path, payload)
    r = requests.post(f"{base}/api/tools", headers=headers, json=payload, timeout=300)
    if r.status_code >= 400:
        raise RuntimeError(f"Tool submit failed for {tool_id}: {r.status_code} {r.text[:600]}")
    submitted = r.json()
    save_json(submit_path, submitted)

    out_by_name = {o.get("output_name"): o.get("id") for o in submitted.get("outputs", []) if o.get("id")}
    out_ids = [o_id for o_id in out_by_name.values() if o_id]
    if not out_ids:
        raise RuntimeError(f"Tool {tool_id} produced no direct outputs")

    latest = {}
    for poll in range(1, 721):
        snap = {"poll": poll, "tool_id": tool_id, "outputs": []}
        done = True
        for out_name, out_id in out_by_name.items():
            if not out_id:
                continue
            d = req_json("GET", f"{base}/api/histories/{history_id}/contents/{out_id}", headers)
            latest[out_name] = d
            st = d.get("state")
            snap["outputs"].append(
                {
                    "output_name": out_name,
                    "id": out_id,
                    "state": st,
                    "name": d.get("name"),
                    "misc_info": d.get("misc_info"),
                }
            )
            if st not in ("ok", "error", "failed_metadata", "discarded"):
                done = False
        save_json(api_dir / f"{poll_prefix}_{poll:03d}.json", snap)
        if done:
            break
        time.sleep(5)
    return out_by_name, latest


env = load_env(Path(".env"))
base = env.get("GALAXY_URL", "https://usegalaxy.org").rstrip("/")
key = env.get("GALAXY_API_KEY")
if not key:
    raise SystemExit("GALAXY_API_KEY missing in .env")
headers = {"x-api-key": key}

# Public paper histories (non-purged source datasets).
santana_history = "bbd44e69cb8906b5db3aaed71bf2d1f1"  # prjna904261-perm
wang_history = "bbd44e69cb8906b5a2336651a2753df4"  # prjna1086003-perm

counts = {
    # Santana
    "SRR22376031": {"source_history": santana_history, "hda_id": "f9cad7b01a4721352391cc0e3811e368"},
    "SRR22376032": {"source_history": santana_history, "hda_id": "f9cad7b01a47213591221e4b6f3eafc5"},
    "SRR22376029": {"source_history": santana_history, "hda_id": "f9cad7b01a472135d47590d3dfdd8998"},
    "SRR22376030": {"source_history": santana_history, "hda_id": "f9cad7b01a47213529cc42d5ef3efac3"},
    "SRR22376027": {"source_history": santana_history, "hda_id": "f9cad7b01a472135839f6aba28e14b4d"},
    "SRR22376028": {"source_history": santana_history, "hda_id": "f9cad7b01a4721357948a31d72ead3e4"},
    # Wang in vitro
    "SRR28790270": {"source_history": wang_history, "hda_id": "f9cad7b01a47213536dad3ab719e2798"},
    "SRR28790272": {"source_history": wang_history, "hda_id": "f9cad7b01a47213507fad9e3c895b967"},
    "SRR28790274": {"source_history": wang_history, "hda_id": "f9cad7b01a47213501e4f21612bc975b"},
    "SRR28790276": {"source_history": wang_history, "hda_id": "f9cad7b01a4721353dec8b5735f1860c"},
    "SRR28790278": {"source_history": wang_history, "hda_id": "f9cad7b01a4721358483fe9162a6712a"},
    "SRR28790280": {"source_history": wang_history, "hda_id": "f9cad7b01a47213577e9eeadcd451a0d"},
    # Wang in vivo
    "SRR28791430": {"source_history": wang_history, "hda_id": "f9cad7b01a472135c5baf644277fc974"},
    "SRR28791431": {"source_history": wang_history, "hda_id": "f9cad7b01a4721351ed14018a0ab2eb7"},
    "SRR28791432": {"source_history": wang_history, "hda_id": "f9cad7b01a4721356643ca8eef8da196"},
    "SRR28791433": {"source_history": wang_history, "hda_id": "f9cad7b01a472135332205af055089ae"},
    "SRR28791434": {"source_history": wang_history, "hda_id": "f9cad7b01a472135f3554823b538e917"},
    "SRR28791437": {"source_history": wang_history, "hda_id": "f9cad7b01a472135ba99249e5426401d"},
    "SRR28791438": {"source_history": wang_history, "hda_id": "f9cad7b01a472135110eeb2772e6d872"},
}

gtf_source = {"source_history": wang_history, "hda_id": "f9cad7b01a472135d39caf31137cbae0"}
gtf_name = "GCA_002759435.3_Cand_auris_B8441_V3.ncbiGene.gtf.gz"

comparisons = [
    {
        "key": "santana_tnSWI1_vs_AR0382_WT",
        "study": "Santana et al. 2023",
        "changed_label": "tnSWI1",
        "reference_label": "AR0382_WT",
        "changed_srrs": ["SRR22376027", "SRR22376028"],
        "reference_srrs": ["SRR22376031", "SRR22376032"],
        "padj_threshold": 0.05,
        "lfc_threshold": 1.0,
        "published": {
            "r2": 0.94,
            "direction_agreement_pct": 99.0,
            "scf1_log2fc": -6.68,
            "mapped_genes": 203,
        },
    },
    {
        "key": "santana_AR0387_WT_vs_AR0382_WT",
        "study": "Santana et al. 2023",
        "changed_label": "AR0387_WT",
        "reference_label": "AR0382_WT",
        "changed_srrs": ["SRR22376029", "SRR22376030"],
        "reference_srrs": ["SRR22376031", "SRR22376032"],
        "padj_threshold": 0.05,
        "lfc_threshold": 1.0,
        "published": {
            "r2": 0.89,
            "direction_agreement_pct": 97.0,
            "scf1_log2fc": -7.25,
            "mapped_genes": 165,
        },
    },
    {
        "key": "wang_AR0382_in_vitro_vs_AR0387_in_vitro",
        "study": "Wang et al. 2024",
        "changed_label": "AR0382_in_vitro",
        "reference_label": "AR0387_in_vitro",
        "changed_srrs": ["SRR28790270", "SRR28790272", "SRR28790274"],
        "reference_srrs": ["SRR28790276", "SRR28790278", "SRR28790280"],
        "padj_threshold": 0.01,
        "lfc_threshold": 1.0,
        "published": {
            "r2": 0.98,
            "direction_agreement_pct": 100.0,
            "deg_count": 76,
            "scf1_log2fc": 8.61,
            "als4112_log2fc": 5.07,
        },
    },
    {
        "key": "wang_AR0382_in_vivo_vs_AR0387_in_vivo",
        "study": "Wang et al. 2024",
        "changed_label": "AR0382_in_vivo",
        "reference_label": "AR0387_in_vivo",
        "changed_srrs": ["SRR28791430", "SRR28791431", "SRR28791432"],
        "reference_srrs": ["SRR28791433", "SRR28791434", "SRR28791437", "SRR28791438"],
        "padj_threshold": 0.01,
        "lfc_threshold": 1.0,
        "published": {
            "r2": 0.9998,
            "direction_agreement_pct": 100.0,
            "deg_count": 259,
            "scf1_log2fc": 4.47,
            "als4112_log2fc": 2.56,
        },
    },
]

stamp = datetime.now(timezone.utc).strftime("%Y%m%d_%H%M%SZ")
history_name = f"RNA-seq_From_Paper_tool_based_{stamp}"
history = req_json("POST", f"{base}/api/histories", headers, payload={"name": history_name})
save_json(api_dir / "30_create_history_tool_based.json", history)
history_id = history["id"]

# Download source files from paper histories.
download_manifest = []
for srr, meta in sorted(counts.items()):
    name = f"{srr}_counts.tsv"
    url = f"{base}/api/histories/{meta['source_history']}/contents/{meta['hda_id']}/display?to_ext=tabular"
    r = requests.get(url, headers=headers, timeout=180)
    if r.status_code >= 400:
        raise RuntimeError(f"Failed to download source count table {srr}: {r.status_code} {r.text[:200]}")
    p = inputs_dir / name
    p.write_text(r.text)
    download_manifest.append({"name": name, "path": str(p), "source_url": url})

gtf_url = f"{base}/api/histories/{gtf_source['source_history']}/contents/{gtf_source['hda_id']}/display"
r_gtf = requests.get(gtf_url, headers=headers, timeout=180)
if r_gtf.status_code >= 400:
    raise RuntimeError(f"Failed to download GTF: {r_gtf.status_code} {r_gtf.text[:200]}")
gtf_path = inputs_dir / gtf_name
gtf_path.write_bytes(r_gtf.content)
download_manifest.append({"name": gtf_name, "path": str(gtf_path), "source_url": gtf_url})
save_json(cfg_dir / "30_download_manifest_tool_based.json", {"files": download_manifest})

# Upload local files to the new history.
uploaded_ids = []
for i, entry in enumerate(download_manifest, start=1):
    name = entry["name"]
    path = Path(entry["path"])
    form_data = {
        "history_id": history_id,
        "tool_id": "upload1",
        "files_0|NAME": name,
        "files_0|type": "upload_dataset",
    }
    with path.open("rb") as fh:
        resp = requests.post(
            f"{base}/api/tools",
            headers=headers,
            data=form_data,
            files={"files_0|file_data": (name, fh)},
            timeout=300,
        )
    if resp.status_code >= 400:
        raise RuntimeError(f"Upload failed for {name}: {resp.status_code} {resp.text[:400]}")
    obj = resp.json()
    save_json(api_dir / f"31_upload_local_{i:02d}_{name}.json", obj)
    for out in obj.get("outputs", []):
        uploaded_ids.append(out["id"])

uploaded = {}
for poll in range(1, 301):
    snap = {"poll": poll, "datasets": []}
    all_terminal = True
    for did in uploaded_ids:
        d = req_json("GET", f"{base}/api/histories/{history_id}/contents/{did}", headers)
        uploaded[did] = d
        st = d.get("state")
        snap["datasets"].append({"id": did, "name": d.get("name"), "state": st})
        if st not in ("ok", "error", "failed_metadata", "discarded"):
            all_terminal = False
    save_json(api_dir / f"32_upload_poll_tool_based_{poll:03d}.json", snap)
    if all_terminal:
        break
    time.sleep(3)

failed = [d for d in uploaded.values() if d.get("state") != "ok"]
if failed:
    save_json(api_dir / "32b_upload_failures_tool_based.json", {"failed": failed})
    raise RuntimeError(f"Upload failures in tool-based run: {len(failed)}")

name_to_id = {d.get("name"): did for did, d in uploaded.items()}
gtf_hda_id = name_to_id[gtf_name]

DESEQ2_ID = "toolshed.g2.bx.psu.edu/repos/iuc/deseq2/deseq2/2.11.40.8+galaxy2"
DEG_ANNOTATE_ID = "toolshed.g2.bx.psu.edu/repos/iuc/deg_annotate/deg_annotate/1.1.0+galaxy1"
VOLCANO_ID = "toolshed.g2.bx.psu.edu/repos/iuc/volcanoplot/volcanoplot/4.0.1+galaxy0"

records = []

for c in comparisons:
    changed_refs = {"values": [{"src": "hda", "id": name_to_id[f"{srr}_counts.tsv"]} for srr in c["changed_srrs"]]}
    reference_refs = {"values": [{"src": "hda", "id": name_to_id[f"{srr}_counts.tsv"]} for srr in c["reference_srrs"]]}

    deseq_inputs = {
        "select_data|how": "datasets_per_level",
        "select_data|rep_factorName_0|factorName": "DEFactor",
        "select_data|rep_factorName_0|rep_factorLevel_0|factorLevel": "MainFactor",
        "select_data|rep_factorName_0|rep_factorLevel_0|countsFile": changed_refs,
        "select_data|rep_factorName_0|rep_factorLevel_1|factorLevel": "BaseFactor",
        "select_data|rep_factorName_0|rep_factorLevel_1|countsFile": reference_refs,
        "header": False,
        "tximport|tximport_selector": "count",
        "advanced_options|fit_type": "1",
        "advanced_options|outlier_replace_off": False,
        "advanced_options|outlier_filter_off": False,
        "advanced_options|auto_mean_filter_off": False,
        "advanced_options|prefilter_conditional|prefilter": "",
        "advanced_options|use_beta_priors": False,
        "output_options|alpha_ma": c["padj_threshold"],
        "output_options|output_selector": ["pdf", "normCounts"],
    }
    de_by_name, de_latest = run_tool_and_poll(
        base=base,
        headers=headers,
        history_id=history_id,
        tool_id=DESEQ2_ID,
        inputs=deseq_inputs,
        cfg_path=cfg_dir / f"40_deseq2_payload_{c['key']}.json",
        submit_path=api_dir / f"40_deseq2_submit_{c['key']}.json",
        poll_prefix=f"40_deseq2_poll_{c['key']}",
    )
    de_result_id = de_by_name.get("deseq_out")
    de_state = (de_latest.get("deseq_out") or {}).get("state")
    if de_state != "ok":
        raise RuntimeError(
            f"DESeq2 failed for {c['key']}: state={de_state}, "
            f"misc={(de_latest.get('deseq_out') or {}).get('misc_info')}"
        )

    annotate_inputs = {
        "input_table": {"src": "hda", "id": de_result_id},
        "mode": "degseq",
        "annotation": {"src": "hda", "id": gtf_hda_id},
        "advanced_parameters|gff_feature_type": "exon",
        "advanced_parameters|gff_feature_attribute": "gene_id",
        "advanced_parameters|gff_transcript_attribute": "transcript_id",
        "advanced_parameters|gff_attributes": "gene_biotype, gene_name",
    }
    an_by_name, an_latest = run_tool_and_poll(
        base=base,
        headers=headers,
        history_id=history_id,
        tool_id=DEG_ANNOTATE_ID,
        inputs=annotate_inputs,
        cfg_path=cfg_dir / f"41_annotate_payload_{c['key']}.json",
        submit_path=api_dir / f"41_annotate_submit_{c['key']}.json",
        poll_prefix=f"41_annotate_poll_{c['key']}",
    )
    ann_id = an_by_name.get("output")
    ann_state = (an_latest.get("output") or {}).get("state")
    if ann_state != "ok":
        raise RuntimeError(
            f"deg_annotate failed for {c['key']}: state={ann_state}, "
            f"misc={(an_latest.get('output') or {}).get('misc_info')}"
        )

    volcano_inputs = {
        "input": {"src": "hda", "id": ann_id},
        "with_header|header": "no",
        "with_header|fdr_col": "7",
        "with_header|pval_col": "6",
        "with_header|lfc_col": "3",
        "with_header|label_col": "13",
        "signif_thresh": c["padj_threshold"],
        "lfc_thresh": c["lfc_threshold"],
        "labels|label_select": "signif",
        "labels|top_num": 10,
        "plot_options|boxes": False,
        "plot_options|legend_labs": "Down,Not Sig,Up",
        "out_options|rscript_out": False,
    }
    vol_by_name, vol_latest = run_tool_and_poll(
        base=base,
        headers=headers,
        history_id=history_id,
        tool_id=VOLCANO_ID,
        inputs=volcano_inputs,
        cfg_path=cfg_dir / f"42_volcano_payload_{c['key']}.json",
        submit_path=api_dir / f"42_volcano_submit_{c['key']}.json",
        poll_prefix=f"42_volcano_poll_{c['key']}",
    )
    plot_state = (vol_latest.get("plot") or {}).get("state")
    if plot_state != "ok":
        raise RuntimeError(
            f"volcanoplot failed for {c['key']}: state={plot_state}, "
            f"misc={(vol_latest.get('plot') or {}).get('misc_info')}"
        )

    records.append(
        {
            "comparison_key": c["key"],
            "deseq2_result_id": de_by_name.get("deseq_out"),
            "deseq2_plots_id": de_by_name.get("plots"),
            "deseq2_counts_id": de_by_name.get("counts_out"),
            "annotated_result_id": ann_id,
            "volcano_plot_id": vol_by_name.get("plot"),
        }
    )


summary_rows = []
for c in comparisons:
    rec = next(r for r in records if r["comparison_key"] == c["key"])
    ann_text = requests.get(
        f"{base}/api/histories/{history_id}/contents/{rec['annotated_result_id']}/display",
        headers=headers,
        timeout=300,
    ).text
    ann_path = out_dir / f"{c['key']}__annotated_deseq2_results.tsv"
    ann_path.write_text(ann_text)

    deseq_text = requests.get(
        f"{base}/api/histories/{history_id}/contents/{rec['deseq2_result_id']}/display",
        headers=headers,
        timeout=300,
    ).text
    (out_dir / f"{c['key']}__deseq2_results.tsv").write_text(deseq_text)

    # deg_annotate output has no header in this mode.
    rows = []
    for raw in csv.reader(io.StringIO(ann_text), delimiter="\t"):
        if not raw:
            continue
        rows.append(raw)

    deg_count = 0
    scf1_lfc = None
    als4112_lfc = None
    for r in rows:
        if len(r) < 13:
            continue
        gene_id = r[0].strip()
        lfc = parse_float(r[2])
        padj = parse_float(r[6])
        gene_name = normalize_gene_name(r[12])
        if lfc is not None and padj is not None and padj < c["padj_threshold"] and abs(lfc) >= c["lfc_threshold"]:
            deg_count += 1
        if lfc is None:
            continue
        if gene_name == "SCF1" or gene_id in ("B9J08_03708", "B9J08_001458"):
            scf1_lfc = lfc
        if gene_name == "ALS4112":
            als4112_lfc = lfc

    pub = c["published"]
    summary_rows.append(
        {
            "comparison_key": c["key"],
            "study": c["study"],
            "changed_label": c["changed_label"],
            "reference_label": c["reference_label"],
            "observed_deg_count_thresholded": deg_count,
            "published_deg_count_thresholded": pub.get("deg_count"),
            "observed_scf1_log2fc": scf1_lfc,
            "published_scf1_log2fc": pub.get("scf1_log2fc"),
            "delta_scf1_log2fc": None if (scf1_lfc is None or pub.get("scf1_log2fc") is None) else scf1_lfc - pub.get("scf1_log2fc"),
            "observed_als4112_log2fc": als4112_lfc,
            "published_als4112_log2fc": pub.get("als4112_log2fc"),
            "delta_als4112_log2fc": None
            if (als4112_lfc is None or pub.get("als4112_log2fc") is None)
            else als4112_lfc - pub.get("als4112_log2fc"),
            "published_r2": pub.get("r2"),
            "published_direction_agreement_pct": pub.get("direction_agreement_pct"),
            "published_mapped_genes": pub.get("mapped_genes"),
        }
    )

save_json(out_dir / "paper_vs_observed_summary_tool_based.json", {"rows": summary_rows})
with (out_dir / "paper_vs_observed_summary_tool_based.csv").open("w", newline="") as fh:
    w = csv.DictWriter(fh, fieldnames=list(summary_rows[0].keys()))
    w.writeheader()
    w.writerows(summary_rows)

md = []
md.append("# RNA-seq From Paper: Tool-Equivalent DE Reanalysis Report")
md.append("")
md.append(f"- generated_utc: `{datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')}`")
md.append(f"- galaxy_url: `{base}`")
md.append(f"- history_name: `{history_name}`")
md.append(f"- history_id: `{history_id}`")
md.append("")
md.append("## Execution Method")
md.append("")
md.append("- Created a new Galaxy history and uploaded the same count tables and GTF used in the paper histories.")
md.append("- Workflow invocations for `rnaseq-de-filtering-plotting.ga` remained in `state=new` with 0 populated steps on this account.")
md.append("- Executed the same tool chain directly via API per contrast: DESeq2 -> deg_annotate -> volcanoplot.")
md.append("")
md.append("## Comparison Against Published Values")
md.append("")
md.append("| comparison | observed DEG count (thresholded) | published DEG count | observed SCF1 log2FC | published SCF1 log2FC | observed ALS4112 log2FC | published ALS4112 log2FC | published R2 | published direction agreement |")
md.append("|---|---:|---:|---:|---:|---:|---:|---:|---:|")
for r in summary_rows:
    md.append(
        "| {comparison_key} | {observed_deg_count_thresholded} | {published_deg_count_thresholded} | {observed_scf1_log2fc} | {published_scf1_log2fc} | {observed_als4112_log2fc} | {published_als4112_log2fc} | {published_r2} | {published_direction_agreement_pct} |".format(
            **r
        )
    )
md.append("")
md.append("## Notes")
md.append("")
md.append("- Published R2/direction-agreement values come from Anton et al. 2025 and are included for reference.")
md.append("- Exact recomputation of published R2 requires the publication supplementary fold-change tables as explicit inputs.")
md.append("- `ALS4112` may remain unresolved if absent from this GTF annotation's `gene_name` attribute values.")

(out_dir / "paper_vs_observed_report_tool_based.md").write_text("\n".join(md) + "\n")

save_json(
    meta_dir / "tool_based_run_ids.json",
    {
        "history_name": history_name,
        "history_id": history_id,
        "records": records,
    },
)

manifest_path = run / "run_manifest.yaml"
manifest_lines = manifest_path.read_text().splitlines()
out_manifest = []
for line in manifest_lines:
    if line.startswith("status:"):
        out_manifest.append("status: completed")
    elif line.startswith("tool_name:"):
        out_manifest.append('tool_name: "DESeq2 + deg_annotate + volcanoplot (workflow-equivalent)"')
    elif line.startswith("tool_id:"):
        out_manifest.append('tool_id: "toolshed.g2.bx.psu.edu/repos/iuc/deseq2/deseq2/2.11.40.8+galaxy2"')
    elif line.startswith("tool_version:"):
        out_manifest.append('tool_version: "2.11.40.8+galaxy2"')
    elif line.startswith("history_name:"):
        out_manifest.append(f'history_name: "{history_name}"')
    elif line.startswith("history_id:"):
        out_manifest.append(f'history_id: "{history_id}"')
    else:
        out_manifest.append(line)
manifest_path.write_text("\n".join(out_manifest) + "\n")

with (run / "journal.md").open("a") as j:
    j.write(f"\n### {datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')} - Tool-equivalent reanalysis completed\n")
    j.write(f"- Created history `{history_name}` (`{history_id}`).\n")
    j.write("- Uploaded 19 count tables + GTF from paper public histories.\n")
    j.write("- Executed DESeq2 + annotation + volcano for all 4 contrasts.\n")
    j.write("- Report: `outputs/paper_vs_observed_report_tool_based.md`.\n")

print(json.dumps({"history_id": history_id, "history_name": history_name, "comparisons": [c["key"] for c in comparisons]}, indent=2))
PY
