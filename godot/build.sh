#!/usr/bin/env bash
#
# Exports the game, with the commit it was built from written into it.
#
#     ./build.sh              (from the godot/ directory — every preset)
#     ./build.sh Linux        (one preset, by its name in export_presets.cfg)
#     GODOT=/path/to/godot ./build.sh
#
# THE STAMP IS THE POINT. An export carries the version from Version.gd, which
# a human bumps by hand — so every build between two bumps calls itself the
# same thing. A binary sat in build/ for a day and fifty-four commits, and
# running it showed a game with no drawn room and a different menu; the obvious
# reading was that the export was broken, and the true one was that it was old.
# Nothing in the binary could tell the two apart.
#
# So the short SHA, the branch, whether the tree was dirty, and the date go into
# res://build_stamp.cfg before the export and out again on the credits screen.
# The file is gitignored: it belongs to a build, not to the source.
set -euo pipefail

GODOT="${GODOT:-$HOME/bin/godot}"
cd "$(dirname "$0")"

STAMP="build_stamp.cfg"
sha="$(git rev-parse --short HEAD 2>/dev/null || echo unknown)"
branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo unknown)"
dirty="false"
git diff --quiet HEAD -- . 2>/dev/null || dirty="true"

cat > "$STAMP" <<EOF
; Written by build.sh at export time. Not source — see .gitignore.
[build]

commit="$sha"
branch="$branch"
dirty=$dirty
at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
EOF

[ "$dirty" = "true" ] && echo "  note: the tree has uncommitted changes; the stamp says so."

targets=("$@")
if [ ${#targets[@]} -eq 0 ]; then
  targets=(Linux Windows)
fi

for preset in "${targets[@]}"; do
  case "$preset" in
    Linux)   out="../build/linux/parlour.x86_64" ;;
    Windows) out="../build/windows/parlour.exe" ;;
    macOS)   out="../build/macos/parlour.zip" ;;
    *) echo "  unknown preset '$preset'"; exit 2 ;;
  esac
  mkdir -p "$(dirname "$out")"
  echo "  exporting $preset -> $out"
  if ! "$GODOT" --headless --export-release "$preset" "$out" >/tmp/export_$preset.log 2>&1; then
    echo "  FAILED — see /tmp/export_$preset.log"
    tail -5 "/tmp/export_$preset.log"
    exit 1
  fi
done

rm -f "$STAMP"
echo "  built $sha${dirty:+ }$([ "$dirty" = true ] && echo '(dirty)')"
