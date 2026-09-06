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
	# The composer's own column in data/base/music.json — what each cue is FOR,
	# in words, for whoever writes the track. Read by a person, not by the game,
	# exactly like the art manifest's `notes`.
	"notes": "dead",
}

var failures: Array[String] = []
var content: Node


func _initialize() -> void:
	content = root.get_node("Content")
	await process_frame
	content.reload()

	_check_the_build_can_name_itself()
	var used := _keys_in_content()
	var src := _all_source()
	_check_every_kind_of_art_is_shown(src)

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
	_check_everything_agrees_on_the_engine()
	_check_the_front_doors_point_at_real_files()

	if not dead.is_empty():
		print("  known-dead content fields (see KNOWN): %s" % ", ".join(dead))
	if failures.is_empty():
		print("ALL PASS — %d content keys, %d accounted for as dynamic or dead" % [used.size(), KNOWN.size()])
		quit(0)
	else:
		for f in failures:
			printerr("FAIL: ", f)
		quit(1)


## THE REPOSITORY'S TWO FRONT DOORS NAME FILES THAT EXIST.
##
## The root README and CLAUDE.md are the first things a person or an agent
## opens, and they are almost entirely a list of paths: run this script, read
## that guide, the game is under here. A path that has been renamed or removed
## turns the front door into a set of wrong directions, and nothing about that
## is visible — the file still reads perfectly.
##
## This is not hypothetical for this repository. Its root README spent the whole
## port telling a coding agent to read thirteen design transcripts and recreate
## the mockups pixel-perfectly, months after the port was finished and living in
## godot/. It was accurate the day it was written and nobody opened it again.
##
## Only backticked paths are checked. Prose says "the reading screen"; the
## things this is about are the ones written as `godot/build.sh`, and quoting
## them is already the convention in both files.
const FRONT_DOORS := ["CLAUDE.md", "README.md"]


func _check_the_front_doors_point_at_real_files() -> void:
	# These live ABOVE res://, which is godot/. Godot refuses to walk out of
	# res:// with "..", so they are opened as ordinary absolute OS paths.
	var repo := ProjectSettings.globalize_path("res://").path_join("..").simplify_path()
	for name in FRONT_DOORS:
		var path: String = repo.path_join(name)
		var text := FileAccess.get_file_as_string(path)
		if text == "":
			failures.append("%s is missing or unreadable — it is the first thing anyone opens" % name)
			continue
		for quoted in _backticked(text):
			# A path INSIDE THE REPOSITORY, not a command, a code fragment or a
			# place on the machine: it has a directory separator, no spaces, no
			# punctuation that belongs to code, and it does not start at the
			# filesystem root. `/tmp` and `preload("res://scenes/…")` are both
			# things these documents legitimately say and neither is a promise
			# about a file in this tree.
			if not quoted.contains("/") or quoted.begins_with("/"):
				continue
			if quoted.contains(" ") or quoted.contains("$") or quoted.contains("(") \
					or quoted.contains("\"") or quoted.contains("…") or quoted.contains("<"):
				continue
			var target: String = repo.path_join(quoted)
			if not (FileAccess.file_exists(target) or DirAccess.dir_exists_absolute(target)):
				failures.append("%s points at `%s`, which does not exist" % [name, quoted])


## Everything between a pair of backticks on one line. Fenced blocks are skipped
## whole: they hold shell lines, and a command is not a promise that a path
## exists — `cd godot` is not a file.
func _backticked(text: String) -> Array[String]:
	var out: Array[String] = []
	var fenced := false
	for line in text.split("\n"):
		if line.begins_with("```"):
			fenced = not fenced
			continue
		if fenced:
			continue
		var parts := line.split("`")
		# Odd indices are the quoted spans: a,`b`,c splits to [a, b, c].
		var i := 1
		while i < parts.size():
			var span := str(parts[i]).strip_edges()
			if span != "":
				out.append(span)
			i += 2
	return out


## THE ENGINE THIS IS RUNNING ON IS THE ENGINE THE PROJECT ASKS FOR, AND THE
## ONE THE README TELLS PEOPLE TO FETCH.
##
## The version is written down in three places that cannot see each other:
## project.godot's `config/features`, which is what Godot itself reads; the
## README's download URL, which is what a new contributor and the CI runner both
## follow; and whatever binary is actually in front of you. Nothing compared
## them.
##
## The failure this guards against is quiet in the worst way. A suite run on the
## wrong engine still goes green — GDScript is forgiving across minor versions —
## and reports that a build nobody has tested is fine. It is the same shape as
## every other bug in this file: a fact kept in more than one place, with nothing
## to notice when they part company.
##
## Compared at MAJOR.MINOR. A patch release is not a different engine and
## pinning to one would fail the day 4.7.1 lands.
func _check_everything_agrees_on_the_engine() -> void:
	var info := Engine.get_version_info()
	var running := "%d.%d" % [int(info["major"]), int(info["minor"])]

	var declared := ""
	for feature in ProjectSettings.get_setting("application/config/features", PackedStringArray()):
		# The feature list also carries the renderer ("GL Compatibility"); the
		# version is the entry shaped like a number.
		if str(feature).split(".").size() == 2 and str(feature).replace(".", "").is_valid_int():
			declared = str(feature)
	if declared == "":
		failures.append("project.godot declares no engine version in config/features")
	elif declared != running:
		failures.append("this is Godot %s but project.godot asks for %s — the suite is green on an engine nobody ships"
			% [running, declared])

	# The README hands out a download URL. If it names a different version, the
	# next person to follow it gets an engine the project does not want, and the
	# first thing they will do is run this suite and believe it.
	var readme := FileAccess.get_file_as_string("res://README.md")
	if readme == "":
		failures.append("README.md is missing or unreadable")
		return
	# Read out of the URL itself, not searched for anywhere in the file. The
	# first version of this asked whether the string "4.7-stable" appeared in
	# the README at all — which it does, in the prose two lines below, so
	# pointing the download link at 4.6 changed nothing and the check passed.
	# A guard that a wrong answer satisfies is not a guard.
	const MARK := "releases/download/"
	var at := readme.find(MARK)
	if at < 0:
		return  # No download instructions to disagree with.
	var tag := readme.substr(at + MARK.length())
	tag = tag.substr(0, tag.find("/"))
	var wanted := "%s-stable" % running
	if tag != wanted:
		failures.append("README.md's download link fetches Godot %s, but this project runs on %s — the next person to follow it installs the wrong engine and this suite will tell them it is fine"
			% [tag, wanted])


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


## The count in words, because the README says "All twenty should print" and a
## sentence is what a person reads.
##
## The list used to stop at twenty and fall back to the digits — so adding a
## twenty-first test asked the README to say "All 21 should print", which is not
## a sentence anybody would write. A hand-kept list that quietly stops listing
## is the exact failure this whole file exists to catch, and it had one in it.
## Composed now, up to ninety-nine, which is more tests than this project will
## ever have.
func _spelt(n: int) -> String:
	const ONES := ["zero", "one", "two", "three", "four", "five", "six", "seven",
		"eight", "nine", "ten", "eleven", "twelve", "thirteen", "fourteen",
		"fifteen", "sixteen", "seventeen", "eighteen", "nineteen"]
	const TENS := ["", "", "twenty", "thirty", "forty", "fifty", "sixty",
		"seventy", "eighty", "ninety"]
	if n < 0 or n > 99:
		return str(n)
	if n < ONES.size():
		return ONES[n]
	var tens: String = TENS[n / 10]
	return tens if n % 10 == 0 else "%s-%s" % [tens, ONES[n % 10]]


## A BUILD SAYS WHICH COMMIT IT IS, or says nothing — never something wrong.
##
## Version.gd's MAJOR/MINOR/PATCH are bumped by hand, so every build between two
## bumps calls itself the same thing. An export sat in build/ for a day and
## fifty-four commits, and running it showed a game with no drawn room and a
## different menu: the obvious reading was a broken export, the true one was an
## old one, and nothing in the binary could tell them apart.
##
## build.sh writes res://build_stamp.cfg just before exporting and removes it
## after. This checks the reading of it, both ways round, because both matter:
## a stamp that is not read leaves the build anonymous, and a stamp read when
## there is none would put a fabricated commit on the credits screen.
func _check_the_build_can_name_itself() -> void:
	var version: Node = root.get_node("Version")

	# No stamp: silent, and full() is still a sensible line.
	var missing := "user://no_such_stamp.cfg"
	if version.build(missing) != "":
		failures.append("Version.build() invented '%s' from a stamp that does not exist"
			% version.build(missing))
	if version.build_detail(missing) != "":
		failures.append("Version.build_detail() invented a detail with no stamp")

	# A clean stamp, and a dirty one.
	var path := "user://test_stamp.cfg"
	for dirty in [false, true]:
		var cfg := ConfigFile.new()
		cfg.set_value("build", "commit", "abc1234")
		cfg.set_value("build", "branch", "main")
		cfg.set_value("build", "dirty", dirty)
		cfg.set_value("build", "at", "2026-01-01T00:00:00Z")
		cfg.save(path)
		var got: String = version.build(path)
		if not got.begins_with("abc1234"):
			failures.append("a stamped build reports '%s', which does not name its commit" % got)
		if got.contains("modified") != dirty:
			failures.append("a %s tree reports '%s' — the modified marker is the wrong way round"
				% ["dirty" if dirty else "clean", got])
		if not version.build_detail(path).contains("main"):
			failures.append("build_detail() drops the branch: '%s'" % version.build_detail(path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

	# And the export has to actually CARRY the file, or all of the above is
	# read from a stamp that never reaches a player.
	var presets := FileAccess.get_file_as_string("res://export_presets.cfg")
	if presets != "" and not presets.contains("build_stamp.cfg"):
		failures.append("export_presets.cfg does not include build_stamp.cfg — a .cfg at the project root is not a resource Godot imports, so the stamp is written, ignored, and the build stays anonymous")


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


## THE GAME'S OWN SOURCE — autoload/ and scenes/ — and deliberately not tests/
## or the dev tools under it.
##
## A field a generator or a screenshot script touches is not a field the GAME
## reads, and counting those as readers is how `sp` hid: every card carries the
## clause it is spoken as, tests/gen_art_manifest.gd copied it into the art
## manifest, and on that evidence this check called it used for the whole port
## while the reading screen showed card names and no sentence at all.
## ART THE MANIFEST ASKS FOR THAT NO SCREEN WOULD EVER SHOW.
##
## The dead-content check above is about data nothing reads. This is the same
## question asked of somebody's WORK: the manifest commissions art by `kind`,
## and every kind must have a screen that puts it up. It did not. Thirteen
## reader portraits had been on the list since the manifest was written and
## `Art.reader_texture()` was called from nowhere at all — an artist could have
## drawn every reader in the game and never seen one of them in it.
func _check_every_kind_of_art_is_shown(src: String) -> void:
	var raw := FileAccess.get_file_as_string("res://data/base/art_manifest.json")
	var parsed = JSON.parse_string(raw)
	if typeof(parsed) != TYPE_DICTIONARY or not parsed.has("assets"):
		failures.append("the art manifest should be readable and hold an 'assets' block")
		return
	var kinds := {}
	for id in parsed["assets"]:
		kinds[str(parsed["assets"][id].get("kind", ""))] = true
	for kind in kinds:
		if kind == "":
			continue
		# The accessor Art.gd exposes per kind, CALLED — "Art." and all. Without
		# the prefix the definition inside Art.gd matches its own check and every
		# kind passes forever, which is how this test first passed with reader
		# portraits still displayed nowhere.
		if not src.contains("Art.%s_texture(" % kind):
			failures.append(
				"the art manifest commissions '%s' art and no screen calls Art.%s_texture() — it would never be seen"
				% [kind, kind])


func _all_source() -> String:
	var parts: Array[String] = []
	for dir_path in ["res://autoload", "res://scenes"]:
		_gather(dir_path + "/", parts)
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
