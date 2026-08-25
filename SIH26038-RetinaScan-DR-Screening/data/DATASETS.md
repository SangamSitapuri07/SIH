# Datasets — download plan (no external APIs at runtime; one-time downloads)

| Dataset | Size | What it gives | Link / how |
|---|---|---|---|
| **APTOS 2019** (Kaggle) | 3,662 train images + 5-class labels (0–4) | Primary training set (severity grading) | kaggle.com/competitions/aptos2019-blindness-detection — accept rules → `kaggle competitions download` |
| **IDRiD** | 81 images with pixel masks | Lesion ground truth: microaneurysms, hemorrhages, hard/soft exudates, optic disc | idrid.grand-challenge.org (free, register) |
| **Messidor** | 1,200 images + grades | External validation set (train on APTOS, test on Messidor = clinical rigor) | www.adcis.net — request academic download |
| EyePACS DR 2015 (Kaggle) | 35k images | Optional scale-up | kaggle.com/c/diabetic-retinopathy-detection |

## Splitting rules (avoid the classic mistake)
- Split **by patient** — both eyes of the same person must stay in the same split.
- Suggested: 80/10/10 train/val/test on APTOS; Messidor used ONLY as external test.

## Preprocessing per image
1. Circular-field detection → crop black borders (Ben Graham).
2. Resize to 512×512 (worse:R/G/B), CLAHE on L channel, illumination flattening.
3. Quality metrics recorded (blur, illumination) → feeds Module 1 gate.

## Storage layout
```
data/
  raw/aptos/            # train_images/ + train.csv
  raw/idrid/
  raw/messidor/
  processed/512/        # after preprocess step
```
