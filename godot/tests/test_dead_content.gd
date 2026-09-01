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

	if not dead.is_empty():
		print("  known-dead content fields (see KNOWN): %s" % ", ".join(dead))
	if failures.is_empty():
		print("ALL PASS — %d content keys, %d accounted for as dynamic or dead" % [used.size(), KNOWN.size()])
		quit(0)
	else:
		for f in failures:
			printerr("FAIL: ", f)
		quit(1)


## key -> the registries it appears in, across every record of every registry.
func _keys_in_content() -> Dictionary:
	var out: Dictionary = {}
	for reg in content.registries:
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
