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
	if bad.is_empty():
		print("ALL PASS — no fx drift across %d readers, %d relics, %d marks, %d signs, %d jobs" % [
			content.readers.size(), content.relics.size(), content.marks.size(),
			content.signs.size(), content.jobs.size(),
		])
		quit(0)
	else:
		for line in bad:
			printerr("FAIL: ", line)
		quit(1)
