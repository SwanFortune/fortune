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
		tex = _load_texture(path)
	_cache[id] = tex
	return tex


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
