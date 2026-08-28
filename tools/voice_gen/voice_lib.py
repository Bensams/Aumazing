"""Shared audio helpers for voice-over generation.

Output contract for the Aumazing voice-over library:
  24 kHz, mono, 16-bit PCM WAV, ~20ms lead pad, ~40ms tail pad.
"""
import numpy as np
import soundfile as sf

TARGET_SR = 24000
# Padding exists to avoid clicks at the edges, nothing more. It was 30/80,
# which is fine for a cue played alone and far too much for one played inside a
# composed phrase: the tail of "Purple" and the lead of "Circle" stack up into
# 110 ms of silence in the middle of two words that should run together. 20/40
# is still comfortably longer than the fade, so edges stay click-free, and a
# 60 ms join is within the range an ordinary stop consonant occupies anyway.
LEAD_PAD_MS = 20
TAIL_PAD_MS = 40
FADE_IN_MS = 5
FADE_OUT_MS = 15
# Trim threshold, relative to peak. This was -60 dB, chosen so quiet word
# onsets were never clipped, and it was so permissive that it never fired: at
# 0.1% of peak the model's own noise floor reads as speech, so `speech_bounds`
# reported a clip already tight when the first audible sound was 300 ms in.
# Every generated pack shipped with ~0.3 s of dead air at each end, which is
# inaudible on a standalone cue and lands as a long pause in the middle of a
# composed phrase like "Tap the" + "Yellow" + "Star".
#
# -45 dB measured over a 10 ms RMS window is the fix: the detected span is
# stable from -45 to -40 dB and only starts eating real speech at -35 dB, where
# "Great job!" loses 120 ms off its tail. Frame RMS rather than sample peak
# matters too -- one stray sample above threshold was enough to defeat the old
# detector. See tools/voice_gen/conform_library.py, which repairs clips that
# were produced before this was corrected.
THRESH_DB = -45.0
TRIM_FRAME_MS = 10.0
# Splitting needs a less sensitive threshold than trimming. At -60 dB the
# low-level breath between carrier words still reads as voiced, so
# "Okay. Gold. Ready." merges into two segments and extraction is refused.
SPLIT_THRESH_DB = -45.0
# No single threshold works for every clip: measured on generated carriers,
# "Gold" split cleanly at -45 dB while "Magenta" needed -40. Rather than pick
# one number that the next reference voice breaks, sweep from least to most
# sensitive and take the first that yields the expected segment count. Stop
# before the range where words start splitting on their own internal stops.
SPLIT_THRESH_SWEEP = (-45.0, -40.0, -35.0, -30.0, -25.0)
PEAK_TARGET = 0.89  # ~-1 dBFS, matches the existing library's ~-5.7 dBFS peaks loosely


def load(path):
    """Read any WAV as float32 mono at its native rate."""
    data, sr = sf.read(path, dtype='float32', always_2d=True)
    return data.mean(axis=1), sr


def resample(x, sr, target=TARGET_SR):
    if sr == target:
        return x
    try:
        import soxr
        return soxr.resample(x, sr, target)
    except ImportError:
        # Linear fallback - adequate here, but soxr is the intended path.
        n = int(round(len(x) * target / sr))
        return np.interp(np.linspace(0, len(x) - 1, n), np.arange(len(x)), x).astype(np.float32)


def speech_bounds(x, thresh_db=THRESH_DB, sr=TARGET_SR,
                  frame_ms=TRIM_FRAME_MS):
    """(first, last) sample index of audible speech, or None if silent.

    Energy is measured over short frames rather than per sample, because a
    single sample above threshold is not speech -- it is the noise floor, and
    treating it as speech is what left dead air on every generated clip.
    One frame of slack each side keeps soft onsets and released consonants.
    """
    if len(x) == 0:
        return None
    n = max(1, int(sr * frame_ms / 1000))
    m = (len(x) // n) * n
    if m < n:
        return None
    r = np.sqrt((np.asarray(x[:m], dtype=np.float32).reshape(-1, n) ** 2)
                .mean(axis=1))
    if r.max() <= 0:
        return None
    above = np.flatnonzero(r > r.max() * (10 ** (thresh_db / 20.0)))
    if above.size == 0:
        return None
    return int(max(0, above[0] - 1) * n), int(min(len(x), (above[-1] + 2) * n))


def split_on_silence(x, sr, min_silence_ms=120, thresh_db=SPLIT_THRESH_DB):
    """Split into voiced segments separated by >= min_silence_ms of silence.

    Used to pull the target word out of a carrier phrase.
    """
    peak = float(np.max(np.abs(x))) if len(x) else 0.0
    if peak <= 0:
        return []
    th = peak * (10 ** (thresh_db / 20.0))
    voiced = np.abs(x) > th
    if not voiced.any():
        return []
    idx = np.flatnonzero(voiced)
    gap = int(sr * min_silence_ms / 1000)
    segs, start, prev = [], idx[0], idx[0]
    for i in idx[1:]:
        if i - prev > gap:
            segs.append((int(start), int(prev)))
            start = i
        prev = i
    segs.append((int(start), int(prev)))
    return segs


def split_carrier(x, sr, expected=3, min_silence_ms=120):
    """Segments of a carrier phrase, or None if it cannot be split cleanly.

    Sweeps [SPLIT_THRESH_SWEEP] and returns the first split that yields
    exactly `expected` segments. Returning None (rather than a best guess)
    is what keeps a mis-cut word from reaching the library silently.
    """
    for th in SPLIT_THRESH_SWEEP:
        segs = split_on_silence(x, sr, min_silence_ms=min_silence_ms,
                                thresh_db=th)
        if len(segs) == expected:
            return segs, th
    return None, None


def pad_and_fade(x, sr, lead_ms=LEAD_PAD_MS, tail_ms=TAIL_PAD_MS):
    """Trim to detected speech, then re-pad with fixed silence and fade edges."""
    b = speech_bounds(x, sr=sr)
    if b is None:
        return None
    first, last = b
    start = max(0, first - int(sr * lead_ms / 1000))
    end = min(len(x), last + int(sr * tail_ms / 1000))
    out = x[start:end].copy()

    lead_short = int(sr * lead_ms / 1000) - (first - start)
    tail_short = int(sr * tail_ms / 1000) - (end - last)
    if lead_short > 0:
        out = np.concatenate([np.zeros(lead_short, np.float32), out])
    if tail_short > 0:
        out = np.concatenate([out, np.zeros(tail_short, np.float32)])

    fi = min(int(sr * FADE_IN_MS / 1000), len(out) // 2)
    fo = min(int(sr * FADE_OUT_MS / 1000), len(out) // 2)
    if fi:
        out[:fi] *= np.linspace(0, 1, fi, dtype=np.float32)
    if fo:
        out[-fo:] *= np.linspace(1, 0, fo, dtype=np.float32)
    return out


def normalize(x, target=PEAK_TARGET):
    peak = float(np.max(np.abs(x))) if len(x) else 0.0
    if peak <= 0:
        return x
    return (x * (target / peak)).astype(np.float32)


def save_16bit(path, x, sr=TARGET_SR):
    x = np.clip(x, -1.0, 1.0)
    sf.write(path, (x * 32767).astype(np.int16), sr, subtype='PCM_16')


def describe(x, sr):
    b = speech_bounds(x, sr=sr)
    speech = (b[1] - b[0]) / sr if b else 0.0
    return dict(total=len(x) / sr, speech=speech,
                peak_db=20 * np.log10(max(float(np.max(np.abs(x))), 1e-9)))
