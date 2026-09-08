#!/usr/bin/env python3
"""Lists what an exported Godot binary actually contains.

    tests/pck_contents.py ../build/linux/parlour.x86_64

WHY THIS EXISTS. The headless suite runs from the source tree, where every file
is a real file. An export is a different artefact: resources are converted,
`tests/*` is filtered out, and a file the packer handled differently is wrong
only in the thing a player is handed. That is not hypothetical — it is how the
shipped build came to have no sound at all. Audio.gd reads its .wav files as
BYTES, on purpose, so that a file dropped into assets/audio/ or shipped by a mod
plays without going near the editor; and an export does not carry the .wav. It
carries assets/audio/coin.wav.import and a converted .sample, so
FileAccess.file_exists("res://assets/audio/coin.wav") was false for all
seventeen cues and the missing-file contract turned that into silence.

Nothing in the suite could see that. This is what did.

THE PACK FORMAT, worked out by looking rather than from documentation, because
the layout moved in format 4 and the obvious reading gave a file count of zero:

  the binary ends with [pck][pck_size: u64][b"GDPC"], so the pack starts at
  filesize - 12 - pck_size. Its header is GDPC, format(u32), then the engine's
  major/minor/patch, then flags(u32) and file_base(u64). THE DIRECTORY IS NOT
  NEXT: at +32 from the pack start there is a u64 offset to it, at the END of
  the pack. There sits the file count and then, per file, a length-prefixed
  path, offset, size, an md5, and a flags word.
"""
import struct
import sys


def contents(path):
    """Every path inside the pack embedded in `path`, without the res:// prefix."""
    blob = open(path, "rb").read()
    if blob[-4:] != b"GDPC":
        raise SystemExit("%s has no embedded pack (no GDPC at the end)" % path)
    size = struct.unpack("<Q", blob[-12:-4])[0]
    base = len(blob) - 12 - size
    if blob[base:base + 4] != b"GDPC":
        raise SystemExit("%s: the pack does not start where its size says" % path)

    fmt = struct.unpack("<I", blob[base + 4:base + 8])[0]
    if fmt != 4:
        raise SystemExit(
            "%s is pack format %d and this reads format 4. The layout below was "
            "read off a 4.7 export; check it against the engine before trusting it."
            % (path, fmt))

    at = base + struct.unpack("<Q", blob[base + 32:base + 40])[0]
    count = struct.unpack("<I", blob[at:at + 4])[0]
    at += 4
    out = []
    for _ in range(count):
        length = struct.unpack("<I", blob[at:at + 4])[0]
        at += 4
        name = blob[at:at + length].rstrip(b"\0").decode("utf-8")
        at += length
        at += 8 + 8 + 16 + 4          # offset, size, md5, flags
        out.append(name.replace("res://", ""))
    return sorted(out)


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit(__doc__.strip().split("\n")[2].strip())
    print("\n".join(contents(sys.argv[1])))
