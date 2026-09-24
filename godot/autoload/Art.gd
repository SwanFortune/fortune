## Autoload. Resolves an art asset id (e.g. "card/pour-the-tea") to a loaded
## Texture2D, or null when the artist hasn't delivered that piece yet — every
## caller is expected to fall back to a procedural placeholder on null, so the
## game stays fully playable with zero art present and improves piece by
## piece as art lands. Nothing here ever blocks or errors on missing art.
##
## Art lives at assets/art/<kind>/<slug>.png by convention (the manifest's own
## asset id IS that path, minus extension). A manifest entry may override that
## with an explicit "file" path for anything stored non-standardly.
##
## See docs/ART_GUIDE.md — that's the artist-facing half of this.
extends Node

const MANIFEST_PATH := "res://data/base/art_manifest.json"
const ART_ROOT := "res://assets/art/"

var manifest: Dictionary = {}
var spec: Dictionary = {}

# id -> Texture2D (or null when known-absent). Caches negative lookups too, so
# a missing piece costs one filesystem check per session, not one per frame.
var _cache: Dictionary = {}


func _ready() -> void:
	# Re-sync whenever content is rebuilt; see Content.reloaded.
	Content.reloaded.connect(reload)
	reload()


func reload() -> void:
	_cache.clear()
	manifest = {}
	spec = {}
	if not FileAccess.file_exists(MANIFEST_PATH):
		return
	var f := FileAccess.open(MANIFEST_PATH, FileAccess.READ)
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("[Art] %s did not parse as an object; running with no art." % MANIFEST_PATH)
		return
	manifest = parsed.get("assets", {})
	spec = parsed.get("spec", {})
	_say_what_does_not_resolve()


## AN ASSET THE MANIFEST CALLS DELIVERED AND NOTHING CAN LOAD IS WORTH ONE LINE.
##
## Silent today: all seventy-nine are `missing`, which is not a problem, it is
## the state of the project. It says nothing until somebody claims otherwise —
## and then it says it in the build where it matters, because tests/run_all.sh
## and tests/smoke_export.sh both fail on an unexpected warning.
##
## This is here because the same bug in Audio shipped: the exported build could
## not see any of its .wav files and every cue was silent, and the only reason
## it was caught before release rather than after is that somebody listed what
## the binary actually contains. Art has the identical shape and no symptom yet,
## because nothing has been drawn.
func _say_what_does_not_resolve() -> void:
	var blank: Array[String] = []
	for id in manifest:
		if str(manifest[id].get("status", UNDELIVERED)) == UNDELIVERED:
			continue
		if texture(str(id)) == null:
			blank.append(str(id))
	if not blank.is_empty():
		push_warning("[Art] %d asset(s) are marked delivered and load nothing: %s"
			% [blank.size(), ", ".join(blank)])


## "Pour The Tea" -> "pour-the-tea". Must match gen_art_manifest.gd's _slug()
## exactly, or ids generated there won't resolve here.
func slug(s: String) -> String:
	var out := s.to_lower()
	var from := ["é", "è", "ê", "ë", "à", "â", "ä", "î", "ï", "ô", "ö", "ù", "û", "ü", "ç", "’", "'"]
	var to := ["e", "e", "e", "e", "a", "a", "a", "i", "i", "o", "o", "u", "u", "u", "c", "", ""]
	for i in from.size():
		out = out.replace(from[i], to[i])
	var result := ""
	for ch in out:
		if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9"):
			result += ch
		elif result.length() > 0 and not result.ends_with("-"):
			result += "-"
	return result.trim_suffix("-")


func card_id(card: Dictionary) -> String:
	return "card/" + slug(card.get("n", ""))


func sitter_id(sitter: Dictionary) -> String:
	return "sitter/" + slug(sitter.get("name", ""))


func reader_id(reader: Dictionary) -> String:
	return "reader/" + slug(reader.get("k", ""))


## The texture for an asset id, or null if there isn't one yet. Callers draw
## their placeholder on null rather than treating it as an error.
func texture(id: String) -> Texture2D:
	if _cache.has(id):
		return _cache[id]
	var tex: Texture2D = null
	var entry: Dictionary = manifest.get(id, {})
	# An explicit "file" wins; otherwise the id itself is the path.
	var path: String = entry.get("file", "")
	if path == "":
		path = ART_ROOT + id + ".png"
	# A "missing" status is the artist's own signal that nothing is delivered
	# yet — trust it and skip the disk check entirely. Any other status still
	# gets verified against the filesystem, so a status of "final" with no
	# file present degrades to the placeholder rather than erroring.
	if entry.get("status", "missing") != "missing":
		tex = animated(entry, path)
		if tex == null:
			tex = _load_texture(path)
	_cache[id] = tex
	return tex


## A DRAWING THAT MOVES. Two ways to deliver one, because animation tools export
## one or the other and an animator should not have to convert:
##
##   a SPRITE SHEET — the ordinary <slug>.png, holding a grid of frames, with
##     "frames": [columns, rows] in the manifest entry (and "count" if the last
##     row is not full). Every frame is the size the spec asks for.
##   a FOLDER OF FRAMES — assets/art/<kind>/<slug>/ holding 0001.png, 0002.png…
##     in the order their names sort. What Krita, Procreate and Aseprite export
##     when asked for "frames as images". No manifest field needed.
##
## "fps" (default 12) sets the speed, "loop": false plays it once and holds the
## last frame. What comes back is an AnimatedTexture, which IS a Texture2D, so
## every card face and portrait slot in the game animates without being told:
## nothing that displays art knows or cares that this one moves.
##
## Null when the entry is not animated, and the caller loads the still.
func animated(entry: Dictionary, path: String) -> Texture2D:
	var frames: Array[Texture2D] = []
	for f in frame_files(path.get_basename()):
		var t := _load_texture(f)
		if t != null:
			frames.append(t)
	var grid = entry.get("frames")
	if frames.is_empty() and grid is Array and grid.size() == 2:
		var sheet := _load_texture(path)
		if sheet != null:
			frames = _slice(sheet, int(grid[0]), int(grid[1]), int(entry.get("count", 0)))
	if frames.size() < 2:
		return null
	var anim := AnimatedTexture.new()
	anim.frames = mini(frames.size(), AnimatedTexture.MAX_FRAMES)
	var each := 1.0 / maxf(float(entry.get("fps", DEFAULT_FPS)), 0.1)
	for i in anim.frames:
		anim.set_frame_texture(i, frames[i])
		anim.set_frame_duration(i, each)
	anim.one_shot = not bool(entry.get("loop", true))
	return anim


const DEFAULT_FPS := 12.0


## The frames in a folder, in name order. Asked two ways and merged: in an
## exported build the pack lists `0001.png.import`/`.remap` rather than the PNG
## (ResourceLoader.list_directory() puts the names back), and a folder dropped
## in after the last editor import, or in user://mods, has plain PNGs only.
func frame_files(folder: String) -> Array[String]:
	var names := {}
	if DirAccess.dir_exists_absolute(folder):
		for n in DirAccess.get_files_at(folder):
			names[n.trim_suffix(".import").trim_suffix(".remap")] = true
	if folder.begins_with("res://"):
		for n in ResourceLoader.list_directory(folder):
			names[n] = true
	var out: Array[String] = []
	for n in names:
		if str(n).to_lower().ends_with(".png"):
			out.append(folder.path_join(n))
	out.sort_custom(func(a, b): return a.naturalnocasecmp_to(b) < 0)
	return out


func _slice(sheet: Texture2D, cols: int, rows: int, count: int) -> Array[Texture2D]:
	var out: Array[Texture2D] = []
	if cols < 1 or rows < 1:
		return out
	var w := sheet.get_width() / cols
	var h := sheet.get_height() / rows
	var n := cols * rows if count <= 0 else mini(count, cols * rows)
	for i in n:
		var a := AtlasTexture.new()
		a.atlas = sheet
		a.region = Rect2(float((i % cols) * w), float((i / cols) * h), float(w), float(h))
		out.append(a)
	return out


## Decodes an image from BYTES rather than going through load().
##
## load() only resolves assets the editor has imported — it needs the .import
## file and the converted resource under .godot/imported/. Art delivered after
## the fact and dropped straight into assets/art/ has none of that, and art a
## MOD ships in user://mods/ never can: the import pipeline only covers res://
## assets known at export time. So the original ResourceLoader.exists() + load()
## pair worked only for art that had been through the editor, which is the one
## case that was never going to be the interesting one. This path works for
## both, and is why "drop the PNG in and it appears" is actually true.
## THE SAME TWO STEPS AS Audio._load_stream(), for the same reason and against a
## bug that has not happened yet. An export does not carry the .png either — the
## importer converts it to a .ctex and the original is not in the pack — so the
## day the illustrator's first drawing lands, FileAccess.file_exists() is false
## in the shipped build and every card falls back to its placeholder. In the
## source tree it would look perfect. That is the audio bug exactly, and the
## only reason it was found there first is that the audio already exists.
func _load_texture(path: String) -> Texture2D:
	if not FileAccess.file_exists(path):
		if not ResourceLoader.exists(path):
			return null
		var res = ResourceLoader.load(path)
		return res if res is Texture2D else null
	var img := Image.new()
	if img.load(path) != OK or img.is_empty():
		push_warning("[Art] %s could not be read as an image." % path)
		return null
	return ImageTexture.create_from_image(img)


func card_texture(card: Dictionary) -> Texture2D:
	return texture(card_id(card))


func sitter_texture(sitter: Dictionary) -> Texture2D:
	return texture(sitter_id(sitter))


func reader_texture(reader: Dictionary) -> Texture2D:
	return texture(reader_id(reader))


## What a laid card becomes in the room — see data/base/room.json and
## scenes/RoomTraces.gd, which draws its placeholder when this is null.
func prop_texture(prop_id: String) -> Texture2D:
	return texture("prop/" + slug(prop_id))


## The status that means NOBODY HAS DRAWN THIS YET, and the answer assumed for an
## entry that does not say. Named rather than spelt "missing" at each call site
## because the credits count against it; see Audio.UNDELIVERED, which is the same
## idea with a different word (art starts absent, sound starts as a stand-in).
const UNDELIVERED := "missing"


## Counts by status, for a quick "how much art is done" readout.
func status_summary() -> Dictionary:
	var out := {}
	for id in manifest:
		var st: String = manifest[id].get("status", UNDELIVERED)
		out[st] = int(out.get(st, 0)) + 1
	return out
