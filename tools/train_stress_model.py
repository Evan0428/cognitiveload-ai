#!/usr/bin/env python3
"""Train the on-device physiological stress model (Chua Yi Zhe).

Pipeline
--------
    WESAD chest ECG  ->  R-peak detection  ->  HR / HRV features
                     ->  MLP (Keras)       ->  TensorFlow Lite  ->  Flutter

Why this dataset
----------------
WESAD (Schmidt et al., ICMI 2018) is the reference public dataset for wearable
stress detection: 15 subjects wearing a chest sensor (RespiBAN) and a wrist
sensor (Empatica E4) through a protocol of baseline, stress (Trier Social
Stress Test), amusement and meditation conditions. It gives us *real* labelled
physiology, so the reported accuracy is a real measurement rather than a
restatement of our own scoring rules.

Why only HR and HRV
-------------------
The model may only use signals the phone can actually supply at inference time.
Apple HealthKit gives us resting heart rate and HRV (SDNN); it does NOT give us
EDA, EMG, respiration or skin temperature. Training on those would produce a
model the app could never feed, so the chest ECG is reduced to exactly the two
signals `PhysiologicalSnapshot` carries.

Each window is described by four features:

    [ hr, sdnn, hr / baseline_hr, sdnn / baseline_sdnn ]

The two ratios mirror `PhysiologicalBaseline` in the app: a heart rate is only
meaningful relative to *your own* resting level. This is the same
intra-individual normalisation the report describes in section 2.4.4, so the
network sees data shaped the way the app will present it.

Evaluation
----------
Leave-one-subject-out cross-validation. A random split would put windows from
the same person in both train and test, and neighbouring windows overlap, so
the score would be inflated by subject leakage. LOSO measures what we actually
care about: performance on a person the model has never seen — which is every
new user of the app.

Usage
-----
    python3 -m venv mlenv
    ./mlenv/bin/pip install -r tools/requirements-ml.txt
    ./mlenv/bin/python tools/train_stress_model.py --wesad /path/to/WESAD

Outputs
-------
    assets/models/stress_model.tflite   bundled into the app
    tools/stress_model_metrics.json     numbers to quote in Chapter 5
"""

import argparse
import json
import os
import pickle
import sys

import numpy as np
from scipy.signal import butter, filtfilt, find_peaks

# ----------------------------------------------------------------- constants

FS = 700          # WESAD chest sampling rate (Hz)
WINDOW_S = 60     # one feature vector per 60 s, matching a HealthKit sample
STEP_S = 10       # hop between windows; overlap gives us more training data

# WESAD condition codes. 0 = undefined, 5/6/7 = ignore per the dataset README.
BASELINE, STRESS, AMUSEMENT, MEDITATION = 1, 2, 3, 4

# Binary protocol from the WESAD paper: stress vs. everything else.
NON_STRESS = (BASELINE, AMUSEMENT)

FEATURES = ['hr', 'sdnn', 'hr_ratio', 'sdnn_ratio']

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MODEL_OUT = os.path.join(REPO, 'assets', 'models', 'stress_model.tflite')
METRICS_OUT = os.path.join(REPO, 'tools', 'stress_model_metrics.json')


# ------------------------------------------------------------ signal -> beats

def detect_r_peaks(ecg, fs=FS):
    """Locate R-peaks with a simplified Pan-Tompkins detector.

    Bandpass to the QRS band, differentiate, square, integrate over a
    ~150 ms window, then take peaks at least 250 ms apart (i.e. below the
    240 bpm that no resting recording will legitimately exceed).
    """
    nyq = fs / 2
    b, a = butter(3, [5 / nyq, 15 / nyq], btype='band')
    filtered = filtfilt(b, a, ecg)

    squared = np.diff(filtered) ** 2
    window = np.ones(int(0.150 * fs)) / int(0.150 * fs)
    integrated = np.convolve(squared, window, mode='same')

    if not np.any(integrated):
        return np.array([], dtype=int)

    threshold = np.percentile(integrated, 98) * 0.35
    peaks, _ = find_peaks(integrated, height=threshold, distance=int(0.25 * fs))
    return peaks


# Reject RR intervals deviating more than this from the window's median.
# Standard ectopic-beat correction: a missed detection produces an interval of
# roughly twice the true length, which passes any fixed plausibility range and
# inflates SDNN far more than any real autonomic change. Measured on WESAD S2,
# omitting this step reverses the expected relationship — stress appeared to
# *raise* HRV (89.5 ms vs 77.9 ms, peaking at an implausible 220 ms). With it,
# the relationship is correct (58.9 ms vs 62.5 ms, peak 88.7 ms).
RR_TOLERANCE = 0.20


def hr_hrv(ecg, fs=FS):
    """Mean heart rate (bpm) and HRV as SDNN (ms) for one window.

    Returns (None, None) when the window is too noisy to yield enough beats.
    """
    peaks = detect_r_peaks(ecg, fs)
    if len(peaks) < 6:
        return None, None

    rr = np.diff(peaks) / fs                       # seconds between beats
    rr = rr[(rr > 0.3) & (rr < 2.0)]               # drop implausible intervals
    if len(rr) < 5:
        return None, None

    # Artefact correction — see RR_TOLERANCE above.
    median = np.median(rr)
    rr = rr[np.abs(rr - median) <= RR_TOLERANCE * median]
    if len(rr) < 5:
        return None, None

    return float(60.0 / rr.mean()), float(rr.std(ddof=1) * 1000.0)


# --------------------------------------------------------- dataset -> tensors

def load_subject(wesad_dir, subject):
    """Feature rows for one subject: (X, y) with X un-normalised by baseline."""
    path = os.path.join(wesad_dir, subject, f'{subject}.pkl')
    if not os.path.exists(path):
        return None

    with open(path, 'rb') as f:
        data = pickle.load(f, encoding='latin1')   # WESAD pickles are Python 2

    ecg = np.asarray(data['signal']['chest']['ECG']).ravel()
    labels = np.asarray(data['label']).ravel()

    size, step = WINDOW_S * FS, STEP_S * FS
    rows, targets = [], []

    for start in range(0, len(ecg) - size, step):
        chunk_labels = labels[start:start + size]
        # Keep only windows that sit entirely inside one condition, so a
        # feature vector is never a blend of two different states.
        unique = np.unique(chunk_labels)
        if len(unique) != 1:
            continue
        condition = int(unique[0])
        if condition != STRESS and condition not in NON_STRESS:
            continue

        hr, sdnn = hr_hrv(ecg[start:start + size])
        if hr is None:
            continue

        rows.append((hr, sdnn, condition))
        targets.append(1 if condition == STRESS else 0)

    if not rows:
        return None

    hrs = np.array([r[0] for r in rows])
    sdnns = np.array([r[1] for r in rows])
    conditions = np.array([r[2] for r in rows])

    # The subject's own resting level, taken from the baseline condition. This
    # is the dataset's stand-in for the app's 14-day rolling average.
    resting = conditions == BASELINE
    if not resting.any():
        return None
    base_hr = float(np.median(hrs[resting]))
    base_sdnn = float(np.median(sdnns[resting]))
    if base_hr <= 0 or base_sdnn <= 0:
        return None

    X = np.column_stack([hrs, sdnns, hrs / base_hr, sdnns / base_sdnn])
    return X.astype(np.float32), np.array(targets, dtype=np.float32)


def load_dataset(wesad_dir):
    subjects = sorted(
        d for d in os.listdir(wesad_dir)
        if d.startswith('S') and os.path.isdir(os.path.join(wesad_dir, d))
    )
    if not subjects:
        sys.exit(f'No subject folders (S2, S3, ...) found in {wesad_dir}')

    out = {}
    for s in subjects:
        result = load_subject(wesad_dir, s)
        if result is None:
            print(f'  {s}: skipped (no usable windows)')
            continue
        X, y = result
        out[s] = (X, y)
        print(f'  {s}: {len(y):4d} windows, {int(y.sum()):4d} stress')
    if len(out) < 3:
        sys.exit('Too few usable subjects to cross-validate.')
    return out


# ------------------------------------------------------------------- model

def build_model(train_X):
    """A deliberately small MLP — it must run on a phone, and four features do
    not justify a large network. Normalisation is a layer *inside* the model so
    the exported .tflite takes raw HR/HRV values and Dart cannot drift out of
    sync with Python over a scaling constant."""
    import tensorflow as tf

    normaliser = tf.keras.layers.Normalization(axis=-1)
    normaliser.adapt(train_X)

    model = tf.keras.Sequential([
        tf.keras.layers.Input(shape=(len(FEATURES),)),
        normaliser,
        tf.keras.layers.Dense(16, activation='relu'),
        tf.keras.layers.Dropout(0.2),
        tf.keras.layers.Dense(8, activation='relu'),
        tf.keras.layers.Dense(1, activation='sigmoid'),
    ])
    model.compile(optimizer=tf.keras.optimizers.Adam(1e-3),
                  loss='binary_crossentropy', metrics=['accuracy'])
    return model


def scores(y_true, y_pred):
    tp = float(((y_pred == 1) & (y_true == 1)).sum())
    fp = float(((y_pred == 1) & (y_true == 0)).sum())
    fn = float(((y_pred == 0) & (y_true == 1)).sum())
    precision = tp / (tp + fp) if tp + fp else 0.0
    recall = tp / (tp + fn) if tp + fn else 0.0
    f1 = 2 * precision * recall / (precision + recall) if precision + recall else 0.0
    return {
        'accuracy': float((y_pred == y_true).mean()),
        'precision': precision,
        'recall': recall,
        'f1': f1,
    }


def leave_one_subject_out(dataset, epochs):
    """Honest generalisation estimate: every fold tests on an unseen person."""
    folds = []
    for held_out in dataset:
        train_subjects = [s for s in dataset if s != held_out]
        train_X = np.concatenate([dataset[s][0] for s in train_subjects])
        train_y = np.concatenate([dataset[s][1] for s in train_subjects])
        test_X, test_y = dataset[held_out]

        model = build_model(train_X)
        model.fit(train_X, train_y, epochs=epochs, batch_size=32, verbose=0)

        predicted = (model.predict(test_X, verbose=0).ravel() >= 0.5).astype(np.float32)
        fold = scores(test_y, predicted)
        fold['subject'] = held_out
        fold['windows'] = int(len(test_y))
        folds.append(fold)
        print(f"  {held_out}: accuracy {fold['accuracy']:.3f}  f1 {fold['f1']:.3f}")
    return folds


def export_tflite(model, path):
    import tensorflow as tf

    converter = tf.lite.TFLiteConverter.from_keras_model(model)
    converter.optimizations = [tf.lite.Optimize.DEFAULT]
    blob = converter.convert()
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, 'wb') as f:
        f.write(blob)
    return len(blob)


# --------------------------------------------------------------------- main

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--wesad', required=True,
                        help='Path to the extracted WESAD folder (contains S2, S3, ...)')
    parser.add_argument('--epochs', type=int, default=60)
    parser.add_argument('--skip-loso', action='store_true',
                        help='Train the deployed model only, without cross-validation')
    args = parser.parse_args()

    if not os.path.isdir(args.wesad):
        sys.exit(f'Not a directory: {args.wesad}')

    print('Extracting HR / HRV windows from WESAD...')
    dataset = load_dataset(args.wesad)

    all_X = np.concatenate([dataset[s][0] for s in dataset])
    all_y = np.concatenate([dataset[s][1] for s in dataset])
    print(f'\n{len(all_y)} windows from {len(dataset)} subjects '
          f'({int(all_y.sum())} stress / {int(len(all_y) - all_y.sum())} non-stress)\n')

    metrics = {
        'dataset': 'WESAD (Schmidt et al., ICMI 2018)',
        'subjects': len(dataset),
        'windows': int(len(all_y)),
        'stress_windows': int(all_y.sum()),
        'features': FEATURES,
        'window_seconds': WINDOW_S,
        'protocol': 'binary: stress vs. (baseline + amusement)',
    }

    if not args.skip_loso:
        print('Leave-one-subject-out cross-validation:')
        folds = leave_one_subject_out(dataset, args.epochs)
        metrics['loso_folds'] = folds
        for key in ('accuracy', 'precision', 'recall', 'f1'):
            values = [f[key] for f in folds]
            metrics[f'loso_{key}_mean'] = float(np.mean(values))
            metrics[f'loso_{key}_std'] = float(np.std(values))
        print(f"\nLOSO accuracy {metrics['loso_accuracy_mean']:.3f} "
              f"+/- {metrics['loso_accuracy_std']:.3f}"
              f"   F1 {metrics['loso_f1_mean']:.3f}")

    # The shipped model sees every subject; LOSO above is what we report.
    print('\nTraining deployed model on all subjects...')
    model = build_model(all_X)
    model.fit(all_X, all_y, epochs=args.epochs, batch_size=32, verbose=0)

    size = export_tflite(model, MODEL_OUT)
    metrics['tflite_bytes'] = size

    with open(METRICS_OUT, 'w') as f:
        json.dump(metrics, f, indent=2)

    print(f'\nWrote {MODEL_OUT} ({size / 1024:.1f} KB)')
    print(f'Wrote {METRICS_OUT}')
    print('\nNow run: flutter pub get && (cd ios && pod install)')


if __name__ == '__main__':
    main()
