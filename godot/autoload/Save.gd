## Autoload. Persists the run in progress so closing the game does not throw
## away three nights of it, and restores it on CONTINUE.
##
## WHY store_var AND NOT JSON. `Run.state` is a plain Dictionary, so JSON looks
## like the obvious choice, but JSON has no integer type: every `hp`, `coin` and
## `denial` would come back as a float, and the parts of the game that render a
## number with str() rather than int() would start showing "5.0". store_var
## round-trips Godot's own types exactly. `allow_objects` is false in both
## directions on purpose — a save file is a file on disk that can be edited or
## swapped, and object deserialization would let one execute code.
##
## WHAT IS AND IS NOT SAVED VERBATIM. The whole state dict is written as-is,
## rather than hand-mapped field by field, so a new field added to a run cannot
## be silently dropped by a serializer nobody remembered to update. But `state`
## is full of *copies* of content records — every card in the deck is a
## duplicate of a Content record, the reader and the sitter's sign likewise. If
## those copies were restored verbatim, an in-progress run would be frozen
## against the content as it stood when the run started: a card retuned in the
## Library, or a mod pack updated or removed, would not reach it, and a deck
## could go on containing cards that no longer exist anywhere. So on load every
## content-derived record is looked up again by its stable identity (a card by
## name, a reader/sign by key) and replaced with the current version, keeping
## only the per-run fields that are genuinely run state — a card's `uid`, a
## sitter's scaled `max`/`denial`/`turns` and elite `twist`.
##
## A card whose name no longer resolves is dropped rather than kept as a husk;
## `restore()` reports how many went, and the caller decides whether that is
## worth telling the player about.
extends Node

const PATH := "user://save.dat"

## Bumped when the shape of what is written changes incompatibly. A save from a
## future version, or from one whose shape this code can no longer read, is
## refused rather than half-restored into a run that then misbehaves.
const VERSION := 1

## Keys inside a fight dict that hold cards. `cross` is the line being spoken
## right now, so a save taken mid-reading resumes mid-reading.
const FIGHT_CARD_PILES := ["hand", "draw", "disc", "cross", "gone"]

## Screens that are not a run in progress: the sign-select screen is before one
## has started and "over" is after it has ended, so neither is worth resuming.
const NOT_A_RUN := ["sign", "over"]

var last_error: String = ""

var _dirty := false


func _ready() -> void:
	var run := get_node_or_null("/root/Run")
	if run != null:
		run.state_changed.connect(_on_state_changed)


func _process(_delta: float) -> void:
	# state_changed fires on every card laid, so writing straight from the
	# signal would hit the disk several times for one player action. Coalescing
	# through a dirty flag makes it at most once a frame, and in practice once
	# per action.
	if _dirty:
		_dirty = false
		_write()


## Quitting can happen between a state change and the next frame, which would
## lose the last action. Flush on the way out as well.
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_EXIT_TREE:
		if _dirty:
			_dirty = false
			_write()


func _on_state_changed() -> void:
	_dirty = true


func has_save() -> bool:
	return FileAccess.file_exists(PATH)


## Metadata about the save on disk without restoring it — enough for the main
## menu to say what CONTINUE would resume into. Empty if there is no readable
## save.
func peek() -> Dictionary:
	var doc := _read()
	if doc.is_empty():
		return {}
	var st: Dictionary = doc.get("state", {})
	return {
		"night": int(st.get("night", 0)) + 1,
		"step": int(st.get("step", 0)) + 1,
		"faith": int(st.get("faith", 0)),
		"reader": str(st.get("reader", {}).get("k", "")),
		"saved_at": int(doc.get("saved_at", 0)),
	}


func clear() -> void:
	_dirty = false
	if FileAccess.file_exists(PATH):
		DirAccess.remove_absolute(PATH)


## Loads the save into Run.state. Returns {ok, dropped, note} — `dropped` counts
## cards whose content no longer exists. On failure `ok` is false and
## `last_error` says why; Run.state is left untouched.
func restore() -> Dictionary:
	var doc := _read()
	if doc.is_empty():
		return {"ok": false, "dropped": 0}
	var st = doc.get("state", null)
	if typeof(st) != TYPE_DICTIONARY or st.is_empty():
		last_error = "save contains no run state"
		return {"ok": false, "dropped": 0}

	var dropped := _rehydrate(st)
	var run := get_node_or_null("/root/Run")
	if run == null:
		last_error = "Run autoload unavailable"
		return {"ok": false, "dropped": 0}
	run.state = st
	# Restoring is itself a state change, but writing it straight back out would
	# be a pointless round trip — and worse, would persist any content drop we
	# just made before the player has been told about it.
	_dirty = false
	return {"ok": true, "dropped": dropped}


# ── writing ─────────────────────────────────────────────────────────────

func _write() -> void:
	var run := get_node_or_null("/root/Run")
	if run == null:
		return
	var st: Dictionary = run.state
	if st.is_empty() or str(st.get("screen", "")) in NOT_A_RUN:
		# Not a run in progress. Clear rather than leave a stale save that
		# CONTINUE would drop the player back into.
		clear()
		return
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f == null:
		last_error = "could not open %s for writing (%s)" % [PATH, error_string(FileAccess.get_open_error())]
		push_warning("[Save] " + last_error)
		return
	f.store_var({
		"version": VERSION,
		"saved_at": int(Time.get_unix_time_from_system()),
		"state": st,
	}, false)
	f.close()


func _read() -> Dictionary:
	last_error = ""
	if not FileAccess.file_exists(PATH):
		return {}
	var f := FileAccess.open(PATH, FileAccess.READ)
	if f == null:
		last_error = "could not open %s (%s)" % [PATH, error_string(FileAccess.get_open_error())]
		return {}
	var doc = f.get_var(false)
	f.close()
	if typeof(doc) != TYPE_DICTIONARY:
		last_error = "save file is not readable — it may be from a different build"
		return {}
	var v := int(doc.get("version", 0))
	if v != VERSION:
		last_error = "save is version %d, this build reads version %d" % [v, VERSION]
		return {}
	return doc


# ── re-resolving content ────────────────────────────────────────────────

## Walks the restored state and swaps every content-derived copy for the live
## one. Returns the number of cards that could not be resolved and were dropped.
func _rehydrate(st: Dictionary) -> int:
	var dropped := 0

	var reader = _relive_reader(st.get("reader", {}))
	if reader != null:
		st["reader"] = reader

	var deck_before: Array = st.get("deck", [])
	st["deck"] = _relive_pile(deck_before)
	dropped += deck_before.size() - st["deck"].size()
	st["marks"] = _relive_marks(st.get("marks", []))

	var f = st.get("f", {})
	if typeof(f) == TYPE_DICTIONARY and not f.is_empty():
		for pile in FIGHT_CARD_PILES:
			var before: Array = f.get(pile, [])
			var after := _relive_pile(before)
			dropped += before.size() - after.size()
			f[pile] = after
		var sign = _relive_sign(f.get("quirk", {}))
		if sign != null:
			f["quirk"] = sign
		f["sitter"] = _relive_sitter(f.get("sitter", {}))
		f["job"] = Content.get_job(str(f.get("sitter", {}).get("role", "")))

	for o in st.get("options", []):
		if typeof(o) != TYPE_DICTIONARY:
			continue
		if o.has("quirk"):
			var q = _relive_sign(o["quirk"])
			if q != null:
				o["quirk"] = q
		if o.has("sitter"):
			o["sitter"] = _relive_sitter(o["sitter"])

	# The pick screen (reward / shop / event) holds card offers.
	var pick = st.get("pick", {})
	if typeof(pick) == TYPE_DICTIONARY:
		for opt in pick.get("opts", []):
			if typeof(opt) == TYPE_DICTIONARY and opt.has("card") and typeof(opt["card"]) == TYPE_DICTIONARY:
				var c = _relive_card(opt["card"])
				if c != null:
					opt["card"] = c

	return dropped


## A card, looked up by the one thing about it that is stable across content
## edits: its name. `uid` is per-run identity (two copies of the same card in a
## deck are distinguishable only by it) so it is carried over, not looked up.
func _relive_card(c) -> Variant:
	if typeof(c) != TYPE_DICTIONARY:
		return null
	var name := str(c.get("n", ""))
	if name == "" or not Content.has_card(name):
		return null
	var fresh: Dictionary = Content.get_card(name).duplicate(true)
	if c.has("uid"):
		fresh["uid"] = c["uid"]
	return fresh


func _relive_pile(pile) -> Array:
	var out: Array = []
	if typeof(pile) != TYPE_ARRAY:
		return out
	for c in pile:
		var live = _relive_card(c)
		if live != null:
			out.append(live)
	return out


func _relive_reader(r) -> Variant:
	if typeof(r) != TYPE_DICTIONARY:
		return null
	var live: Dictionary = Content.get_reader(str(r.get("k", "")))
	return live if not live.is_empty() else null


func _relive_sign(s) -> Variant:
	if typeof(s) != TYPE_DICTIONARY:
		return null
	var live: Dictionary = Content.get_sign(str(s.get("k", "")))
	return live if not live.is_empty() else null


## Marks and relics are addressed by name like cards. A mark from a pack that
## has since been removed is dropped rather than kept, since Rules.has() would
## otherwise keep granting an fx nothing can explain to the player.
func _relive_marks(marks) -> Array:
	var out: Array = []
	if typeof(marks) != TYPE_ARRAY:
		return out
	for m in marks:
		if typeof(m) != TYPE_DICTIONARY:
			continue
		var name := str(m.get("n", ""))
		var found := false
		for pool in [Content.marks, Content.relics]:
			for candidate in pool:
				if str(candidate.get("n", "")) == name:
					out.append(candidate)
					found = true
					break
			if found:
				break
	return out


## A sitter carries both content fields (name, role, element, dialogue) and
## fields the run computed (max/denial/turns scaled for the night, the elite
## twist). Take the content half live and keep the computed half.
func _relive_sitter(s) -> Dictionary:
	if typeof(s) != TYPE_DICTIONARY:
		return {}
	var live: Dictionary = Content.get_sitter(str(s.get("name", "")))
	if live.is_empty():
		return s
	var out: Dictionary = live.duplicate(true)
	for k in ["max", "denial", "turns", "elite", "twist", "shieldMul"]:
		if s.has(k):
			out[k] = s[k]
	return out
