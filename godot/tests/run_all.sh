#!/usr/bin/env bash
#
# Runs the whole test suite and says one thing: green, or what went wrong.
#
#     tests/run_all.sh              (from the godot/ directory)
#     GODOT=/path/to/godot tests/run_all.sh
#
# There was no runner. Seventeen files were run by hand, in a shell loop
# retyped from memory each time, and "the suite is green" meant "I grepped for
# FAIL and did not see any". That is fine until the day something prints an
# ERROR instead of a FAIL — which is most of the interesting failures, since
# Godot reports a null dereference, a bad theme override, a freed capture and a
# malformed scene as engine errors and carries on.
#
# So this checks BOTH:
#
#   1. no test printed FAIL;
#   2. no ERROR or WARNING came out that is not on the list below.
#
# The second half is the one that earns its keep. The suite deliberately drives
# a lot of error paths — a corrupt save, an unwritable disk, a mod with broken
# JSON, an option naming a card nobody has — so it cannot simply demand
# silence. Every expected line is named here WITH THE TEST THAT CAUSES IT, so a
# new one has to be looked at and either fixed or added on purpose.
#
# That is not hypothetical: ten "Lambda capture at index 0 was freed" errors sat
# in this suite's output for weeks, printed on every run, ignored because the
# FAIL count was zero. They turned out to be the map's knock still pending when
# the screen was torn down. See docs/PORTING_NOTES.md.
set -u

GODOT="${GODOT:-$HOME/bin/godot}"
cd "$(dirname "$0")/.." || exit 2

# THE SEED THE WHOLE RUN IS PLAYED ON.
#
# Fifty-nine of the suite's runs are started with no seed, on purpose: a
# different evening every time is how the soak test and the scene sweep find
# things a fixed fixture never would. The cost was that a failure could not be
# replayed — one run of this suite failed once and twenty-two afterwards did
# not, and there was nothing left of the first but the memory of it.
#
# So the series is pinned rather than fixed. Run.gd seeds the global generator
# from PARLOUR_SEED, so the first unseeded run, the second and the fortieth are
# the same forty evenings for a given seed and different ones for another. A
# fresh seed is drawn per run and PRINTED, and printed again beside any failure
# with the line that replays it.
PARLOUR_SEED="${PARLOUR_SEED:-$(date +%s)-$$}"
export PARLOUR_SEED

# Every expected ERROR/WARNING, and which test deliberately causes it. A line
# not matching any of these fails the run.
ALLOWED=(
  # test_save.gd writes a deliberately corrupt save and reads it back.
  'Condition "\(uint32_t\)buff\.size\(\) != len"'
  '\[Save\] the save was unreadable'
  # test_save.gd / test_scenes.gd make user:// unwritable on purpose.
  '\[Save\] could not put the save in place'
  '\[Settings\] could not write'
  '\[Profile\] could not write'
  # test_settings.gd asks for settings and values that do not exist.
  "\[Settings\] unknown setting 'no_such_setting'"
  '\[Settings\] .* had an unknown value'
  # test_modloader.gd feeds the loader malformed JSON.
  'Parse JSON failed'
  # test_run.gd resolves names nothing answers to, to prove they are dropped
  # rather than handed over empty.
  '\[Run\] an option names the'
  # test_profile.gd / test_minitel.gd exercise malformed unlocks and codes.
  '\[Profile\] unlock '
  '\[Minitel\] BRKN'
  # Godot's own exit-time bookkeeping in `-s` mode: the SceneTree is torn down
  # without a main scene, so nodes the script parented to the root are still
  # alive at quit. Not a leak in the game.
  'ObjectDB instances were leaked'
  'RIDs? of type .* (was|were) leaked'
)

pattern=""
for a in "${ALLOWED[@]}"; do
  pattern="${pattern:+$pattern|}$a"
done

fails=0
noise=0
files=0
FAILED_DIR="${FAILED_DIR:-/tmp/parlour-failures}"
rm -rf "$FAILED_DIR"

for f in tests/test_*.gd; do
  name="$(basename "$f" .gd)"
  files=$((files + 1))
  out="$("$GODOT" --headless --path . -s "$f" 2>&1)"

  f_lines="$(printf '%s\n' "$out" | grep -c 'FAIL')"
  n_lines="$(printf '%s\n' "$out" | grep -E '^(ERROR|WARNING|SCRIPT ERROR)' | grep -Ev "$pattern")"
  n_count=0
  [ -n "$n_lines" ] && n_count="$(printf '%s\n' "$n_lines" | wc -l | tr -d ' ')"

  if [ "$f_lines" -eq 0 ] && [ "$n_count" -eq 0 ]; then
    printf '  ok    %s\n' "$name"
  else
    printf '  FAIL  %s  (%s failure(s), %s unexpected line(s))\n' "$name" "$f_lines" "$n_count"
    printf '%s\n' "$out" | grep 'FAIL' | sed 's/^/        /'
    [ -n "$n_lines" ] && printf '%s\n' "$n_lines" | sed 's/^/        /'
    # THE WHOLE OUTPUT, KEPT. What a failing test printed before it failed is
    # most of the evidence, and until now it was thrown away the moment the
    # next test ran — which is exactly what happened to the one failure this
    # suite has had that nobody could reproduce.
    mkdir -p "$FAILED_DIR"
    printf '%s\n' "$out" > "$FAILED_DIR/$name.log"
    printf '        full output: %s/%s.log\n' "$FAILED_DIR" "$name"
    printf '        replay it:   PARLOUR_SEED=%s %s --headless --path . -s %s\n' \
      "$PARLOUR_SEED" "$GODOT" "$f"
  fi
  fails=$((fails + f_lines))
  noise=$((noise + n_count))
done

echo
if [ "$fails" -eq 0 ] && [ "$noise" -eq 0 ]; then
  echo "ALL GREEN — $files test files, no failures, nothing unexpected on the console."
  echo "            played on PARLOUR_SEED=$PARLOUR_SEED"
  exit 0
fi
echo "NOT GREEN — $files test files, $fails failure(s), $noise unexpected console line(s)."
echo "            played on PARLOUR_SEED=$PARLOUR_SEED — set it to replay this exact run."
echo "            full output of each failing file: $FAILED_DIR"
exit 1
