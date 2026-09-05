#!/usr/bin/env python3
"""Dev tool: writes the PLACEHOLDER music and room tone in assets/audio/.

    python3 tests/gen_music.py        (run from the godot/ directory)

The looping half of what tests/gen_sounds.py does for the one-shots, and the
same deal: these are stand-ins so that the two new volume sliders, the MUSIC and
AMBIENCE buses, the crossfades in autoload/Audio.gd and the per-screen cues in
autoload/Nav.gd all drive something rather than nothing. They are not a score.
See docs/SOUND_GUIDE.md, which names the CC0 sources a real track can come from.

WHY THESE ARE SYNTHESISED AND NOT DOWNLOADED: the container this was written in
has no route to freesound, OpenGameArt, Pixabay or incompetech — every one of
them fails to connect. Dropping a real file in is one copy and one `status`
change; nothing here has to be re-run for it.

EVERY LOOP IS SEAMLESS, which is the whole difficulty with a placeholder that
plays for an hour: the waveform has to arrive back where it started. Two rules
do it — the pitched parts use periods that divide the loop exactly, and the
noise parts crossfade their own tail over their own head.

Deliberately stdlib-only (no numpy, no ffmpeg), for the same reason as
gen_sounds.py: a generator that needs an install is one nobody runs.
"""
import math
import pathlib
import random
import struct
import wave

# HALF the sample rate of the one-shots. These are minutes long where a knock is
# a fifth of a second, and 44.1kHz placeholders would put five megabytes of
# stand-in audio in the repository. Nothing here has content above 8kHz anyway.
SR = 22050
OUT = pathlib.Path(__file__).resolve().parent.parent / "assets" / "audio"
random.seed(11)  # fixed, so re-running produces byte-identical files


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
    print("%-16s %5.1fs  %6.0f kB" % (name + ".wav", len(samples) / SR, len(data) / 1024))


def loop_safe(freq, seconds):
    """The nearest frequency to `freq` that fits a whole number of cycles into
    `seconds` — which is what makes a sustained note loop without a click."""
    cycles = max(1, round(freq * seconds))
    return cycles / seconds


def note(buf, seconds, freq, at, dur, gain, harmonics=(1.0, 0.3, 0.12)):
    """A soft plucked note, added into `buf` and WRAPPING PAST THE END back to
    the start — a note struck near the end of the loop has to still be ringing
    when the loop comes round, or every pass has a hole in it."""
    n = len(buf)
    f = loop_safe(freq, seconds)
    for i in range(int(dur * SR)):
        t = i / SR
        # Slow attack, long decay: a hammer on a felt string, not a pluck.
        a = min(1.0, t / 0.06)
        e = a * math.exp(-t / (dur * 0.42))
        s = sum(h * math.sin(2 * math.pi * f * (k + 1) * t) for k, h in enumerate(harmonics))
        buf[(int(at * SR) + i) % n] += s * e * gain


def drone(buf, seconds, freq, gain, wobble=0.0):
    """A sustained tone under everything. Wobble is a slow detune, itself on a
    period that divides the loop, so it comes back to where it started."""
    n = len(buf)
    f = loop_safe(freq, seconds)
    w = loop_safe(0.11, seconds) if wobble else 0.0
    for i in range(n):
        t = i / SR
        detune = 1.0 + wobble * math.sin(2 * math.pi * w * t) if wobble else 1.0
        buf[i] += gain * (
            math.sin(2 * math.pi * f * detune * t) + 0.35 * math.sin(2 * math.pi * f * 2 * detune * t)
        )


def rain(seconds, lp=0.06, gain=1.0, drips=0):
    """Filtered noise, wrapped: the last second is crossfaded over the first, so
    the loop point is inside a fade rather than at a seam."""
    n = int(seconds * SR)
    tail = int(1.0 * SR)
    raw = [random.uniform(-1, 1) for _ in range(n + tail)]
    out = []
    y = 0.0
    for x in raw:
        y += lp * (x - y)          # one-pole low pass — weather, not hiss
        out.append(y)
    for i in range(tail):          # crossfade the tail back over the head
        f = i / tail
        out[i] = out[i] * f + out[n + i] * (1 - f)
    out = out[:n]
    for _ in range(drips):         # the odd heavier drop off the gutter
        at = random.randrange(n)
        for i in range(int(0.05 * SR)):
            e = math.exp(-i / (0.012 * SR))
            out[(at + i) % n] += 0.5 * e * random.uniform(-1, 1)
    return [v * gain for v in out]


def crackle(seconds, rate=14):
    """A grate: a low breath with small sharp pops in it, all wrapped."""
    n = int(seconds * SR)
    out = rain(seconds, lp=0.012, gain=0.7)
    for _ in range(int(rate * seconds)):
        at = random.randrange(n)
        amp = random.uniform(0.15, 1.0)
        for i in range(int(0.03 * SR)):
            e = math.exp(-i / (0.004 * SR))
            out[(at + i) % n] += amp * e * random.uniform(-1, 1)
    return out


def bed(seconds):
    return [0.0] * int(seconds * SR)


def main():
    # A minor, mostly: the game is melancholic and warm, not spooky. Frequencies
    # are A2/C3/E3/A3/B3/D4 — a small hand-span on an out-of-tune upright.
    A2, C3, E3, G3, A3, B3, D4, E4 = 110.0, 130.8, 164.8, 196.0, 220.0, 246.9, 293.7, 329.6

    # THE PARLOUR — the menu and everything outside a run. A room with the lamp
    # on and nobody in it yet: one chord, arriving slowly, twice a loop.
    s = 16.0
    b = bed(s)
    drone(b, s, A2, 0.10, wobble=0.004)
    for at, f in [(0.0, A3), (1.6, C3), (3.4, E3), (8.0, A3), (9.7, B3), (11.6, E3)]:
        note(b, s, f, at, 5.0, 0.30)
    write("parlour", b, peak=0.45)

    # THE EVENING — the map. Walking pace: a low pulse on the half-bar and the
    # same chord opening up a step at a time.
    s = 16.0
    b = bed(s)
    drone(b, s, A2, 0.07)
    for k in range(8):
        note(b, s, A2, k * 2.0, 1.4, 0.22, harmonics=(1.0, 0.15))
    for at, f in [(1.0, E3), (3.0, G3), (5.0, A3), (7.0, B3), (9.0, A3), (11.0, G3), (13.0, E3), (15.0, D4)]:
        note(b, s, f, at, 2.6, 0.20)
    write("the_evening", b, peak=0.42)

    # THE TABLE — a reading. The quietest of the three by a long way: somebody
    # is talking over this and the cards are the event, so it is nearly a drone
    # with one note every four seconds to say time is passing.
    s = 16.0
    b = bed(s)
    drone(b, s, A2, 0.12, wobble=0.003)
    drone(b, s, E3, 0.05)
    for at, f in [(0.5, A3), (4.5, E3), (8.5, C3), (12.5, E3)]:
        note(b, s, f, at, 4.5, 0.13, harmonics=(1.0, 0.2, 0.05))
    write("the_table", b, peak=0.34)

    # THE MAYOR — the last half hour of the third night, and the only track
    # allowed to be uncomfortable. A tritone under the root, and a pulse that
    # does not quite line up with it.
    s = 12.0
    b = bed(s)
    drone(b, s, A2, 0.13, wobble=0.010)
    drone(b, s, 155.6, 0.07, wobble=0.014)   # E flat: the interval that will not settle
    for k in range(9):
        note(b, s, A2, k * 1.3, 1.1, 0.20, harmonics=(1.0, 0.4, 0.25))
    write("the_mayor", b, peak=0.46)

    # AFTER — the end of a run. What is left when the knocking stops: the same
    # chord as the parlour, falling instead of rising, with more air round it.
    s = 16.0
    b = bed(s)
    drone(b, s, A2, 0.08, wobble=0.002)
    for at, f in [(0.0, E4), (2.4, B3), (5.0, A3), (8.4, E3), (12.0, C3)]:
        note(b, s, f, at, 6.0, 0.26)
    write("after", b, peak=0.42)

    # THE ROOM — rain on the window of a small house in bad weather, under
    # everything, all night. Long enough not to hear the loop.
    write("rain", rain(12.0, lp=0.05, drips=9), peak=0.36)

    # And the grate, for the hours indoors.
    write("fire", crackle(10.0), peak=0.30)


if __name__ == "__main__":
    main()
