#!/usr/bin/env python3
"""Generates CommandX/crumple.wav: a short (~0.2 s) paper-crumple click.
Usage: python3 tools/make_crumple_sound.py CommandX/crumple.wav
"""
import sys, wave
import numpy as np

SR = 44100
DUR = 0.20
rng = np.random.default_rng(7)
n = int(SR * DUR)
out = np.zeros(n)

def highpass(x, a=0.93):
    y = np.zeros_like(x); prev_x = prev_y = 0.0
    for i, v in enumerate(x):
        prev_y = a * (prev_y + v - prev_x); prev_x = v; y[i] = prev_y
    return y

# a handful of sharp micro-crackles (paper creases), clustered at the start
times = [0.000, 0.012, 0.027, 0.041, 0.060, 0.082, 0.108, 0.140]
amps  = [1.00, 0.70, 0.90, 0.50, 0.55, 0.35, 0.25, 0.15]
for t, a in zip(times, amps):
    start = int(t * SR)
    length = int(rng.uniform(0.004, 0.011) * SR)
    burst = highpass(rng.standard_normal(length))
    burst *= np.exp(-np.linspace(0, 7, length)) * a
    out[start:start + length] += burst[: n - start]

# thin rustle bed that fades fast
bed = highpass(rng.standard_normal(n), 0.9) * np.exp(-np.linspace(0, 9, n)) * 0.18
out += bed

out /= np.max(np.abs(out)); out *= 0.55
out[-200:] *= np.linspace(1, 0, 200)

path = sys.argv[1] if len(sys.argv) > 1 else "crumple.wav"
with wave.open(path, "wb") as w:
    w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
    w.writeframes((out * 32767).astype(np.int16).tobytes())
print(f"wrote {path} ({DUR}s)")
