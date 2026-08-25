# SIH26038 — PS Breakdown → Module Map (verbatim requirements → our build)

Org: **MathWorks** · Theme: Clean & Green Technology · Category: Software
Named toolboxes: Image Processing, Computer Vision, Deep Learning, Medical Imaging,
Simulink, Statistics & ML.

## The PS literally demands 5 modules

### M1 · Image Quality Assessment & Enhancement
> "evaluate fundus images for adequacy (focus, illumination, field of view).
> Apply adaptive enhancement (CLAHE, illumination normalization, denoising);
> reject ungradeable ones with recapture feedback."

**Build:** `matlab/preprocess_fundus.m` — blur score (Laplacian variance),
illumination stats, FOV mask coverage → GRADEABLE / ENHANCED / REJECT+reason.
Ben-Graham crop, CLAHE on L-channel, Gaussian illumination flattening.

### M2 · Retinal Structure Segmentation
> "optic disc/fovea localization, vessel segmentation, microaneurysm detection,
> exudate segmentation, hemorrhage classification, neovascularization detection."

**Build:** Frangi vesselness (vessels), intensity+centre priors (OD/fovea),
morphological candidates + small U-Net fine-tuned on **IDRiD lesion masks**
(exudates, hemorrhages, microaneurysms). Output candidate maps that later feed
the explainability overlay.

### M3 · DR Severity Grading (0–4)
> "clinically acceptable sensitivity (>90%) and specificity (>85%) for
> referable DR (Level 2+)."

**Build:** EfficientNetB0/ResNet50 transfer learning on **APTOS 2019**.
Binary referable head tuned by decision-threshold search on the val split.
Metrics to publish: QWK (5-class), sens/spec/AUC (referable),
confusion matrix, external check on **Messidor**. Temperature-scaled confidence.

### M4 · Explainability Module
> "Grad-CAM attention maps, lesion-level evidence correlated with clinical
> criteria, calibrated confidence, automated annotated reports —
> ophthalmologist validation in under 30 seconds."

**Build:** MATLAB `gradCAM()` heatmap + M2 lesion-candidate overlay + generated
clinical rationale text + annotated PDF report. Human-in-the-loop review screen.

### M5 · Simulink Workflow Simulation
> "Model the telemedicine screening pipeline in Simulink — acquisition rates,
> bandwidth constraints, processing throughput, review capacity — optimize
> resource allocation for district-level programs serving 100,000+ patients annually."

**Build:** SimEvents discrete-event model: arrivals → capture → upload queue
(bandwidth) → GPU throughput → ophthalmologist review pool → outputs
(daily capacity, queue times, utilization). Sweep parameters → optimal
cameras/servers/doctors for a district. **Nearly no team will do this — do it.**

## Success criteria (PS says "working prototype demonstrating…")
- [ ] >90% sensitivity & >85% specificity for referable DR (val-set table)
- [ ] Grad-CAM outputs "rated clinically useful" (capture a doctor-reviewer screen)
- [ ] Simulink resource-optimization model with charts
- [ ] Benchmark table vs published results (integrated pipeline > single technique)
