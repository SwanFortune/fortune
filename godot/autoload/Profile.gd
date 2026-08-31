## Autoload. What persists BETWEEN runs, as opposed to Save.gd's single run in
## progress. Small on purpose: a handful of totals at user://profile.cfg.
##
## It exists to make one thing real. Every reader in readers.json carries an
## `unlock` field, ported faithfully from the prototype — and nothing read it,
## so all thirteen were available from the first launch and the field was
## decoration. It is now a condition this evaluates.
##
## NO PROGRESSION IS INVENTED FOR THE BASE GAME. Every base reader still has
## `unlock: null` and is available immediately, exactly as before; what changed
## is that the mechanism works, is tested, and is moddable — a pack can lock a
## reader behind a condition, and the example pack does, so the feature is
## exercised rather than merely present. Whether any BASE reader should be
## locked is a design decision for the game's author, not a porting one. (The
## obvious candidate, if ever: Serpentarius, the thirteenth sign, "You were
## never on the wheel.")
##
## Stats are recorded by watching Run.state_changed for the transitions that
## matter, the same way Save.gd works, so Run.gd stays free of persistence.
extends Node

const PATH := "user://profile.cfg"
const SECTION := "profile"

## stat key -> default. Also the list of what an `unlock` condition may name;
## a condition on anything else is reported rather than silently never met.
const STATS := {
	"runs_finished": 0,
	"best_faith": 0,
	"total_mended": 0,
	# Reader keys that have finished at least one run. Stored as an Array
	# because ConfigFile has no set type; treated as one.
	"readers_finished": [],
}

var _values: Dictionary = {}

## The screen we last saw, so a transition can be told from a redraw —
## state_changed fires on every action, not only when the screen changes.
var _last_screen := ""


func _ready() -> void:
	load_from_disk()
	var run := get_node_or_null("/root/Run")
	if run != null:
		run.state_changed.connect(_on_state_changed)


func get_stat(key: String):
	if not STATS.has(key):
		push_error("[Profile] unknown stat '%s'" % key)
		return null
	var value = _values.get(key, STATS[key])
	# Same reason as Settings.get_value(): the defaults live in a `const`, so
	# handing out the Array itself would let a caller corrupt it for good.
	return value.duplicate() if typeof(value) == TYPE_ARRAY else value


func set_stat(key: String, value) -> void:
	if not STATS.has(key):
		push_error("[Profile] unknown stat '%s'" % key)
		return
	_values[key] = value
	save_to_disk()


func reset() -> void:
	_values.clear()
	save_to_disk()


# ── recording ───────────────────────────────────────────────────────────

func _on_state_changed() -> void:
	var run := get_node_or_null("/root/Run")
	if run == null:
		return
	var st: Dictionary = run.state
	var screen := str(st.get("screen", ""))
	if screen == _last_screen:
		return
	var was := _last_screen
	_last_screen = screen

	# "over" is the end of a run, win or lose, and it is the only transition
	# recorded. A "runs_started" stat was tried and dropped: there is no
	# unambiguous screen transition for it (the first one after boot comes from
	# a blank _last_screen, and a resumed run produces the same shape as a new
	# one), it would have needed persistence calls inside Run.gd to be honest,
	# and no unlock condition wanted it. Reaching "over" needs none of that.
	if screen == "over" and was != "over":
		_record_finished_run(st)


func _record_finished_run(st: Dictionary) -> void:
	set_stat("runs_finished", int(get_stat("runs_finished")) + 1)
	set_stat("best_faith", maxi(int(get_stat("best_faith")), int(st.get("faith", 0))))
	set_stat("total_mended", int(get_stat("total_mended")) + int(st.get("mended", 0)))
	var key := str(st.get("reader", {}).get("k", ""))
	if key != "":
		var done: Array = get_stat("readers_finished")
		if not done.has(key):
			done.append(key)
			set_stat("readers_finished", done)


# ── unlocks ─────────────────────────────────────────────────────────────

## Whether `unlock` is satisfied. `null`, absent, or an empty dict all mean
## "no condition", which is what every base reader carries.
##
## A condition is `{"stat": <name>, "at_least": <n>}` for the numeric stats, or
## `{"stat": "readers_finished", "includes": <reader key>}` for the list. Kept
## deliberately small: a general expression language would be more than any
## mod has asked for, and this shape is checkable — an unknown stat name is a
## reported mistake rather than a condition that can never be met.
func meets(unlock) -> bool:
	if unlock == null or typeof(unlock) != TYPE_DICTIONARY or unlock.is_empty():
		return true
	var key := str(unlock.get("stat", ""))
	if not STATS.has(key):
		push_warning("[Profile] unlock names unknown stat '%s'; treating as unlocked." % key)
		return true
	var value = get_stat(key)
	if unlock.has("includes"):
		return typeof(value) == TYPE_ARRAY and value.has(unlock["includes"])
	if unlock.has("at_least"):
		return int(value) >= int(unlock["at_least"])
	push_warning("[Profile] unlock on '%s' has no at_least or includes; treating as unlocked." % key)
	return true


## What a player has to do, as a translated line. A pack may supply its own
## wording as `unlock.text`, which is always better than anything derived —
## it can say "win a run as the Crab" rather than naming a stat.
func unlock_text(unlock) -> String:
	if unlock == null or typeof(unlock) != TYPE_DICTIONARY or unlock.is_empty():
		return ""
	if str(unlock.get("text", "")) != "":
		return I18n.t(str(unlock["text"]))
	var key := str(unlock.get("stat", ""))
	if unlock.has("includes"):
		return I18n.t("Finish a run as %s") % str(unlock["includes"])
	return I18n.t("Reach %s of %s") % [unlock.get("at_least", 0), key]


func reader_locked(reader: Dictionary) -> bool:
	return not meets(reader.get("unlock", null))


# ── persistence ─────────────────────────────────────────────────────────

func load_from_disk() -> void:
	_values.clear()
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	for key in STATS:
		if cfg.has_section_key(SECTION, key):
			var raw = cfg.get_value(SECTION, key)
			if typeof(raw) == typeof(STATS[key]):
				_values[key] = raw


func save_to_disk() -> void:
	var cfg := ConfigFile.new()
	for key in STATS:
		if _values.has(key):
			cfg.set_value(SECTION, key, _values[key])
	cfg.save(PATH)
