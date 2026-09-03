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

## Written first, then renamed over PATH. See _write().
const TMP_PATH := "user://save.dat.tmp"

## The previous good save, kept so a corrupt or truncated one is survivable.
## See _read() and restore().
const BACKUP_PATH := "user://save.dat.bak"

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

## True when the LAST attempt to write the run failed, and stays true until one
## succeeds. Read by RunHeader, which puts a line on screen.
##
## Separate from last_error, which also carries READ failures — a save that
## could not be loaded at startup is a different message, shown in a different
## place, and mixing them meant a stale one from launch could appear mid-run.
##
## This exists because the failure was completely silent. A disk that is full,
## or a save directory that is read-only, made every write fail; last_error was
## set, a warning went to the console, and the player — who is in the middle of
## a run and nowhere near a console — was told nothing at all. They finished
## three nights, closed the game, and the run was simply gone, with no
## CONTINUE on the menu and no explanation ever, because last_error does not
## survive a relaunch either.
var write_failed := false

## True when the last read fell back to the backup because the current save
## could not be read. The main menu says so: a player who has silently lost an
## action or two should hear about it rather than wonder later.
var restored_from_backup := false

var _dirty := false


func _ready() -> void:
	var run := get_node_or_null("/root/Run")
	if run != null:
		run.state_changed.connect(_on_state_changed)
	Content.reloaded.connect(_on_content_reloaded)


## Content just changed under a run that is already in progress.
##
## `Run.state` is full of COPIES of content records — every card in the deck,
## the reader, the sitter's sign. Reloading the registries does not touch those
## copies, so without this a card retuned in the Library or by a mod pack keeps
## its old numbers for the rest of the run, and the edit appears to do nothing.
##
## The re-resolution already exists, in restore(): write the run out and read it
## back, which is exactly the path a restart would take. Flush first so anything
## the dirty flag has not yet committed is not rolled back by the read.
func _on_content_reloaded() -> void:
	var run := get_node_or_null("/root/Run")
	if run == null or run.state.is_empty() or str(run.state.get("screen", "")) in NOT_A_RUN:
		return
	_dirty = false
	_write()
	restore()


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


## Removes the save AND its backup and temp file. Clearing only the main one
## would leave a stale backup that a later corrupt read could resurrect —
## dropping the player into a run they had already finished or abandoned.
func clear() -> void:
	_dirty = false
	for path in [PATH, BACKUP_PATH, TMP_PATH]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


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
	# WRITTEN TO A TEMPORARY FILE AND THEN RENAMED. Writing straight to PATH
	# means the save is, for the length of the write, a half-written file — and
	# a crash or a power cut in that window leaves the player with a truncated
	# save and no run. The window is small and this game writes several times a
	# minute; small and often is exactly how that lottery gets won.
	#
	# A rename within the same directory is atomic on every filesystem this
	# ships to, so the save on disk is only ever the old one or the new one.
	var f := FileAccess.open(TMP_PATH, FileAccess.WRITE)
	if f == null:
		last_error = "could not open %s for writing (%s)" % [TMP_PATH, error_string(FileAccess.get_open_error())]
		write_failed = true
		push_warning("[Save] " + last_error)
		return
	f.store_var({
		"version": VERSION,
		"saved_at": int(Time.get_unix_time_from_system()),
		"state": st,
	}, false)
	f.close()

	# The previous save becomes the backup before the new one takes its place,
	# so there is always one known-good file behind the current one. Losing a
	# run to a bad write is bad; losing it with a perfectly good save from ten
	# seconds ago sitting there unused would be worse.
	var dir := DirAccess.open("user://")
	if dir == null:
		last_error = "could not open user:// to place the save"
		write_failed = true
		push_warning("[Save] " + last_error)
		return
	if FileAccess.file_exists(PATH):
		dir.remove(BACKUP_PATH.get_file())
		dir.rename(PATH.get_file(), BACKUP_PATH.get_file())
	var err := dir.rename(TMP_PATH.get_file(), PATH.get_file())
	if err != OK:
		last_error = "could not put the save in place (%s)" % error_string(err)
		write_failed = true
		push_warning("[Save] " + last_error)
		return
	write_failed = false


## The current save, or the backup if the current one cannot be read.
##
## Falling back is the point of keeping a backup at all: refusing a corrupt save
## while a perfectly good one from ten seconds earlier sits beside it unused
## would be a worse answer than losing one action. `restored_from_backup` says
## which was used, so the player can be told they lost a little rather than
## being silently moved back in time.
##
## A VERSION MISMATCH IS NOT A CORRUPTION and does not fall back: a save from a
## newer build means this one cannot read it, and its backup will be from the
## same newer build. Trying it would only produce the same refusal twice.
func _read() -> Dictionary:
	last_error = ""
	restored_from_backup = false
	var doc := _read_file(PATH)
	if not doc.is_empty() or last_error == "" or last_error.begins_with("save is version"):
		return doc

	var main_error := last_error
	var backup := _read_file(BACKUP_PATH)
	if backup.is_empty():
		last_error = main_error   # the backup is no better; report the real one
		return {}
	restored_from_backup = true
	last_error = ""
	push_warning("[Save] the save was unreadable (%s); using the backup." % main_error)
	return backup


func _read_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		last_error = "could not open %s (%s)" % [path, error_string(FileAccess.get_open_error())]
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
