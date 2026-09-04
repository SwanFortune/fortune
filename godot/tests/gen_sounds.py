#!/usr/bin/env python3
"""Dev tool: writes the PLACEHOLDER sounds in assets/audio/.

    python3 tests/gen_sounds.py       (run from the godot/ directory)

These are stand-ins, not sound design — see docs/SOUND_GUIDE.md. They exist so
that `master_volume` and `muted` in Settings, which drive the real audio bus,
drive something rather than nothing, and so the wiring in autoload/Audio.gd is
exercised rather than merely written.

Deliberately stdlib-only (no numpy, no ffmpeg): a placeholder generator that
needs an install is a placeholder generator nobody runs. Replacing any of these
with a real file means dropping it in and setting that entry's "status" to
"final" in data/base/sounds.json; this script is then not needed for it again.
"""
import math
import pathlib
import random
import struct
import wave

SR = 44100
OUT = pathlib.Path(__file__).resolve().parent.parent / "assets" / "audio"
random.seed(7)  # fixed, so re-running produces byte-identical files


def env(i, n, attack=0.004, release=0.5):
    """Percussive envelope: fast attack, exponential decay."""
    a = int(SR * attack)
    if i < a:
        return i / max(a, 1)
    t = (i - a) / max(n - a, 1)
    return math.exp(-t / release) * (1 - t) ** 0.5


def write(name, samples, peak=0.5):
    m = max(1e-9, max(abs(s) for s in samples))
    data = b"".join(
        struct.pack("<h", int(max(-1, min(1, s / m * peak)) * 32767)) for s in samples
    )
    OUT.mkdir(parents=True, exist_ok=True)
    with wave.open(str(OUT / (name + ".wav")), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(data)
    print("%-18s %5.2fs" % (name + ".wav", len(samples) / SR))


def noise_thud(dur, lp, release, click=0.0):
    """Filtered noise — a card, a coat, paper. One-pole lowpass keeps it soft."""
    n = int(SR * dur)
    out = []
    y = 0.0
    a = lp / (lp + SR)
    for i in range(n):
        y += a * (random.uniform(-1, 1) - y)
        s = y
        if click and i < SR * 0.002:
            s += click * random.uniform(-1, 1)
        out.append(s * env(i, n, 0.001, release))
    return out


def tone(dur, f0, f1, release, harmonics=(1.0, 0.35, 0.12)):
    """A soft struck tone, pitch gliding f0 -> f1."""
    n = int(SR * dur)
    out = []
    ph = 0.0
    for i in range(n):
        f = f0 + (f1 - f0) * (i / n)
        ph += 2 * math.pi * f / SR
        s = sum(a * math.sin(ph * (k + 1)) for k, a in enumerate(harmonics))
        out.append(s * env(i, n, 0.006, release))
    return out


def mix(*layers):
    n = max(len(l) for l in layers)
    return [sum(l[i] if i < len(l) else 0.0 for l in layers) for i in range(n)]


def main():
    # One card leaving the hand for the table: paper, not a click.
    write("card_lay", noise_thud(0.16, 2600, 0.28, click=0.25))
    # Cards arriving: softer, a shade higher, so a hand of five reads as a riffle.
    write("card_draw", noise_thud(0.11, 3400, 0.22, click=0.15))
    # The hand going away at end of reading: longer, duller.
    write("card_discard", noise_thud(0.26, 1500, 0.45))
    # The reading resolving — the one moment that should feel like an event.
    write("reading_resolve", mix(tone(0.9, 392.0, 392.0, 0.30), tone(0.9, 587.3, 587.3, 0.22)))
    # They go home whole. A rising fifth, warm.
    write("sitter_win", mix(tone(1.4, 392.0, 587.3, 0.42), tone(1.4, 784.0, 784.0, 0.18, (0.5, 0.1))))
    # They leave as they came. The same interval, falling, and flatter.
    write("sitter_lose", mix(tone(1.2, 392.0, 261.6, 0.40), tone(1.2, 196.0, 196.0, 0.30, (0.6,))))
    # Money on the table.
    write("coin", mix(tone(0.30, 1568.0, 1480.0, 0.10, (0.4, 0.9, 0.5)), noise_thud(0.10, 6000, 0.08)))
    # A fist on the front door. The one sound in the game the title is about:
    # a run is sixteen knocks and it ends when the knocking stops. Wood, so a
    # low body with a hard noisy transient on the front of it, and short —
    # a door in a small house does not ring.
    write("knock", mix(
        tone(0.30, 155.0, 118.0, 0.11, (1.0, 0.45, 0.18)),
        tone(0.18, 92.0, 78.0, 0.09, (0.8,)),
        noise_thud(0.05, 1900, 0.025, click=0.9),
    ))
    # Menus: quiet enough to sit under a hundred presses an hour.
    write("ui_move", noise_thud(0.05, 5200, 0.05), peak=0.28)
    write("ui_press", mix(tone(0.10, 660.0, 620.0, 0.07, (0.7, 0.2)), noise_thud(0.04, 5000, 0.04)), peak=0.38)


if __name__ == "__main__":
    main()
