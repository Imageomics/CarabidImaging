<div align="center">

# 🪲 BioREPO Detection Pipeline

**Large-scale, zero-shot detection & extraction of biological specimens, color palettes, and scalebars from tray images**

<p>
  <img alt="Python" src="https://img.shields.io/badge/Python-3.12-blue?logo=python&logoColor=white">
  <img alt="PyTorch" src="https://img.shields.io/badge/PyTorch-2.1%2B-ee4c2c?logo=pytorch&logoColor=white">
  <img alt="Transformers" src="https://img.shields.io/badge/🤗%20Transformers-4.44%E2%80%93%3C5-yellow">
</p>

</div>

---

## 📖 Overview

The detection pipeline for turning raw, high-resolution **carabid beetle tray scans** into clean, structured datasets. It runs three independent detectors, each targeting a different object class in the tray:

| Module | Target | Model | 
|-----|-----|-----|
| 🪲 **Beetle detection** | Individual specimens | Grounding DINO (local GPU) | 
| 🎨 **Colorpicker detection** | Color-calibration palettes | Moondream (cloud API) | 
| 📏 **Scalebar detection** | Centimeter reference bars | Moondream (cloud API) |

Every module is **zero-shot** (no training/fine-tuning required), is built for
**SLURM** parallelism, and ships a **human-in-the-loop** review path.

---

## ✨ Key Features

- **Zero-shot specimen detection** with `IDEA-Research/grounding-dino-base` and an
  **iterative confidence sweep** (0.30 → 0.10). Each pass accumulates new boxes,
  masks them, and continues at lower thresholds to recover faint specimens.
- **Split-tray handling.** Images whose filename contains `-and-` are treated as
  two stacked trays; each half is processed independently by masking the other
  half to the ImageNet mean.
- **Geometric de-duplication.** Custom **IoU** and **containment-ratio** filters
  drop overlapping and nested boxes; oversized boxes (> 5 % of image area) are
  discarded as non-specimens.
- **Reading-order output.** Crops are sorted top-to-bottom, left-to-right so crop
  indices line up with physical tray layout.
- **Rate-limit-aware cloud detection.** Moondream calls use jittered sleeps and
  exponential backoff on HTTP 429.
- **Hallucination guard (scalebar).** Any box larger than 10 % of the image is
  rejected as a hallucination.
- **Human-in-the-loop verification.** Ambiguous results (zero boxes, conflicting
  boxes, or single low-confidence boxes) are routed to a `Plotted_Recheck/`
  folder for fast visual triage.

---

## 🗂️ Repository Layout

```
detection-pipeline/
├── detection_beetles.py       # Specimen detection (Grounding DINO)
├── detection_colorpicker.py   # Color-palette detection (Moondream)
├── detection_scalebar.py      # Scalebar detection (Moondream)
├── requirements.txt
└── README.md
```

---

## 🛠️ Installation

```bash
# 1. Clone
git clone https://github.com/Imageomics/CarabidImaging
cd CarabidImaging/detection-pipeline

# 2. Create an isolated environment (Python 3.12)
python -m venv detection_env
source detection_env/bin/activate

# 3. Install dependencies
pip install --upgrade pip
pip install -r requirements.txt
```

> **On OSC:** load Python before creating the venv, e.g. `module load python/3.12`.
> Beetle detection needs a GPU node (A100/H100 recommended); the Moondream modules run on CPU.

---

## 🔐 Credentials & Security (read this first)

The pipeline needs two secrets, both read from the environment:

| Variable | Used by | Where to get it |
|---|---|---|
| `HF_TOKEN` | beetle detection | huggingface.co → Settings → Access Tokens |
| `MOONDREAM_API_KEY` | colorpicker + scalebar | moondream.ai console |

Export them in your shell or inside your SLURM script — **never commit them:**

```bash
export HF_TOKEN="hf_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
export MOONDREAM_API_KEY="eyJhbGciOi..."
```

> [!WARNING]
> **Do not hardcode tokens in `.sh` files that are tracked by git.** A leaked
> Hugging Face token or Moondream key is live the instant it is pushed. Keep them
> in your environment (or a shell profile / `.env` that is git-ignored), and if a
> key was ever committed, **revoke and rotate it immediately.**


---

## 📥 Input Data

Point the modules at a directory of `.jpg` / `.jpeg` / `.png` tray images
(searched **recursively**).

**Beetle detection additionally requires a ground-truth metadata file** (`.csv`
or `.json`) with these two columns:

| Column | Meaning |
|---|---|
| `imageID` | Image filename, e.g. `TRAY_00123.jpg` |
| `NumberOfBeetlesInTray` | Expected specimen count (used for accuracy logging) |

Missing or `inf` counts are treated as unknown (`NaN`) and simply left blank in
the results — they do not stop processing.

---

## 🧠 Modules

### 1 · Beetle Detection — `detection_beetles.py`

Detects and crops individual specimens using Grounding DINO.

**Pipeline per image:** load & verify → split trays if `-and-` in filename →
iterative threshold sweep (each pass masks the boxes found so far and re-detects
at a lower threshold) → size filter (≤ 5 % area) → IoU + containment filtering
→ optional LLaVA completeness check → reading-order sort → save crops, plotted
tray (routed to `Good/` or `Recheck/`), and count record.

Trays with zero detections, or where LLaVA reports a beetle left unmasked, are
routed to `Recheck/`. Results are appended to the CSV one tray at a time, so
rerunning with the same `--output-dir` resumes where the previous run stopped.

```bash
python detection_beetles.py \
    --image-dir     /path/to/images/ \
    --output-dir    /path/to/output/ \
    --metadata-file /path/to/metadata.csv
```

| Argument | Required | Description |
|---|:--:|---|
| `--image-dir` | ✅ | Root directory of tray images (recursive) |
| `--output-dir` | ✅ | Destination for crops, plots, and CSV |
| `--metadata-file` | ✅ | Ground-truth CSV/JSON (`imageID`, `NumberOfBeetlesInTray`) |
| `--no-llava` | | Skip the LLaVA completeness check |

> ℹ️ By default, a LLaVA-Next model (`llava-v1.6-mistral-7b-hf`) checks each
> masked tray for missed beetles. Pass `--no-llava` to skip this check and avoid
> the additional model download and GPU-memory use.

---

### 2 · Colorpicker Detection — `detection_colorpicker.py`

Locates the color-calibration palette with Moondream, querying two prompts
(`"a color palette"`, `"a colorpicker"`) and reconciling the results.

**Decision logic:** both prompts agree (IoU ≥ 0.75) → merge boxes, mark **Good**.
Otherwise → keep the smaller box and flag for **Recheck**. Images under a
`SmallBeetles` path/name are skipped. **Resumable**, same as the scalebar module.

```bash
python detection_colorpicker.py \
    --image_dir  /path/to/images/ \
    --output_dir /path/to/output/ \
    --task_id    0 \
    --num_tasks  8
```

| Argument | Default | Description |
|---|:--:|---|
| `--image_dir` | — | Root directory of images (recursive) |
| `--output_dir` | — | Destination for plots and per-task CSV |
| `--task_id` | 0 | This worker's index in the array |
| `--num_tasks` | 1 | Total workers (controls chunk size) |

---

### 3 · Scalebar Detection — `detection_scalebar.py`

Locates the centimeter scalebar with Moondream, with an extra guard against
hallucinated giant boxes.

**Decision logic:** two agreeing boxes (IoU ≥ 0.6) → merge, mark **Good**.
Any box > 10 % of image area is dropped as a hallucination; if a single valid box
remains it is kept but flagged **Recheck**; non-overlapping valid boxes → keep the
smaller, flag **Recheck**. **Resumable** — images already present in
`Plotted_Good/` or `Plotted_Recheck/` are skipped.

```bash
python detection_scalebar.py \
    --image_dir  /path/to/images/ \
    --output_dir /path/to/output/ \
    --task_id    0 \
    --num_tasks  8
```

Arguments are identical to the colorpicker module.

> ⚠️ **Argument-flag convention differs by module.** Beetle detection uses
> **hyphens** (`--image-dir`, `--output-dir`, `--metadata-file`); the Moondream
> modules use **underscores** (`--image_dir`, `--output_dir`). Copy the exact form
> shown for each script.

---

## 📤 Outputs

### Beetle detection
```
<output-dir>/
├── Detection_results.csv        # one row per tray, appended as each tray finishes
├── BadImages.txt                # corrupted/unreadable images that were skipped
├── cropped_images/
│   └── <tray_name>/
│       ├── <tray_name>_1.png     # crops in reading order
│       └── <tray_name>_2.png
└── plotted_trays/                # full tray with red bounding boxes
    ├── Good/
    │   └── <tray_name>.png
    └── Recheck/                  # zero detections or LLaVA flagged missed beetles
        └── <tray_name>.png
```

**CSV columns (beetle module):** `image_path`, `filename`, `actual`, `detected`,
`llava_says_more`, `verify` (`True` = routed to `Recheck/`), `pass_log`
(threshold and new boxes per pass), `detections` (boxes).

### Colorpicker & scalebar
```
<output-dir>/
├── Colorpickers_task_<id>.csv    # (or Scalebars_task_<id>.csv) per-task log
├── Plotted_Good/                 # single high-confidence detection
└── Plotted_Recheck/              # needs human review (0 / conflicting / low-conf)
```

**CSV columns (Moondream modules):** `image_name`, `plotted_image`,
`num_<object>s`, `<object>_coords`, `verify` (`True` = needs review).

---

## 🖥️ Running on SLURM

The Moondream modules parallelize by splitting the sorted image list into
`num_tasks` contiguous chunks; each array task processes chunk `task_id`. To scale
up, raise **both** the `#SBATCH --array` range **and** `--num_tasks` so they match:

```bash
#SBATCH --array=0-15      # 16 workers
...
    --num_tasks=16
```

Because chunking is index-based, keep the source image directory **stable** across
a run (adding/removing files mid-run shifts the chunk boundaries).

---


## 🔧 Tunable Parameters

| Parameter | Module | Default | Effect |
|---|---|:--:|---|
| Adaptive threshold range | beetle | 0.30 → 0.10, step 0.05 | Confidence sweep for detection |
| `text_threshold` | beetle | 0.20 | Grounding DINO text-match strictness |
| Max box size ratio | beetle | 0.05 | Rejects boxes larger than 5 % of image |
| IoU / containment thresholds | beetle | 0.40 / 0.60 | Overlap & nesting de-duplication |
| Merge IoU | colorpicker / scalebar | 0.75 / 0.60 | Agreement needed to merge two prompts |
| Max area (hallucination cap) | scalebar | 0.10 | Rejects boxes > 10 % of image |

---

## 📝 Notes

- All detectors are zero-shot; there is **no training step**.
- Beetle detection runs locally on GPU; colorpicker and scalebar call the
  **Moondream cloud API** and therefore require network access from compute nodes.
- All three modules write their CSVs incrementally and are resumable. The beetle
  module skips trays already logged in `Detection_results.csv`; the Moondream
  modules skip images already present in `Plotted_Good/` or `Plotted_Recheck/`.
  A plotted image is only kept once its CSV row has been written, so a failed
  write is retried on the next run.

---
