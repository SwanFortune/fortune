#!/usr/bin/env bash
#
# Plays the EXPORTED build. Not the source tree, not a scene instantiated by a
# test — the binary a player is handed, driven through real screens with real
# keystrokes.
#
#     tests/smoke_export.sh              (from the godot/ directory; builds first)
#     tests/smoke_export.sh --no-build   (use the binary already in build/linux)
#
# WHY THIS EXISTS. The headless suite instantiates screens directly and never
# boots the main scene, and an export is a different thing again: resources are
# packed, `tests/*` is filtered out, and a file the packer skipped is missing
# only in the shipped artefact. Every bug of that shape is invisible until
# somebody runs the binary — and running it is how a day-old build was mistaken
# for a broken export, twice.
#
# Needs xvfb-run, xdotool and ImageMagick. It is not part of run_all.sh: it
# builds a 74 MB binary and takes a minute.
#
# WHAT IT ASSERTS
#   1. the build starts and is still alive at the end;
#   2. the console carries nothing but the known environment complaints;
#   3. EVERY STEP CHANGES THE SCREEN. A key that reaches nothing leaves the
#      frame identical, which is what a scene that failed to load looks like;
#   4. WHAT IS ACTUALLY IN THE PACK. Every .json the content pipeline reads and
#      every locale table, present by the exact path the game asks for — and
#      tests/* absent, which this file's own header claims and nothing checked.
#      Added after the shipped build turned out to have no sound at all: the
#      pack carries a converted .sample and not the .wav, and Audio.gd reads
#      bytes by path on purpose. See tests/pck_contents.py.
set -u

cd "$(dirname "$0")/.."
GODOT="${GODOT:-$HOME/bin/godot}"
OUT="${OUT:-/tmp/smoke_export}"
BIN="../build/linux/parlour.x86_64"

for tool in xvfb-run xdotool convert xwd; do
  command -v "$tool" >/dev/null || { echo "  needs $tool — apt-get install xvfb xdotool imagemagick x11-apps"; exit 2; }
done

if [ "${1:-}" != "--no-build" ]; then
  ./build.sh Linux || exit 1
fi
[ -x "$BIN" ] || { echo "  no build at $BIN"; exit 2; }

rm -rf "$OUT"; mkdir -p "$OUT"

# Each step is a label and the key that should get there from the one before.
STEPS="menu: sign:Return gift:Return map:Return reading:Return laid:Return"

cat > "$OUT/drive.sh" <<'INNER'
#!/bin/bash
OUT="$1"; BIN="$2"; shift 2
rm -rf "$HOME/.local/share/godot/app_userdata/Parlour/save.dat"*
"$BIN" >"$OUT/console.log" 2>&1 &
echo $! > "$OUT/pid"
sleep 10
# THE WINDOW, NOT THE ROOT, so a frame is the game and nothing else and the
# comparison below cannot be moved by anything outside it. Here they happen to
# be the same rectangle — which is worth knowing: a root capture once showed the
# game in the corner of a black band and the obvious explanation was that the
# capture was cropping it. It was not. The game really was drawing 1152x648 into
# a 1280x720 window, and the fix was the project canvas, not this.
WIN=$(xdotool search --name . 2>/dev/null | tail -1)
grab() { if [ -n "$WIN" ]; then xwd -id "$WIN" -silent; else xwd -root -silent; fi; }
i=0
for step in "$@"; do
  label="${step%%:*}"; key="${step#*:}"
  if [ -n "$key" ]; then xdotool key --clearmodifiers "$key"; sleep 3; fi
  i=$((i + 1))
  grab | convert xwd:- png:"$OUT/$(printf '%d' $i)_$label.png" 2>/dev/null
done
pid=$(cat "$OUT/pid")
kill -0 "$pid" 2>/dev/null && echo alive > "$OUT/alive"
kill "$pid" 2>/dev/null
INNER
chmod +x "$OUT/drive.sh"
timeout 240 xvfb-run -a -s "-screen 0 1280x720x24" "$OUT/drive.sh" "$OUT" "$BIN" $STEPS

fails=0

[ -f "$OUT/alive" ] || { echo "  FAIL  the build was not running at the end — it crashed or quit"; fails=$((fails+1)); }

# The same allow-list idea as run_all.sh: name what this container is expected
# to complain about, and treat anything else as real.
ALLOWED='Could not set V-Sync mode|All audio drivers failed|Condition "status < 0" is true|ALSA|pulseaudio|PulseAudio'
noise=$(grep -E '^(ERROR|SCRIPT ERROR|WARNING)' "$OUT/console.log" 2>/dev/null | grep -Ev "$ALLOWED")
if [ -n "$noise" ]; then
  echo "  FAIL  the exported build printed something unexpected:"
  printf '%s\n' "$noise" | sed 's/^/        /'
  fails=$((fails + $(printf '%s\n' "$noise" | wc -l)))
fi

# WHAT THE PACK CARRIES. Cheap, exact, and the only check here that can say
# WHY a screen is wrong rather than that it is.
if ! python3 tests/pck_contents.py "$BIN" > "$OUT/pck.txt" 2>"$OUT/pck.err"; then
  echo "  FAIL  could not read the pack: $(cat "$OUT/pck.err")"
  fails=$((fails + 1))
else
  before=$fails
  for want in $(cd . && ls data/base/*.json data/base/locale/*.json); do
    grep -qx "$want" "$OUT/pck.txt" || {
      echo "  FAIL  $want is not in the exported pack — the build ships without it"
      fails=$((fails + 1))
    }
  done
  if grep -q "^tests/" "$OUT/pck.txt"; then
    echo "  FAIL  the pack carries tests/ — exclude_filter is not doing its job"
    fails=$((fails + 1))
  fi
  # Only when nothing above it failed — an "ok" printed under its own failures
  # is the kind of output that gets skimmed and believed.
  [ "$fails" -eq "$before" ] && \
    echo "  ok    the pack carries $(wc -l < "$OUT/pck.txt") files, content and locale among them, and no tests/"
fi

prev=""
for shot in "$OUT"/*.png; do
  name=$(basename "$shot" .png)
  if [ -n "$prev" ]; then
    diff=$(compare -metric RMSE "$prev" "$shot" null: 2>&1 | sed 's/ .*//')
    same=$(awk -v d="${diff:-0}" 'BEGIN { print (d < 200) ? "1" : "0" }')
    if [ "$same" = "1" ]; then
      echo "  FAIL  $name looks identical to $(basename "$prev" .png) — that key reached nothing"
      fails=$((fails + 1))
    else
      echo "  ok    $name"
    fi
  else
    echo "  ok    $name"
  fi
  prev="$shot"
done

echo
if [ "$fails" -eq 0 ]; then
  echo "PLAYS — the exported build starts, walks five screens and lays a card. Frames in $OUT."
  exit 0
fi
echo "NOT PLAYABLE — $fails problem(s). Frames and console in $OUT."
exit 1
