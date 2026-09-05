## Autoload. What persists BETWEEN runs, as opposed to Save.gd's single run in
## progress. Small on purpose: a handful of totals at user://profile.cfg.
##
## It is what makes readers.json's `unlock` field real rather than decoration.
##
## NO PROGRESSION IS INVENTED FOR THE BASE GAME: every base reader carries
## `unlock: null` and is available immediately. The mechanism works, is tested
## and is moddable — the example pack locks a reader, so it is exercised — but
## whether any BASE reader should be locked is the author's decision, not a
## porting one.
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
	# The hardest rung of the ladder finished, so the sign screen can open on it
	# rather than making somebody climb back up by hand every run. See
	# data/base/difficulty.json.
	"best_level": 0,
	# Minitel codes the player has dialled. An unlock condition can test this
	# with {stat: "codes_entered", includes: "OEIL"} — which is why the Minitel
	# needed no progression store of its own. See autoload/Minitel.gd.
	"codes_entered": [],

	# ── the tallies the records screen reads ─────────────────────────────
	# runs_finished above counts every run that ended; this counts the ones
	# that ended by reaching the end of the third night rather than by somebody
	# putting their coat back on.
	"runs_won": 0,
	# People, not runs: everyone who sat down and went home as they came.
	# total_mended above is the other half of the same count.
	"total_left": 0,

	# ── STREAKS ──────────────────────────────────────────────────────────
	# Three things can run, and each keeps what it is on and the best it has
	# ever been. They are ordinary stats, so an unlock condition can name one
	# ("finish three runs in a row") without any new machinery.
	#
	# READINGS: people got through to, one after another, ACROSS runs — a run
	# ending does not break it, somebody leaving does. That is the streak the
	# game is actually about.
	"streak_readings": 0, "best_streak_readings": 0,
	# RUNS: runs finished whole, one after another.
	"streak_runs": 0, "best_streak_runs": 0,
	# DAYS: calendar days in a row with at least one run finished on them.
	# `last_day` is the local date the last one was finished on, as YYYY-MM-DD,
	# which is what tells today from yesterday from a week off.
	"streak_days": 0, "best_streak_days": 0, "last_day": "",
}

## Why the last write to disk failed, or "" if it did not. Read by the main
## menu — see save_to_disk().
var last_error: String = ""

var _values: Dictionary = {}

## The screen we last saw, so a transition can be told from a redraw —
## state_changed fires on every action, not only when the screen changes.
var _last_screen := ""

## How many ledger entries this run has already been counted for. The ledger is
## how the per-READING streak is watched: it grows by one every time somebody
## gets up from the table, and it carries what became of them. Watching it means
## Run.gd needs to know nothing about any of this, which is the rule the rest of
## this file already follows.
var _counted := 0

## Which run those entries belong to. A ledger read at boot, or after a save is
## loaded, is FULL OF READINGS THAT WERE COUNTED WHEN THEY HAPPENED — without
## this, resuming a run would count every one of them again and hand out a
## streak nobody played. The seed is the run's identity (see Run._seed_from).
var _run_seed := ""


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
	if _put(key, value):
		save_to_disk()


## Sets without touching the disk, and says whether anything changed. Several
## stats move together on one event — a finished run moves six — and writing
## the file once per event rather than once per stat is the difference between
## one write and six.
func _put(key: String, value) -> bool:
	if not STATS.has(key):
		push_error("[Profile] unknown stat '%s'" % key)
		return false
	_values[key] = value
	return true


## Adds to a streak, or ends it. The best it ever reached is kept either way.
##
## `after_break` is what a broken one restarts at, and it is not always zero: a
## person who went home as they came does not count towards anything, but a DAY
## you played on counts even when it is the first day in a while. The day streak
## read 0 on the very first day of a profile until this had a name.
func _streak(name: String, on: bool, after_break: int = 0) -> void:
	var now := int(get_stat("streak_" + name)) + 1 if on else after_break
	_put("streak_" + name, now)
	_put("best_streak_" + name, maxi(int(get_stat("best_streak_" + name)), now))


func reset() -> void:
	_values.clear()
	save_to_disk()


# ── recording ───────────────────────────────────────────────────────────

func _on_state_changed() -> void:
	var run := get_node_or_null("/root/Run")
	if run == null:
		return
	var st: Dictionary = run.state
	_watch_the_ledger(st)
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


## Everyone who has got up from the table since the last time we looked. Runs
## on every state_changed, not only on a screen change, because nobody changes
## screen when a reading ends — the result panel is drawn over the same one.
func _watch_the_ledger(st: Dictionary) -> void:
	var ledger: Array = st.get("ledger", [])
	var seed := str(st.get("seed", ""))
	if seed != _run_seed:
		# A different run than the one we were watching — a new one, or one
		# resumed from disk. Whatever is already on its ledger happened before
		# we were looking and has been counted once already.
		_run_seed = seed
		_counted = ledger.size()
	elif ledger.size() < _counted:
		# The same seed played again from the start.
		_counted = ledger.size()
	if ledger.size() == _counted:
		return
	var moved := false
	while _counted < ledger.size():
		var entry = ledger[_counted]
		_counted += 1
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var mended: bool = str(entry.get("outcome", "")) == "mended"
		_streak("readings", mended)
		if not mended:
			_put("total_left", int(get_stat("total_left")) + 1)
		moved = true
	if moved:
		save_to_disk()


func _record_finished_run(st: Dictionary) -> void:
	_put("runs_finished", int(get_stat("runs_finished")) + 1)
	_put("best_faith", maxi(int(get_stat("best_faith")), int(st.get("faith", 0))))
	_put("total_mended", int(get_stat("total_mended")) + int(st.get("mended", 0)))
	_put("best_level", maxi(int(get_stat("best_level")), int(st.get("level", 0))))

	# A run ends one of two ways, and the ledger is what knows which: anybody
	# who went home as they came ends it there and then.
	var whole := true
	for entry in st.get("ledger", []):
		if typeof(entry) == TYPE_DICTIONARY and str(entry.get("outcome", "")) != "mended":
			whole = false
			break
	if whole:
		_put("runs_won", int(get_stat("runs_won")) + 1)
	_streak("runs", whole)
	_count_today()

	var key := str(st.get("reader", {}).get("k", ""))
	if key != "":
		var done: Array = get_stat("readers_finished")
		if not done.has(key):
			done.append(key)
			_put("readers_finished", done)
	save_to_disk()


## The day streak, which is the one that measures coming back rather than
## playing well. Today continues yesterday and repeats itself; anything else
## starts again at one.
##
## LOCAL dates, from the player's own clock, because "yesterday" is a thing that
## happens in a house, not in UTC. It also means the clock can be moved and the
## streak fooled, which is the correct trade for something with no reward
## attached to it.
func _count_today() -> void:
	var today := Time.get_date_string_from_system()
	var last := str(get_stat("last_day"))
	if last == today:
		return
	_streak("days", last == _the_day_before(today), 1)
	_put("last_day", today)


func _the_day_before(day: String) -> String:
	var parts := day.split("-")
	if parts.size() != 3:
		return ""
	var unix := Time.get_unix_time_from_datetime_dict({
		"year": int(parts[0]), "month": int(parts[1]), "day": int(parts[2]),
		"hour": 12, "minute": 0, "second": 0,
	})
	return Time.get_date_string_from_unix_time(int(unix) - 86400)


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
		# The derived wording has to match the stat, not just its shape. Both
		# list stats are `includes` conditions, and describing a Minitel code as
		# a reader to finish a run with would send the player somewhere the
		# condition can never be met.
		if key == "codes_entered":
			return I18n.t("Dial 3615 %s") % str(unlock["includes"])
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
	# The return value is not decoration: a read-only user:// or a full disk
	# fails here, and the main menu shows it once for whichever of the three
	# config writes failed. Silent, it costs an unlock.
	# Written to a temporary file and renamed into place, for the same reason
	# Save.gd does it: a crash partway through a write would otherwise leave a
	# truncated config, and a truncated config is one ConfigFile.load() refuses
	# — losing every unlock rather than the one being written.
	var tmp := PATH + ".tmp"
	var err := cfg.save(tmp)
	if err == OK:
		var dir := DirAccess.open("user://")
		err = dir.rename(tmp.get_file(), PATH.get_file()) if dir != null else FAILED
	if err != OK:
		last_error = "could not write %s (%s)" % [PATH, error_string(err)]
		push_warning("[Profile] " + last_error)
	else:
		last_error = ""
