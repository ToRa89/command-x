#!/usr/bin/env python3
"""Synthesizes a short paper-crumple sound (no samples, no licensing issues).

Usage: python3 tools/make_crumple_sound.py CommandX/crumple.wav
Needs: numpy
"""
import sys
import wave

import numpy as np

SR = 44100
DUR = 0.75
rng = np.random.default_rng(42)  # fixed seed: reproducible result


def bandpass(x, lo, hi):
    spec = np.fft.rfft(x)
    freqs = np.fft.rfftfreq(len(x), 1 / SR)
    spec[(freqs < lo) | (freqs > hi)] = 0
    return np.fft.irfft(spec, len(x))


n = int(SR * DUR)
t = np.arange(n) / SR

# 1) Rustle: band-limited noise with a ragged, decaying envelope
noise = bandpass(rng.standard_normal(n), 1500, 9000)
raw_env = np.abs(bandpass(rng.standard_normal(n), 0, 38))  # slow random wobble
raw_env = raw_env / raw_env.max()
decay = np.exp(-t / 0.28)
rustle = noise * (raw_env ** 1.5) * decay * 0.55

# 2) Crackles: many tiny damped bursts, dense at the start, sparse at the end
crackle = np.zeros(n)
pos = 0.0
while pos < DUR:
    rate = 140 * np.exp(-pos / 0.30) + 18  # events per second
    pos += rng.exponential(1 / rate)
    i = int(pos * SR)
    if i >= n - 400:
        break
    length = int(rng.uniform(0.002, 0.008) * SR)
    k = np.arange(length) / SR
    freq = rng.uniform(1800, 6500)
    burst = np.sin(2 * np.pi * freq * k) * np.exp(-k / rng.uniform(0.0008, 0.003))
    burst += rng.standard_normal(length) * np.exp(-k / 0.001) * 0.6
    amp = rng.uniform(0.15, 1.0) * np.exp(-pos / 0.45)
    crackle[i:i + length] += burst * amp

sig = rustle + crackle * 0.9
sig *= np.minimum(1, t / 0.004)                 # 4 ms fade-in
sig *= np.minimum(1, (DUR - t) / 0.08)           # 80 ms fade-out
sig = sig / np.max(np.abs(sig)) * 0.7            # about -3 dBFS

pcm = (sig * 32767).astype("<i2")
out = sys.argv[1] if len(sys.argv) > 1 else "crumple.wav"
with wave.open(out, "wb") as w:
    w.setnchannels(1)
    w.setsampwidth(2)
    w.setframerate(SR)
    w.writeframes(pcm.tobytes())
print(f"wrote {out}: {DUR:.2f}s, peak {np.max(np.abs(sig)):.2f}")
