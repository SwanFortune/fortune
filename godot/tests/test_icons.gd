## Headless test for the vector icon system.
##   godot --headless --path godot -s tests/test_icons.gd
##
## The icons are the prototype's own line art (EL_ART, SIGN_ART, PLANET_ART in
## Parlour v23.dc.html), carried over as path data and rasterised at runtime by
## autoload/Icons.gd. Two things about that arrangement need watching.
##
## First, THE PATHS ARE DATA THIS PROJECT DOES NOT PARSE. They go straight to
## Godot's SVG renderer, so a typo in one is not a syntax error anywhere — it is
## an icon that comes back blank, or a stroke that quietly renders as nothing.
## That is exactly what happened while this was being written: Color.to_html()
## returns bare hex digits, SVG needs a leading "#", and an invalid colour is
## not an error in SVG — every badge came out as an empty tinted square. So the
## test rasterises every icon and counts the pixels that actually got drawn.
##
## Second, the base content has to be COMPLETE. A mod adding a sign without art
## is fine — the badge falls back — but a base sign with no icon is a hole in
## the game's own look that nothing else would report.
##
## Autoloads are fetched via get_node() — see the note at the top of
## tests/test_rules.gd for why the bare global names don't resolve here.
extends SceneTree

const TESTS := [
	"_test_every_icon_actually_draws",
	"_test_the_base_content_is_fully_illustrated",
	"_test_an_unknown_icon_is_null_rather_than_blank",
	"_test_colour_reaches_the_drawing",
	"_test_icons_are_cached",
]

var failures: Array[String] = []
var finished: Dictionary = {}
var content: Node
var icons: Node


func _initialize() -> void:
	content = root.get_node("Content")
	icons = root.get_node("Icons")
	await process_frame
	content.reload()

	for t in TESTS:
		call(t)
		if not finished.has(t):
			failures.append("%s aborted before finishing — see the SCRIPT ERROR above" % t)

	if failures.is_empty():
		print("ALL PASS — %d test methods" % TESTS.size())
		quit(0)
	else:
		for f in failures:
			printerr("FAIL: ", f)
		quit(1)


func check(cond: bool, label: String) -> void:
	if not cond:
		failures.append(label)


func done(name: String) -> void:
	finished[name] = true


## How many pixels an icon actually puts on the canvas. A blank result is the
## failure mode this whole file exists for: it is what a bad path, a bad
## colour, or a renderer that quietly refused all look like.
func _ink(tex: Texture2D) -> int:
	if tex == null:
		return 0
	var img := tex.get_image()
	var n := 0
	for y in img.get_height():
		for x in img.get_width():
			if img.get_pixel(x, y).a > 0.05:
				n += 1
	return n


func _test_every_icon_actually_draws() -> void:
	var total := 0
	for kind in content.icons:
		for name in content.icons[kind]:
			total += 1
			var tex: Texture2D = icons.texture(str(kind), str(name), 32, Color(0.83, 0.69, 0.22))
			check(tex != null, "%s/%s did not rasterise at all" % [kind, name])
			# 20 is a floor, not a target: the thinnest of these (a single
			# stroked line) still covers far more than that at 32px, and a blank
			# or nearly-blank result is what a broken path looks like.
			check(_ink(tex) > 20, "%s/%s rendered blank or nearly so (%d pixels)" % [kind, name, _ink(tex)])
	check(total >= 28, "the base pack should carry the source's whole icon set, found %d" % total)
	done("_test_every_icon_actually_draws")


## Every element, every sign and every reader's planet in the BASE content has
## a drawing. A mod adding one without art degrades gracefully; the game's own
## content having a hole would just look unfinished, and nothing else looks.
func _test_the_base_content_is_fully_illustrated() -> void:
	for el in content.ring:
		check(icons.has("element", str(el)), "element '%s' has no icon" % el)
	for sg in content.signs:
		var key := str(sg.get("k", ""))
		if str(sg.get("_pack", "")) == "parlour.base":
			check(icons.has("sign", key), "base sign '%s' has no icon" % key)
	for r in content.readers:
		if str(r.get("_pack", "")) != "parlour.base":
			continue
		check(icons.has("sign", str(r.get("k", ""))), "base reader '%s' has no sign icon" % r.get("k"))
		var planet := str(r.get("planet", ""))
		if planet != "":
			check(icons.has("planet", planet), "planet '%s' (%s) has no icon" % [planet, r.get("k")])
	done("_test_the_base_content_is_fully_illustrated")


## The contract every caller relies on: no icon means null, so the UI can fall
## back to the text glyph rather than leaving a hole where a badge should be.
func _test_an_unknown_icon_is_null_rather_than_blank() -> void:
	check(icons.texture("element", "no_such_element", 32, Color.WHITE) == null,
		"an unknown name should be null")
	check(icons.texture("no_such_kind", "fire", 32, Color.WHITE) == null,
		"an unknown kind should be null")
	check(not icons.has("sign", "no_such_sign"), "has() should agree")
	# A zero or negative size is a caller bug, not a reason to crash.
	check(icons.texture("element", "fire", 0, Color.WHITE) == null, "a zero size should be null")
	done("_test_an_unknown_icon_is_null_rather_than_blank")


## The colour has to reach the drawing. It did not, for a while: SVG treats an
## unprefixed hex value as invalid and renders the stroke as NOTHING rather
## than erroring, so every badge was an empty tinted square and the first probe
## missed it by hardcoding a "#"-prefixed literal.
func _test_colour_reaches_the_drawing() -> void:
	var red: Texture2D = icons.texture("element", "fire", 32, Color(1, 0, 0))
	check(red != null and _ink(red) > 20, "a red icon should draw")
	if red == null:
		done("_test_colour_reaches_the_drawing")
		return
	var img := red.get_image()
	var found_red := false
	for y in img.get_height():
		for x in img.get_width():
			var px := img.get_pixel(x, y)
			if px.a > 0.5 and px.r > 0.5 and px.g < 0.3 and px.b < 0.3:
				found_red = true
	check(found_red, "the requested colour should appear in the drawing")
	done("_test_colour_reaches_the_drawing")


## Rasterising an SVG is not free and a card face asks for the same badge many
## times a screen, so the same request must come back as the same texture.
func _test_icons_are_cached() -> void:
	var a: Texture2D = icons.texture("element", "water", 24, Color.WHITE)
	var b: Texture2D = icons.texture("element", "water", 24, Color.WHITE)
	check(a != null and a == b, "the same request should return the cached texture")
	var c: Texture2D = icons.texture("element", "water", 24, Color.RED)
	check(c != null and c != a, "a different colour is a different texture")
	# ...and a content reload drops the cache, so a mod's replacement is seen.
	icons.reload()
	var d: Texture2D = icons.texture("element", "water", 24, Color.WHITE)
	check(d != null and d != a, "reload() should have dropped the cache")
	done("_test_icons_are_cached")
