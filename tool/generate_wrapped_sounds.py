#!/usr/bin/env python3
"""Synthesises the Wrapped sound effects into assets/sounds/.

The five cues are generated rather than sourced so they are licence-free,
tiny, and tunable: a sound that is half a semitone off, or a hair too loud
against the others, is a one-line change here and a re-run — not a hunt for a
replacement file. Committing the generator alongside the WAVs is what keeps
them from becoming binaries nobody dares touch.

    python tool/generate_wrapped_sounds.py

Everything is built from one voice: a struck-bar tone (sine partials under an
exponential decay), which is the timbre that reads as "interface" rather than
as "music" and survives a phone speaker. Pitches are drawn from a C major
pentatonic so any two cues that overlap — a bar tick landing under the tail of
the count arpeggio — are still consonant.

Stdlib only; no numpy.
"""

import math
import os
import struct
import wave

# 22.05 kHz. These cues are a handful of sine partials topping out around 6 kHz,
# so the extra octave 44.1 kHz buys is silence that still costs bytes — half the
# rate is half the download for no audible difference. Partials above the Nyquist
# limit are dropped in `add_note` rather than left to alias back down as grit.
RATE = 22050
OUT_DIR = os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "assets", "sounds"
)

# C major pentatonic, the scale every cue is drawn from.
C4, G4 = 261.63, 392.00
C5, D5, E5, G5, A5 = 523.25, 587.33, 659.25, 783.99, 880.00
C6, E6 = 1046.50, 1318.51

# (frequency multiple, amplitude, how much faster this partial decays).
# Upper partials dying first is what makes a struck bar sound struck; hold them
# and the tone turns into an organ.
STRUCK = [(1.0, 1.00, 1.0), (2.0, 0.30, 1.7), (3.0, 0.11, 2.6), (4.01, 0.05, 3.4)]
# Slightly inharmonic, the way a small bell is — enough shimmer to read as a
# reward without the clang of true bell ratios.
BELL = [(1.0, 1.00, 1.0), (2.76, 0.24, 1.5), (5.40, 0.08, 2.2), (8.93, 0.03, 3.0)]
# Nearly pure, for the low swell that opens the story.
SOFT = [(1.0, 1.00, 1.0), (2.0, 0.12, 1.6), (3.0, 0.03, 2.4)]


def add_note(buf, start, freq, amp, decay, partials=STRUCK, attack=0.004):
    """Mix one struck note into `buf` at `start` seconds."""
    begin = int(start * RATE)
    # Run each note until it is 50 dB down rather than for a fixed length, so
    # nothing is truncated into a click and nothing wastes samples on silence.
    length = int(min(math.log(316.0) / decay, 3.0) * RATE)
    attack_n = max(int(attack * RATE), 1)

    # Anything above the Nyquist limit would fold back down the spectrum as an
    # audible whistle at the wrong pitch, so it is dropped instead. The margin
    # keeps the very top partial off the limit itself.
    voiced = [p for p in partials if freq * p[0] < RATE * 0.45]

    for n in range(length):
        i = begin + n
        if i >= len(buf):
            break
        t = n / RATE
        env = math.exp(-decay * t)
        if n < attack_n:
            env *= n / attack_n
        sample = 0.0
        for mult, p_amp, p_decay in voiced:
            sample += (
                p_amp
                * math.exp(-decay * (p_decay - 1.0) * t)
                * math.sin(2 * math.pi * freq * mult * t)
            )
        buf[i] += amp * env * sample


def write(name, buf, peak):
    """Normalise to `peak` full-scale, fade the tail, and write a 16-bit mono WAV."""
    high = max(abs(s) for s in buf) or 1.0
    gain = peak / high

    # An 8 ms fade guarantees the buffer ends at zero. Without it the DAC gets a
    # step edge and every cue arrives with a click in front of the next one.
    fade = int(0.008 * RATE)
    frames = bytearray()
    for i, s in enumerate(buf):
        v = s * gain
        remaining = len(buf) - i
        if remaining < fade:
            v *= remaining / fade
        frames += struct.pack("<h", int(max(-1.0, min(1.0, v)) * 32767))

    path = os.path.join(OUT_DIR, name)
    with wave.open(path, "wb") as f:
        f.setnchannels(1)
        f.setsampwidth(2)
        f.setframerate(RATE)
        f.writeframes(bytes(frames))
    print(f"  {name:24} {len(buf) / RATE:.2f}s  {os.path.getsize(path) / 1024:6.1f} KB")


def silence(seconds):
    return [0.0] * int(seconds * RATE)


def build_open():
    """Panel 1 — a low bloom. Slow enough to feel like a curtain going up."""
    buf = silence(1.5)
    add_note(buf, 0.00, C4, 0.60, 2.2, SOFT, attack=0.16)
    add_note(buf, 0.02, G4, 0.42, 2.4, SOFT, attack=0.18)
    add_note(buf, 0.05, C5, 0.30, 2.6, SOFT, attack=0.20)
    return buf


def build_count():
    """Panel 2 — three notes climbing under the big number as it lands."""
    buf = silence(1.3)
    for i, freq in enumerate((C5, E5, G5)):
        add_note(buf, i * 0.095, freq, 0.85, 4.6)
    return buf


def build_tick():
    """Each subject bar, and the month arrows. Has to disappear behind itself."""
    buf = silence(0.16)
    add_note(buf, 0.0, A5, 0.9, 34.0, attack=0.001)
    return buf


def build_chime():
    """Panel 4 — two notes, warmer and slower: this one is a compliment."""
    buf = silence(1.4)
    add_note(buf, 0.00, G5, 0.80, 2.9, BELL)
    add_note(buf, 0.15, C6, 0.70, 2.7, BELL)
    return buf


def build_finish():
    """Panel 5 — the card. Four notes up, with the octave ringing over the top."""
    buf = silence(1.8)
    for i, freq in enumerate((C5, E5, G5, C6)):
        add_note(buf, i * 0.072, freq, 0.80, 4.2)
    add_note(buf, 0.29, E6, 0.45, 2.0, BELL)
    add_note(buf, 0.29, C6, 0.35, 1.9, BELL)
    return buf


# Peaks are set relative to each other, not per file: the tick sits well under
# everything because it fires five times in a row, and the finish is loudest
# because it is the payoff. The app never touches volume at runtime.
CUES = [
    ("wrapped_open.wav", build_open, 0.42),
    ("wrapped_count.wav", build_count, 0.62),
    ("wrapped_tick.wav", build_tick, 0.26),
    ("wrapped_chime.wav", build_chime, 0.55),
    ("wrapped_finish.wav", build_finish, 0.72),
]


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    print(f"Writing to {OUT_DIR}")
    for name, build, peak in CUES:
        write(name, build(), peak)


if __name__ == "__main__":
    main()
