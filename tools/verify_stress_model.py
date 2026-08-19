#!/usr/bin/env python3
"""Sanity-check the exported stress model before shipping it in the app.

Training finishing without an error does not mean the model learned anything
useful. This runs the exported .tflite on hand-built physiological profiles
that a human can reason about, and checks the probabilities move in the
direction they should:

    resting  ->  low probability of stress
    strained ->  high probability of stress

A model that fails these is broken no matter what its accuracy said, and a
model that passes them is doing something a supervisor can be walked through.

Usage:
    ./mlenv/bin/python tools/verify_stress_model.py
"""

import os
import sys

import numpy as np

# TensorFlow 2.20 deprecates tf.lite.Interpreter in favour of LiteRT. Prefer
# the new package when it is installed, fall back when it isn't, so this keeps
# working on either.
try:
    from ai_edge_litert.interpreter import Interpreter
except ImportError:
    import tensorflow as tf
    Interpreter = tf.lite.Interpreter

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MODEL = os.path.join(REPO, 'assets', 'models', 'stress_model.tflite')

# Population anchors — these must match StressModel in lib/services/.
NORM_HR, NORM_HRV = 60.0, 80.0

# (label, heart rate bpm, HRV SDNN ms, expectation)
CASES = [
    ('Deeply rested',      52,  95, 'low'),
    ('Normal resting',     60,  78, 'low'),
    ('Mildly elevated',    75,  50, 'any'),
    ('Clearly strained',   95,  28, 'high'),
    ('Severely strained', 110,  18, 'high'),
]


def features(hr, hrv, base_hr=NORM_HR, base_hrv=NORM_HRV):
    """Same four inputs, in the same order, as lib/services/stress_model.dart."""
    return np.array([[hr, hrv, hr / base_hr, hrv / base_hrv]], dtype=np.float32)


def main():
    if not os.path.exists(MODEL):
        sys.exit(
            f'No model at {MODEL}\n'
            'Train it first:\n'
            '  ./mlenv/bin/python tools/train_stress_model.py --wesad /path/to/WESAD'
        )

    interpreter = Interpreter(model_path=MODEL)
    interpreter.allocate_tensors()
    inp = interpreter.get_input_details()[0]
    out = interpreter.get_output_details()[0]

    print(f'Model: {MODEL} ({os.path.getsize(MODEL) / 1024:.1f} KB)')
    print(f'Input {inp["shape"]} {inp["dtype"].__name__} -> '
          f'output {out["shape"]} {out["dtype"].__name__}\n')

    if tuple(inp['shape']) != (1, 4):
        sys.exit(f'Expected input shape (1, 4), got {tuple(inp["shape"])}. '
                 'The Dart side sends four features.')

    def predict(hr, hrv):
        interpreter.set_tensor(inp['index'], features(hr, hrv))
        interpreter.invoke()
        return float(interpreter.get_tensor(out['index'])[0][0])

    print(f'{"Profile":<20}{"HR":>6}{"HRV":>7}{"P(stress)":>12}   verdict')
    print('-' * 60)

    results, failures = [], []
    for label, hr, hrv, expect in CASES:
        p = predict(hr, hrv)
        results.append(p)
        verdict = 'ok'
        if expect == 'low' and p > 0.5:
            verdict, _ = 'TOO HIGH', failures.append(label)
        elif expect == 'high' and p < 0.5:
            verdict, _ = 'TOO LOW', failures.append(label)
        print(f'{label:<20}{hr:>6}{hrv:>7}{p:>12.3f}   {verdict}')

    print()

    # The ordering matters more than any single value: strain must never come
    # out calmer than rest.
    if results[-1] <= results[0]:
        failures.append('ordering (strained scored no higher than rested)')

    # Personal baselines should matter: the same 88 bpm means different things
    # for someone who normally rests at 55 than for someone who rests at 80.
    low_resting = predict(88, 40)
    interpreter.set_tensor(inp['index'], features(88, 40, base_hr=80, base_hrv=45))
    interpreter.invoke()
    high_resting = float(interpreter.get_tensor(out['index'])[0][0])
    print(f'Same reading (88 bpm, 40 ms) against different personal baselines:')
    print(f'  rests at 60 bpm -> {low_resting:.3f}')
    print(f'  rests at 80 bpm -> {high_resting:.3f}')
    if abs(low_resting - high_resting) < 0.01:
        print('  note: baseline made almost no difference to this reading')
    print()

    if failures:
        print('FAILED: ' + '; '.join(failures))
        print('The model is not fit to ship. Check the LOSO scores in '
              'tools/stress_model_metrics.json.')
        sys.exit(1)

    print('All checks passed — safe to bundle.')
    print('Next: flutter run, then open Wellbeing and look for '
          'the "Stress pattern" card.')


if __name__ == '__main__':
    main()
