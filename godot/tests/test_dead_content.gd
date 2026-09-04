## Headless check for CONTENT FIELDS NOTHING READS.
##   godot --headless --path godot -s tests/test_dead_content.gd
##
## This exists because the same bug has now happened four times on this port,
## and every time it was found by accident:
##
##   - `Content.LOAD_EXAMPLE_MODS` was a constant nothing consulted, so the
##     setting it documented did not exist;
##   - every reader's `unlock` field was read by nobody, so all thirteen were
##     available regardless and the field was decoration;
##   - an elite's `twist.t` sentence was never displayed, so an elite silently
##     changed the fight and the player was told only "ELITE";
##   - the `{S}`/`{es}` pronoun tokens had no substituter, so every sign rule
##     reached the player with the braces still in it.
##
## They share a shape: data faithfully ported, plausible-looking, and inert.
## Nothing errors, nothing looks wrong in a screenshot, and no test fails —
## the feature simply is not there. A grep is all it takes to find them, so
## this does the grep on every run rather than waiting for a fifth accident.
##
## HOW IT WORKS: collect every distinct key across every record in every
## registry, then look for that key as a quoted string anywhere in the .gd
## sources. A key that appears nowhere is either read dynamically (fine) or
## dead (a finding). KNOWN below records which, with the reason, so the check
## passes on today's state and fails the moment a NEW unread key appears.
##
## LIMITS, stated plainly, because a check whose precision is oversold is worse
## than no check. It is a grep: it proves a key is MENTIONED, not that it is
## used correctly, and a short key can be mentioned coincidentally ("p" is both
## a sitter's pronoun field and a pronoun token). So it under-reports. It does
## not over-report, which is the direction that matters — a newly-added inert
## field cannot slip past it.
##
## It also has to skip its own file. KNOWN names every key it exempts, so a
## self-scan would find each of them "mentioned" and the check would quietly
## pass on everything, forever, while looking like it worked. That is the same
## failure mode it exists to catch, which is a good joke and a real hazard.
extends SceneTree

## This file, excluded from the scan — see the header.
const SELF := "test_dead_content.gd"

## Keys that are legitimately absent from the source as literals, with why.
## "dynamic" — read by variable, so a literal would not appear.
## "dead"    — genuinely unread. Kept rather than deleted, and named here so
##             it stays visible instead of being rediscovered later.
## Registries whose dictionary keys are IDS FROM ELSEWHERE rather than field
## names. `icons` is {kind: {name: art}} — two levels deep, unlike every other
## dict registry — so its inner keys are element/sign/planet ids, looked up
## dynamically by whatever is being drawn. Scanning them as though they were
## fields asks "does the literal 'MERCURY' appear in a .gd file", which it
## never will and never should.
const ID_KEYED := ["icons"]

const KNOWN := {
	# I18n.fill() looks these up as table[token], where token comes from a
	# regex over the sentence — no literal ever appears.
	"S": "dynamic", "s": "dynamic", "O": "dynamic", "o": "dynamic",
	"P": "dynamic", "p": "dynamic", "R": "dynamic", "r": "dynamic",
	"is": "dynamic", "es": "dynamic", "has": "dynamic", "do": "dynamic",
	"goes": "dynamic",
	# Rules.next_wall() reads denial_shield[quirk.fx]; "shield" happens to
	# appear as a literal elsewhere and "tide" does not.
	"tide": "dynamic",
	# DEAD, and dead in the prototype too: `guard: 3` sits on one card
	# ("Let Them Say The Worst Of It") and appears in no scoring code on
	# either side of the port. An abandoned mechanic, not a porting miss —
	# so it is neither implemented (that would be inventing a rule the author
	# never wrote) nor deleted (that would discard the intention).
	"guard": "dead",
	# PROVENANCE, not a game field, and deliberately not read by anything. The
	# eight ordinary events added during the port carry `"added": "port"` so the
	# game's author can find every line somebody else wrote in one search and
	# replace it. A marker the code acts on would be a marker that changes the
	# game; this one only has to be greppable.
	"added": "dead",
}

var failures: Array[String] = []
var content: Node


func _initialize() -> void:
	content = root.get_node("Content")
	await process_frame
	content.reload()

	var used := _keys_in_content()
	var src := _all_source()

	var dead: Array[String] = []
	for key in used:
		if src.contains('"%s"' % key) or src.contains("'%s'" % key):
			continue
		if not KNOWN.has(key):
			failures.append(
				"'%s' (in %s) appears in no .gd file — either wire it up or add it to KNOWN with a reason"
				% [key, ", ".join(used[key])])
		elif KNOWN[key] == "dead":
			dead.append(key)

	_check_the_readme_lists_every_test()
	_check_no_autoload_or_test_preloads_a_scene_script()
	_check_the_version_is_written_down_once()

	if not dead.is_empty():
		print("  known-dead content fields (see KNOWN): %s" % ", ".join(dead))
	if failures.is_empty():
		print("ALL PASS — %d content keys, %d accounted for as dynamic or dead" % [used.size(), KNOWN.size()])
		quit(0)
	else:
		for f in failures:
			printerr("FAIL: ", f)
		quit(1)


## The README's test list is maintained by hand, so it drifts: it said "all
## thirteen" while fifteen existed, because two tests were added and the README
## was not. A test nobody knows to run is not much better than one that does not
## exist — and this file is already the place where "something exists that
## nothing accounts for" is caught, so the check belongs here.
##
## Membership and the count only. The one-line description beside each entry is
## prose and stays a human's job.
func _check_the_readme_lists_every_test() -> void:
	var readme := FileAccess.get_file_as_string("res://README.md")
	if readme == "":
		failures.append("README.md is missing or unreadable")
		return

	var files: Array[String] = []
	var d := DirAccess.open("res://tests")
	d.list_dir_begin()
	var name := d.get_next()
	while name != "":
		# gen_* tools, the screenshot tool and the balance report are not
		# pass/fail tests; the README documents those in their own sections.
		if name.begins_with("test_") and name.ends_with(".gd"):
			files.append(name)
		name = d.get_next()
	d.list_dir_end()
	files.sort()

	for f in files:
		if not readme.contains("tests/" + f):
			failures.append("tests/%s is not listed in README.md — nobody would know to run it" % f)

	var expected := "All %s should print" % _spelt(files.size())
	if not readme.contains(expected):
		failures.append("README.md should say \"%s\" — there are %d test files" % [expected, files.size()])


func _spelt(n: int) -> String:
	const WORDS := ["zero", "one", "two", "three", "four", "five", "six", "seven",
		"eight", "nine", "ten", "eleven", "twelve", "thirteen", "fourteen",
		"fifteen", "sixteen", "seventeen", "eighteen", "nineteen", "twenty"]
	return WORDS[n] if n < WORDS.size() else str(n)


## The version exists in two places that cannot disagree: autoload/Version.gd,
## which the menu and the credits read, and data/base/mod.json, which declares
## the version of the CONTENT the base pack ships. They are different things
## and could in principle diverge — but not silently, and not by neglect, which
## is what would happen the first time one was bumped and the other forgotten.
func _check_the_version_is_written_down_once() -> void:
	var declared := str(content.registries.get("_version", ""))
	var manifest := FileAccess.get_file_as_string("res://data/base/mod.json")
	var parsed = JSON.parse_string(manifest)
	if typeof(parsed) != TYPE_DICTIONARY:
		failures.append("data/base/mod.json does not parse")
		return
	var in_manifest := str(parsed.get("version", ""))
	var in_code := str(root.get_node("Version").string())
	if in_manifest != in_code:
		failures.append(
			"the base pack says version %s and Version.gd says %s — bump both or neither"
			% [in_manifest, in_code])


## THE PRELOAD TRAP, made into a rule.
##
## Six times in this port, a file has been broken by `preload()`ing a scene
## script. preload() resolves while the FILE CONTAINING IT is compiled — and
## anything launched with `godot -s`, or any autoload, is compiled before the
## autoloads are registered. Every script under scenes/ refers to autoloads
## (I18n, Content, Settings, Run...), so preloading one from that position
## compiles it to nothing, silently, and every later call on it fails.
##
## The worst case did not even fail locally: preloading RunHeader from a test
## left RunHeader compiled to nothing for the whole process, so every in-run
## screen lost its header and six unrelated cases in that file went red.
##
## The rule that covers all six: nothing in autoload/ or tests/ may preload a
## script under scenes/. Use load() at call time, by which point the autoloads
## exist. Scene scripts preloading each other is fine and is not touched here —
## they are only ever compiled once the game is running.
##
## A text scan, not a runtime check, because the failure IS at compile time:
## by the time anything could observe it at runtime the damage is done.
func _check_no_autoload_or_test_preloads_a_scene_script() -> void:
	for dir_path in ["res://autoload", "res://tests"]:
		# _gather() collects file CONTENTS, not paths — it exists to build one
		# big haystack for the dead-key scan. This needs to name the offender,
		# so it walks for paths of its own.
		var files: Array[String] = []
		_gather_paths(dir_path, files)
		for path in files:
			var text := FileAccess.get_file_as_string(path)
			var line_no := 0
			for line in text.split("\n"):
				line_no += 1
				var stripped := line.strip_edges()
				if stripped.begins_with("#"):
					continue   # a comment explaining the trap is not the trap
				if line.contains("preload(\"res://scenes/"):
					failures.append(
						"%s:%d preloads a scene script — use load() at call time, or it compiles to nothing when run with `godot -s`"
						% [path, line_no])


## Paths of every .gd under `dir_path`, recursively. Skips this file: it holds
## the offending string as a literal, and a scanner that trips over its own
## search term is a scanner nobody trusts.
func _gather_paths(dir_path: String, out: Array[String]) -> void:
	var d := DirAccess.open(dir_path)
	if d == null:
		return
	d.list_dir_begin()
	var name := d.get_next()
	while name != "":
		var full := dir_path.path_join(name)
		if d.current_is_dir():
			if not name.begins_with("."):
				_gather_paths(full, out)
		elif name.ends_with(".gd") and name != SELF:
			out.append(full)
		name = d.get_next()
	d.list_dir_end()


## key -> the registries it appears in, across every record of every registry.
func _keys_in_content() -> Dictionary:
	var out: Dictionary = {}
	for reg in content.registries:
		if ID_KEYED.has(str(reg)):
			continue
		var value = content.registries[reg]
		var records: Array = []
		if typeof(value) == TYPE_ARRAY:
			for r in value:
				if typeof(r) == TYPE_DICTIONARY:
					records.append(r)
		elif typeof(value) == TYPE_DICTIONARY:
			for v in value.values():
				if typeof(v) == TYPE_DICTIONARY:
					records.append(v)
		for rec in records:
			for k in rec:
				var key := str(k)
				# "_"-prefixed keys are bookkeeping (author comments, the pack
				# stamp), not content the game is expected to read.
				if key.begins_with("_"):
					continue
				if not out.has(key):
					out[key] = []
				if not out[key].has(reg):
					out[key].append(reg)
	return out


func _all_source() -> String:
	var parts: Array[String] = []
	_gather("res://", parts)
	return "\n".join(parts)


func _gather(dir_path: String, out: Array[String]) -> void:
	var d := DirAccess.open(dir_path)
	if d == null:
		return
	d.list_dir_begin()
	var name := d.get_next()
	while name != "":
		var full := dir_path.path_join(name) if dir_path.ends_with("/") == false else dir_path + name
		if d.current_is_dir():
			if not name.begins_with(".") and name != "assets":
				_gather(full + "/", out)
		elif (name.ends_with(".gd") or name.ends_with(".py")) and name != SELF:
			out.append(FileAccess.get_file_as_string(full))
		name = d.get_next()
	d.list_dir_end()
