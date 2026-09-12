## Rules.gd against the SPECIFICATION ITSELF, not a transcription of it.
##   godot --headless --path godot -s tests/test_against_the_prototype.gd
##
## CLAUDE.md says `project/` is the prototype this was ported from, that it is
## still the specification, and that where the two disagree the prototype is
## right. Until this file, the only thing checking that sentence was a handful
## of cases in tests/test_rules.gd traced by hand — a human transcription of
## what the prototype does. A transcription can be wrong, and worse, it can be
## wrong IN THE SAME DIRECTION as the port: somebody reads the JS, writes the
## GDScript, then writes the expected numbers from the GDScript they just wrote.
## This repository has shipped three tests that passed for the wrong reason and
## one of them was exactly that shape.
##
## The specification is executable. So this runs it. tests/prototype_bridge.js
## cuts simulate() and the five helpers it uses out of the .html at run time and
## runs them under node; both engines are handed the SAME randomly generated
## readings, and every field of both answers has to match.
##
## SOURCE MODE, DERIVED RATHER THAN LISTED. Rules.gd is deliberately not a
## literal port: reader traits take their size from data/base/fx.json, the white
## bonus is capped, pierce pays a `spare` when there is no wall, and the denial
## wall has drain/cap rules the prototype never had. Every one of those says in
## its own comment that 0-or-absent restores the source's behaviour exactly. So
## this empties `fx` and `denial_wall` instead of listing the source's constants
## here — a list of twelve numbers copied out of the JS would be one more copy
## that stops tracking what it copied, in the file whose whole subject is that.
## It also means this test CHECKS those comments: if "absent restores the
## source" is not true of some trait, the run disagrees and says which.
##
## WHAT IS FUZZED AND WHAT IS HELD. Cards, readers, marks, jobs, quirks, walls
## and hand order are all random. Two things are held to what a real game
## produces, and both would otherwise report divergences that no game can reach:
## a sitter always has an element (the two engines disagree about a card with no
## element sitting opposite a sitter with no element, because JS `null === null`
## is true and the port asks for a real element first), and every card carries
## `f` (the port defaults it to 0, JS would make it NaN and poison the sum).
##
## Cases come from the global generator, which Run.gd pins from PARLOUR_SEED —
## so a failing run replays with the seed tests/run_all.sh prints.
extends "res://tests/harness.gd"

## Enough that the rarer combinations (halfbest landing on a banked card,
## minthree with two cards, a wall bigger than the reading) turn up in most
## runs, and still under a second.
const CASES := 2000

const BRIDGE := "res://tests/prototype_bridge.js"

## Every trait the engine asks `has()` about, plus nothing. Derived from what
## Rules.gd actually branches on rather than from fx.json, because a trait in
## the data that the engine ignores is not what is under test here.
const READER_FX := ["", "pierce", "opener", "closer", "steady", "switch2", "perOwn", "white", "serpent", "own3"]
const JOB_FX := ["", "opener3", "closer3", "steady3"]
const QUIRK_FX := ["", "nobonus", "mutefirst", "lasthalf", "halfown", "deadel", "norepeat", "halfbest", "minthree"]
const ELS := ["fire", "earth", "air", "water"]

var content: Node
var rules: Node

var _fx_before: Dictionary = {}
var _wall_before: Dictionary = {}
var _cases: Array = []
var _theirs: Array = []
var _skipped := ""


func setup() -> void:
	content = root.get_node("Content")
	rules = root.get_node("Rules")
	content.reload()
	# Source mode. Restored in teardown() — these are the live registries the
	# rest of the process reads.
	_fx_before = content.fx.duplicate(true)
	_wall_before = content.denial_wall.duplicate(true)
	content.fx = {}
	content.denial_wall = {}

	_cases = _invent(CASES)
	_theirs = _what_the_prototype_says(_cases)


func teardown() -> void:
	content.fx = _fx_before
	content.denial_wall = _wall_before
	content.reload()


func summary() -> String:
	if _skipped != "":
		return _skipped
	return "%d reading(s) agreed with the prototype, field for field" % _cases.size()


## THE WHOLE TEST. Both engines, the same readings, every field.
func _test_the_port_and_the_prototype_agree() -> void:
	if _skipped != "":
		print("  (skipping: %s)" % _skipped)
		done()
		return
	check(_theirs.size() == _cases.size(),
		"the bridge answered %d of %d readings" % [_theirs.size(), _cases.size()])

	var shown := 0
	for i in min(_theirs.size(), _cases.size()):
		var one: Dictionary = _cases[i]
		var mine: Dictionary = rules.simulate(one["ctx"], one["f"])
		var theirs: Dictionary = _theirs[i]
		var where := _first_disagreement(mine, theirs)
		if where == "":
			continue
		# Every mismatch is the same bug until proven otherwise, and two thousand
		# copies of it would bury the case that shows it.
		shown += 1
		if shown > 3:
			continue
		check(false, "reading %d disagrees: %s\n  the reading: %s\n  the port:   %s\n  the spec:   %s"
			% [i, where, JSON.stringify(one["f"]), JSON.stringify(mine), JSON.stringify(theirs)])
	if shown > 3:
		check(false, "%d readings of %d disagree in all; the first three are above"
			% [shown, _cases.size()])
	done()


## THE BRIDGE IS CUTTING OUT THE REAL THING. If the prototype were ever renamed,
## moved, or rewritten so the extractor found nothing, the test above would have
## nothing to compare against — and the cheapest way for that to go wrong is
## silently, with an empty answer that agrees with everything.
func _test_the_bridge_is_reading_the_specification() -> void:
	if _skipped != "":
		print("  (skipping: %s)" % _skipped)
		done()
		return
	check(not _theirs.is_empty(), "the bridge returned nothing at all")
	if _theirs.is_empty():
		done()
		return
	var moved := 0
	for r in _theirs:
		if int(r.get("gross", 0)) != 0 or not r.get("rows", []).is_empty():
			moved += 1
	check(moved > _theirs.size() / 2,
		"only %d of %d readings scored anything — the extractor is probably returning a stub"
		% [moved, _theirs.size()])
	done()


# ── the two engines ─────────────────────────────────────────────────────

func _what_the_prototype_says(cases: Array) -> Array:
	var here := ProjectSettings.globalize_path("user://")
	var cases_path := here.path_join("prototype_cases.json")
	var out_path := here.path_join("prototype_out.json")

	var for_them: Array = []
	for one in cases:
		for_them.append({"state": one["state"], "f": one["f"]})
	var f := FileAccess.open("user://prototype_cases.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(for_them))
	f.close()

	# IS NODE HERE AT ALL — asked separately, and this is not a detail. The first
	# version had one path for both answers, so renaming the function the
	# extractor looks for made the whole file SKIP AND REPORT ALL PASS. A test
	# that cannot find the thing it checks must fail, not excuse itself; only a
	# missing interpreter is a reason to stand down, because this needs a second
	# language to run at all and refusing the whole suite over that is worse.
	var version: Array = []
	if OS.execute("/usr/bin/env", ["node", "--version"], version, true) != 0:
		_skipped = "node is not installed here, so the prototype cannot be run"
		return []

	var said: Array = []
	var code := OS.execute("/usr/bin/env",
		["node", ProjectSettings.globalize_path(BRIDGE), cases_path, out_path], said, true)
	if code != 0:
		# Node works and the bridge did not. Something is wrong with the bridge or
		# with the specification it reads, and either way nothing is being checked.
		failures.append("the bridge could not run the specification:\n%s" % "\n".join(said).strip_edges())
		return []
	var body := FileAccess.get_file_as_string("user://prototype_out.json")
	DirAccess.remove_absolute("user://prototype_cases.json")
	DirAccess.remove_absolute("user://prototype_out.json")
	var parsed = JSON.parse_string(body)
	if not (parsed is Array):
		failures.append("the bridge wrote something that is not a list of readings")
		return []
	return parsed


## The first field where the two answers differ, or "" when they agree.
##
## `halveNote` is compared as PRESENT OR ABSENT, not as text: the prototype
## builds its wording from the sitter's pronoun and the port keeps the wording
## in the locale, which is a translation decision rather than arithmetic.
func _first_disagreement(mine: Dictionary, theirs: Dictionary) -> String:
	for field in ["gross", "pierced", "denial", "absorbed", "applied", "bank", "over",
			"hpAfter", "extraTurns", "coin", "shieldNext"]:
		if int(mine.get(field, 0)) != int(theirs.get(field, 0)):
			return "%s: the port says %s, the prototype says %s" % [field, mine.get(field), theirs.get(field)]
	if (mine.get("halveNote") == null) != (theirs.get("halveNote") == null):
		return "halveNote: the port says %s, the prototype says %s" % [mine.get("halveNote"), theirs.get("halveNote")]

	var my_rows: Array = mine.get("rows", [])
	var their_rows: Array = theirs.get("rows", [])
	if my_rows.size() != their_rows.size():
		return "rows: the port laid out %d, the prototype %d" % [my_rows.size(), their_rows.size()]
	for i in my_rows.size():
		var a: Dictionary = my_rows[i]
		var b: Dictionary = their_rows[i]
		for field in ["i", "total"]:
			if int(a.get(field, 0)) != int(b.get(field, 0)):
				return "row %d %s: the port says %s, the prototype says %s" % [i, field, a.get(field), b.get(field)]
		for field in ["bank", "pierce"]:
			if bool(a.get(field, false)) != bool(b.get(field, false)):
				return "row %d %s: the port says %s, the prototype says %s" % [i, field, a.get(field), b.get(field)]
		# An element the prototype never set comes back as null; the port says "".
		for field in ["el", "link", "note", "name"]:
			var mine_s := str(a.get(field, "")) if a.get(field) != null else ""
			var their_s := str(b.get(field, "")) if b.get(field) != null else ""
			if mine_s != their_s:
				return "row %d %s: the port says '%s', the prototype says '%s'" % [i, field, mine_s, their_s]
	return ""


# ── inventing readings ──────────────────────────────────────────────────

func _invent(how_many: int) -> Array:
	var out: Array = []
	for _i in how_many:
		var reader := {"fx": READER_FX[randi() % READER_FX.size()], "el": ELS[randi() % ELS.size()]}
		var marks: Array = []
		for _m in randi() % 3:
			if randf() < 0.5:
				marks.append({"fx": "el", "el": ELS[randi() % ELS.size()]})
			else:
				marks.append({"fx": READER_FX[randi() % READER_FX.size()]})
		var serp_el: String = ELS[randi() % ELS.size()] if randf() < 0.3 else ""

		var quirk := {"fx": QUIRK_FX[randi() % QUIRK_FX.size()]}
		if quirk["fx"] == "deadel":
			quirk["dead"] = ELS[randi() % ELS.size()]

		var cross: Array = []
		for _c in randi() % 7:
			cross.append(_a_card(cross.size()))
		var sitter_el: String = ELS[randi() % ELS.size()]
		var wall := randi() % 9
		var f := {
			"quirk": quirk,
			"cross": cross,
			"hp": randi() % 20,
			"max": 10 + randi() % 40,
			"denial": wall,
			"denialUp": randi() % 4,
			"el": sitter_el,
			"job": {"fx": JOB_FX[randi() % JOB_FX.size()]},
			"sitter": {"p": "they", "denial": wall, "el": sitter_el},
		}
		out.append({
			"f": f,
			# The same thing said two ways: the prototype keeps it on this.state,
			# the port passes it in.
			"state": {"reader": reader, "marks": marks, "serpEl": serp_el},
			"ctx": {"reader": reader, "marks": marks, "serp_el": serp_el},
		})
	return out


## One laid card. Every field the engine reads, present about as often as the
## base content has it — a fuzzer that gave every card every field would spend
## two thousand readings on a card that exists nowhere.
func _a_card(n: int) -> Dictionary:
	var c := {"n": "c%d" % n, "f": randi() % 9}
	var roll := randf()
	if roll < 0.12:
		c["neutral"] = true
	elif roll < 0.18:
		c["chroma"] = true
	elif roll < 0.24:
		c["wild"] = true
	else:
		c["el"] = ELS[randi() % ELS.size()]
	if randf() < 0.18:
		c["follows"] = "same" if randf() < 0.5 else "turn"
		c["bonus"] = 1 + randi() % 5
	if randf() < 0.10:
		c["perEl"] = ELS[randi() % ELS.size()]
		c["perAmt"] = 1 + randi() % 3
	if randf() < 0.08:
		c["bonusFlat"] = 1 + randi() % 4
	if randf() < 0.08:
		c["solo"] = 1 + randi() % 6
	if randf() < 0.08:
		c["perLaid"] = 1 + randi() % 3
	if randf() < 0.10:
		c["opener"] = 1 + randi() % 4
	if randf() < 0.10:
		c["closer"] = 1 + randi() % 4
	if randf() < 0.08:
		c["next"] = 1 + randi() % 4
	if randf() < 0.06:
		c["turn"] = 1
	if randf() < 0.06:
		c["coin"] = 1 + randi() % 5
	if randf() < 0.10:
		c["bank"] = true
	if randf() < 0.10:
		c["pierce"] = true
	return c
