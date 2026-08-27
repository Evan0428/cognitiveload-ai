# On-device stress model — training guide

The app ships a small TensorFlow Lite neural network that estimates the
probability the user is under acute physiological stress, from heart rate and
HRV. This file explains how to reproduce it.

**The model file is not in the repository.** `assets/models/stress_model.tflite`
is produced by training, and training needs a dataset that cannot be
redistributed. Until you generate it the app runs normally on its rule-based
readiness scoring — `StressModel.probability()` returns `null`, the Wellbeing
"Stress pattern" card stays hidden, and nothing breaks.

## 1. Get the dataset

**WESAD** — Wearable Stress and Affect Detection (Schmidt, Reiss, Duerichen,
Marberger & Van Laerhoven, *ICMI 2018*).

- 15 subjects, chest sensor (RespiBAN) + wrist sensor (Empatica E4)
- Conditions: baseline, stress (Trier Social Stress Test), amusement, meditation
- Free for research use

Dataset page: <https://ubi29.informatik.uni-siegen.de/usi/data_wesad.html>

Direct download (verified — returns `WESAD.zip`, `application/zip`, 2,249,444,501
bytes ≈ 2.25 GB):

```
https://uni-siegen.sciebo.de/s/HGdUkoNlW1Ub0Gx/download
```

The page also lists a second share link (`.../s/pYjSgfOVs6Ntahr`) which now
returns 404, as does the older `ubicomp.eti.uni-siegen.de/home/datasets/icmi18/`
path that many papers cite. Use the link above. Mirrors exist on the UCI
Machine Learning Repository (dataset 465) and Kaggle if Siegen is unreachable
from your network.

Download with a resumable client — a dropped connection two hours in is
otherwise a full restart:

```bash
curl -L -C - -o WESAD.zip "https://uni-siegen.sciebo.de/s/HGdUkoNlW1Ub0Gx/download"
```

The archive expands to substantially more than 2.25 GB (the pickles hold 700 Hz
float signals), so leave room. Extract it so the folder structure looks like:

```
WESAD/
  S2/S2.pkl
  S3/S3.pkl
  ...
```

Cite it in Chapter 5. Using a published dataset with a citation is the whole
point — it is what makes the accuracy figure a measurement rather than an
assertion.

## 2. Train

```bash
python3 -m venv mlenv
./mlenv/bin/pip install -r tools/requirements-ml.txt
./mlenv/bin/python tools/train_stress_model.py --wesad /path/to/WESAD
```

Expect it to take a while: it re-runs R-peak detection over every subject and
then trains one model per cross-validation fold.

Outputs:

| File | Purpose |
|---|---|
| `assets/models/stress_model.tflite` | bundled into the app |
| `tools/stress_model_metrics.json` | accuracy / precision / recall / F1 for Chapter 5 |

Then:

```bash
flutter pub get && (cd ios && pod install)
```

## 3. What the pipeline does

1. **Feature extraction.** Chest ECG at 700 Hz is split into 60-second windows
   (10-second hop). A simplified Pan–Tompkins detector finds R-peaks; the RR
   intervals give mean heart rate and SDNN.
2. **Personal normalisation.** Each subject's resting level is taken as the
   median over their baseline condition, and every window also carries
   `hr / baseline_hr` and `sdnn / baseline_sdnn`. This mirrors
   `PhysiologicalBaseline` in the app — the same intra-individual
   normalisation described in report §2.4.4.
3. **Model.** Input(4) → Normalization → Dense(16, ReLU) → Dropout(0.2) →
   Dense(8, ReLU) → Dense(1, sigmoid). Small on purpose: it runs on a phone,
   and four features do not justify anything larger.
4. **Evaluation.** Leave-one-subject-out cross-validation.
5. **Export.** Trained on all subjects, converted to TFLite with default
   optimisation. The result is a few KB.

## Two design decisions worth defending

**Only HR and HRV.** WESAD also carries EDA, EMG, respiration and skin
temperature, and using them would raise the accuracy — published WESAD results
that include EDA are noticeably stronger. They are excluded because Apple
HealthKit cannot supply them. A model trained on signals the app can never feed
would report a higher number and be useless in production.

**Normalisation is a layer inside the model, not a constant in Dart.** The
exported `.tflite` takes raw HR and HRV, so there is no scaling constant to
copy into Flutter and no way for the two to drift apart.

## Honest limitations

- WESAD's stress condition is acute laboratory stress (public speaking, mental
  arithmetic), not the sustained academic workload this app targets. The model
  detects *a physiological stress signature*, which is related to but not the
  same as cognitive load.
- 15 subjects, all adults in a lab, is a small and unrepresentative sample.
- LOSO accuracy is measured on WESAD, not on app users. No claim is made about
  accuracy on TARUMT students, because that has not been measured.

State these in §6.3 (Limitations). Naming them is stronger than hoping nobody
asks — every one of them is a question an examiner can reach on their own.
