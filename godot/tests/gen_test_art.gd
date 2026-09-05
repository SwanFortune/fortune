## Dev-only throwaway: writes obviously-fake gradient PNGs at the real spec
## sizes and flips their manifest status to "final", purely to prove the art
## pipeline (manifest -> Art.gd -> UIKit) renders delivered art rather than
## the placeholder. These are NOT art; delete them once real pieces land:
##   rm godot/assets/art/card/pour-the-tea.png godot/assets/art/sitter/mme-perrot.png \
##      godot/assets/art/reader/taurus.png
## then set both statuses back to "missing".
##   godot --headless --path godot -s tests/gen_test_art.gd
extends SceneTree

const MANIFEST := "res://data/base/art_manifest.json"


func _initialize() -> void:
	_write("res://assets/art/card/pour-the-tea.png", 768, 576, Color(0.24, 0.55, 0.9))
	_write("res://assets/art/sitter/mme-perrot.png", 768, 1024, Color(0.78, 0.59, 0.35))
	# A reader too: three kinds are commissioned, and the third had no screen
	# showing it at all until the sign list grew one.
	_write("res://assets/art/reader/taurus.png", 768, 1024, Color(0.55, 0.75, 0.45))
	_mark(["card/pour-the-tea", "sitter/mme-perrot", "reader/taurus"])
	print("test art written + marked final")
	quit(0)


func _write(path: String, w: int, h: int, tint: Color) -> void:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			var t := float(x + y) / float(w + h)
			img.set_pixel(x, y, Color(tint.r * t + 0.16, tint.g * t + 0.12, tint.b * t + 0.2, 1.0))
	# A dark band across the lower third, mimicking where a real card's scrim
	# sits, so the screenshot makes it obvious which region the name overlays.
	for y in range(int(h * 0.62), h):
		for x in w:
			var c := img.get_pixel(x, y)
			img.set_pixel(x, y, c.darkened(0.35))
	img.save_png(ProjectSettings.globalize_path(path))
	print("  wrote ", path, " ", w, "x", h)


func _mark(ids: Array) -> void:
	var f := FileAccess.open(MANIFEST, FileAccess.READ)
	var doc: Dictionary = JSON.parse_string(f.get_as_text())
	f.close()
	for id in ids:
		if doc["assets"].has(id):
			doc["assets"][id]["status"] = "final"
			doc["assets"][id]["notes"] = "TEMP pipeline-test gradient, not real art — see tests/gen_test_art.gd"
	var w := FileAccess.open(MANIFEST, FileAccess.WRITE)
	w.store_string(JSON.stringify(doc, "  ") + "\n")
	w.close()
