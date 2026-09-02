## Headless content audit — a port of the source's dev-only AUDIT tab
## (fxAudit()). Run after editing any data/base/*.json or mod pack:
##   godot --headless --path godot -s tests/test_content_audit.gd
## Exits 0 with "ALL PASS" if every fx reference is clean, exits 1 and lists
## every drift otherwise (unknown fx key, fx borrowed from the wrong
## category, or a needsEl fx missing its element).
extends SceneTree


func _initialize() -> void:
	var content: Node = root.get_node("Content")
	var rules: Node = root.get_node("Rules")
	content.reload()

	var bad: Array = rules.fx_audit()
	bad.append_array(_audit_number_types(content))
	if bad.is_empty():
		print("ALL PASS — no fx drift, no float-shaped whole numbers, across %d readers, %d relics, %d marks, %d signs, %d jobs" % [
			content.readers.size(), content.relics.size(), content.marks.size(),
			content.signs.size(), content.jobs.size(),
		])
		quit(0)
	else:
		for line in bad:
			printerr("FAIL: ", line)
		quit(1)


## Whole numbers in content must be ints, not floats.
##
## JSON has no integer type, so Godot parses `"cost": 1` as 1.0. The codebase
## treats these as ints throughout — int() in scoring, str() on a card face —
## and that appeared to work because Godot 4.3's str() renders an integral
## float as "1". Godot 4.7 renders it as "1.0", and every card in the game
## suddenly showed a cost of "1.0" and a restore of "+5.0".
##
## Nothing errored and no test failed: the bug had been latent since the first
## commit, hidden by a formatting detail of one engine version, and it took a
## screenshot under a different one to see it. ModLoader now converts whole
## numbers at load; this pins that down so it cannot regress, and so the check
## travels to whatever engine version anyone runs it on.
##
## Genuinely fractional values (an elite's maxMul, a sound's pitch_jitter) are
## expected to stay floats and are not flagged.
func _audit_number_types(content: Node) -> Array:
	var bad: Array = []
	for reg in content.registries:
		_walk_numbers(content.registries[reg], reg, bad)
		if bad.size() > 6:
			break
	return bad


func _walk_numbers(value, where: String, bad: Array) -> void:
	if bad.size() > 6:
		return
	match typeof(value):
		TYPE_FLOAT:
			if is_finite(value) and value == floor(value):
				bad.append("%s holds %s as a float — whole numbers must be ints or they render as \"%s\"" % [
					where, value, str(value)])
		TYPE_DICTIONARY:
			for k in value:
				_walk_numbers(value[k], "%s.%s" % [where, k], bad)
		TYPE_ARRAY:
			for i in value.size():
				_walk_numbers(value[i], "%s[%d]" % [where, i], bad)
