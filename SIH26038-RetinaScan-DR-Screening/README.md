# SIH26038 — RetinaScan: Explainable AI Diabetic Retinopathy Screening (MathWorks)

MATLAB-based retinal screening pipeline for rural India: quality gate →
segmentation → severity grading → Grad-CAM explainability → Simulink
telemedicine workflow optimization.

**Target band:** referable DR (Level ≥2) sensitivity >90%, specificity >85% on
validation; cross-dataset check on Messidor.

## Pipeline

```
fundus photo (portable camera / phone adapter)
   │
   ├─ M1 Quality gate (preprocess_fundus.m) ── reject? → recapture feedback
   │        └── enhancement: Ben-Graham crop + CLAHE + illumination flattening
   ├─ M2 Segmentation (vessels/OD/fovea classical; lesions = U-Net on IDRiD)
   ├─ M3 Severity grading (EfficientNetB0, trained on APTOS in Colab → ONNX →
   │        MATLAB importONNXNetwork). Threshold tuned for sens>90/spec>85.
   ├─ M4 Explainability: gradCAM() heatmap + lesion overlay + calibrated
   │        confidence + annotated PDF report (<30s ophthalmologist review)
   └─ M5 Simulink/SimEvents district screening simulation (100k+ patients/yr)
```

## Repo layout

| Path | What |
|---|---|
| `docs/ps_analysis.md` | PS requirements → module mapping |
| `data/DATASETS.md` | dataset links, split rules, storage layout |
| `matlab/preprocess_fundus.m` | Module 1: quality gate + enhancement (runnable) |
| `notebooks/` | Colab training notebooks (PyTorch → ONNX export) |
| `scripts/` | split preparation, threshold tuning, metrics |

## Week plan (submission 20 Sept 2026)

- **W1 (26 Aug–1 Sep):** MathWorks/SIH license · MATLAB+DL onramps · download
  APTOS+IDRiD · run M1 on APTOS subset
- **W2 (2–8 Sep):** Colab training → sens/spec threshold table → Grad-CAM →
  calibration → M2 lesion pipeline
- **W3 (9–15 Sep):** App Designer GUI + PDF report + SimEvents model + Hindi UI
- **W4 (16–20 Sep):** 3-min demo video + 7-slide PPT → submit

## Team roles (6)
ML lead · MATLAB/app dev · CV/preprocessing · Simulink+reports ·
data/validation · product/PPT (≥1 female member).
