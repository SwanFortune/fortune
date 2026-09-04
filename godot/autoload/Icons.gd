## Autoload. The prototype's own vector icons, rasterised at whatever size and
## colour is asked for.
##
## The line art for every element, sign, planet and card archetype comes from
## the source (EL_ART, SIGN_ART, PLANET_ART, ARCH in Parlour v23.dc.html). The
## △▽◇□ text glyphs are only the character fallback, and only where an icon is
## missing.
##
## The path data is in data/base/icons.json, verbatim. Nothing here interprets
## it: an icon is wrapped in a 24x24 SVG document and handed to
## Image.load_svg_from_string(), which is Godot's own renderer. That has three
## consequences worth having:
##
##   - the paths stay EXACTLY as authored, arcs and all. Parsing SVG path data
##     in GDScript would be a few hundred lines and a source of drift;
##   - an icon is rasterised at the pixel size it will be drawn at, so it is
##     crisp at any scale — including under text_scale and ui_scale, which is
##     where a fixed-size PNG would go soft;
##   - it needs no import step, so a mod can ship its own icons the same way it
##     ships art and audio. Icons ride the ordinary content pipeline.
##
## Cached by (name, size, colour): a card face asks for the same element badge
## a hundred times a screen, and rasterising an SVG is not free.
extends Node

## The source's own geometry, kept as constants because they are proportions
## rather than choices: a 24-unit viewBox, 1.7 stroke, and a badge whose icon
## is 68% of its box with a corner radius of 30% (elIcon/archIcon, ~line 1023).
const VIEWBOX := 24.0
const STROKE := 1.7
const ICON_FRACTION := 0.68
const RADIUS_FRACTION := 0.3
## Badge fill and border, as fractions of the icon's colour. The source writes
## these as color-mix percentages.
const BADGE_FILL_ALPHA := 0.24
const BADGE_BORDER_ALPHA := 0.52

var _cache: Dictionary = {}


func _ready() -> void:
	Content.reloaded.connect(reload)


## Drops the cache, so a mod repointing an icon takes effect at once. Wired to
## Content.reloaded like Art and Audio.
func reload() -> void:
	_cache.clear()


## True when `kind`/`name` names an icon that exists — callers fall back to the
## text glyph rather than drawing nothing.
func has(kind: String, name: String) -> bool:
	return not _art(kind, name).is_empty()


func _art(kind: String, name: String) -> Array:
	# Archetypes live in their own registry because they carry a colour and a
	# description alongside their art, which the icon tables do not. Reaching
	# them through the same texture() call keeps every caller identical.
	if kind == "archetype":
		return Array(Content.archetypes.get(name, {}).get("art", []))
	var table: Dictionary = Content.icons.get(kind, {})
	return Array(table.get(name, []))


## A texture of `kind`/`name` at `px` pixels square, stroked in `color`.
## Returns null when there is no such icon, which every caller treats as "use
## the text glyph" — the same contract Art.gd has for undelivered art.
func texture(kind: String, name: String, px: int, color: Color) -> Texture2D:
	var art := _art(kind, name)
	if art.is_empty() or px <= 0:
		return null
	var key := "%s/%s/%d/%s" % [kind, name, px, color.to_html()]
	if _cache.has(key):
		return _cache[key]

	var img := Image.new()
	# The scale argument is how the rasteriser gets its pixel size: the document
	# is 24 units wide, so scaling by px/24 gives exactly px pixels.
	var err := img.load_svg_from_string(_document(art, color), float(px) / VIEWBOX)
	if err != OK:
		push_warning("[Icons] %s/%s did not render (%s)" % [kind, name, error_string(err)])
		return null
	var tex := ImageTexture.create_from_image(img)
	_cache[key] = tex
	return tex


## Wraps the primitives in an SVG document. `currentColor` in the source's data
## (the filled dot at the centre of SUN and `pinpoint`) resolves against the
## document's own `color`, so it is set alongside `stroke`.
func _document(art: Array, color: Color) -> String:
	var body := ""
	for p in art:
		body += _element(p)
	# "#" IS REQUIRED. Color.to_html() returns bare hex digits, and SVG treats an
	# unprefixed value as an invalid colour — which does not error, it renders
	# the stroke as nothing. The badges came out as empty tinted squares and the
	# first probe missed it because it used a hardcoded "#d4b038".
	var hex := "#" + color.to_html(false)
	return ('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24"'
		+ ' fill="none" stroke="%s" color="%s" stroke-width="%s"' % [hex, hex, STROKE]
		+ ' stroke-linecap="round" stroke-linejoin="round">' + body + "</svg>")


func _element(p: Dictionary) -> String:
	var tag := str(p.get("tag", ""))
	if tag == "":
		return ""
	var attrs := ""
	for k in p:
		if k == "tag":
			continue
		attrs += ' %s="%s"' % [k, str(p[k])]
	return "<%s%s/>" % [tag, attrs]
