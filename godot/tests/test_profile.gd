## Headless test for cross-run persistence and the reader unlock condition.
##   godot --headless --path godot -s tests/test_profile.gd
##
## The guarantees under test:
##   - the `unlock` field on a reader is actually evaluated. It was ported
##     faithfully from the prototype and then read by nothing at all, so every
##     reader was available regardless — the whole point of this file is that
##     the field is no longer decoration;
##   - NO BASE READER IS LOCKED. Making the mechanism work must not quietly
##     change the game's own progression, which is the author's call and not a
##     porting one;
##   - a run finishing is recorded once, not once per redraw of the end screen;
##   - a malformed or unknown condition is reported and treated as unlocked,
##     rather than locking a reader behind something unreachable.
extends SceneTree

const TESTS := [
	"_test_no_base_reader_is_locked",
	"_test_unlock_conditions",
	"_test_bad_conditions_do_not_lock",
	"_test_a_finished_run_is_recorded_once",
	"_test_stats_are_copied_out",
	"_test_the_streaks_count_and_break",
	"_test_the_day_streak",
]

var failures: Array[String] = []
var finished: Dictionary = {}
var content: Node
var run: Node
var profile: Node


func _initialize() -> void:
	content = root.get_node("Content")
	run = root.get_node("Run")
	profile = root.get_node("Profile")
	await process_frame
	content.reload()

	for t in TESTS:
		profile.reset()
		call(t)
		if not finished.has(t):
			failures.append("%s aborted before finishing — see the SCRIPT ERROR above" % t)
	profile.reset()

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


## The base game's own progression is unchanged: thirteen readers, all
## available from a fresh profile, exactly as before the field did anything.
func _test_no_base_reader_is_locked() -> void:
	for key in ["aries", "taurus", "gemini", "cancer", "leo", "virgo", "libra",
			"scorpio", "sagittarius", "capricorn", "aquarius", "pisces", "serpentarius"]:
		var r: Dictionary = content.get_reader(key)
		check(not r.is_empty(), "base reader '%s' should exist" % key)
		check(not profile.reader_locked(r),
			"base reader '%s' must not be locked — that would be inventing progression" % key)
	done("_test_no_base_reader_is_locked")


## The mechanism itself, including the example pack's demonstration of it —
## a condition that is not met keeps a reader locked, and meeting it opens it.
func _test_unlock_conditions() -> void:
	var lantern: Dictionary = content.get_reader("example_lantern")
	check(not lantern.is_empty(), "the example pack should contribute a locked reader")
	check(profile.reader_locked(lantern), "it should be locked on a fresh profile")

	profile.set_stat("runs_finished", 2)
	check(not profile.reader_locked(lantern), "two finished runs should open it")

	# The list-valued condition shape.
	var by_reader := {"stat": "readers_finished", "includes": "cancer"}
	check(not profile.meets(by_reader), "'includes' should not match an empty list")
	profile.set_stat("readers_finished", ["cancer"])
	check(profile.meets(by_reader), "'includes' should match once the key is present")

	check(profile.meets(null), "a null unlock means no condition")
	check(profile.meets({}), "an empty unlock means no condition")
	check(profile.unlock_text(null) == "", "no condition should produce no line")
	check(profile.unlock_text(lantern["unlock"]) != "", "a condition should tell the player what it wants")
	done("_test_unlock_conditions")


## A typo in a pack must not produce a reader nobody can ever select.
func _test_bad_conditions_do_not_lock() -> void:
	print("--- the next two warnings are expected: deliberately malformed unlock conditions ---")
	check(profile.meets({"stat": "no_such_stat", "at_least": 1}),
		"an unknown stat should be treated as unlocked, not as unreachable")
	check(profile.meets({"stat": "runs_finished"}),
		"a condition with no comparison should be treated as unlocked")
	done("_test_bad_conditions_do_not_lock")


## The end-of-run screen redraws several times. Recording on every redraw would
## inflate every total, and unlock conditions are counted against those totals.
func _test_a_finished_run_is_recorded_once() -> void:
	run.state = run.fresh()
	run.pick_reader(0)
	run.take_pick(0)

	run.state["faith"] = 123
	run.state["mended"] = 4
	run.end_run("done")
	run.state_changed.emit()   # a redraw of the same screen
	run.state_changed.emit()

	check(int(profile.get_stat("runs_finished")) == 1,
		"a finished run should count once, got %s" % profile.get_stat("runs_finished"))
	check(int(profile.get_stat("best_faith")) == 123,
		"best faith should be recorded, got %s" % profile.get_stat("best_faith"))
	check(int(profile.get_stat("total_mended")) == 4,
		"mended should accumulate, got %s" % profile.get_stat("total_mended"))
	check(profile.get_stat("readers_finished").has("aries"),
		"the reader that finished should be recorded, got %s" % str(profile.get_stat("readers_finished")))
	done("_test_a_finished_run_is_recorded_once")


## THE READING STREAK IS WATCHED OFF THE LEDGER, not off a call from Run.gd —
## the same rule the rest of this file follows. Which means it has to survive
## what the ledger actually does: it grows mid-screen (nobody changes screen
## when a reading ends), and it starts over on a new run.
func _test_the_streaks_count_and_break() -> void:
	profile.reset()
	profile._counted = 0
	run.state = run.fresh()
	run.pick_reader(0)
	run.take_pick(0)
	var ledger: Array = []
	for outcome in ["mended", "mended", "mended"]:
		ledger.append({"outcome": outcome})
		run.state["ledger"] = ledger
		run.state_changed.emit()
	check(int(profile.get_stat("streak_readings")) == 3,
		"three mended in a row is a streak of 3, got %s" % profile.get_stat("streak_readings"))

	# The same ledger, emitted again: nobody sat down twice.
	run.state_changed.emit()
	check(int(profile.get_stat("streak_readings")) == 3,
		"a redraw must not count anybody twice, got %s" % profile.get_stat("streak_readings"))

	ledger.append({"outcome": "left"})
	run.state["ledger"] = ledger
	run.state_changed.emit()
	check(int(profile.get_stat("streak_readings")) == 0,
		"somebody going home as they came ends the streak, got %s" % profile.get_stat("streak_readings"))
	check(int(profile.get_stat("best_streak_readings")) == 3,
		"the best it reached is kept, got %s" % profile.get_stat("best_streak_readings"))
	check(int(profile.get_stat("total_left")) == 1,
		"they should be counted, got %s" % profile.get_stat("total_left"))

	# A NEW RUN, the way the game starts one: the state changes once with an
	# empty ledger before anybody sits down. Whatever is already on a ledger the
	# first time we see a run was counted when it happened — that is what stops
	# a resumed run from handing out a streak nobody played, and it is why this
	# emits before adding to the ledger rather than after.
	run.state = run.fresh()
	run.state_changed.emit()
	run.state["ledger"] = [{"outcome": "mended"}]
	run.state_changed.emit()
	check(int(profile.get_stat("streak_readings")) == 1,
		"a new run continues the streak from where it was, got %s" % profile.get_stat("streak_readings"))

	# AND A RESUMED RUN COUNTS NOBODY TWICE. Same shape as a reload: a run
	# arrives already carrying a ledger. Everyone on it was counted the day they
	# sat down.
	profile._run_seed = "some other evening"
	run.state["ledger"] = [{"outcome": "mended"}, {"outcome": "mended"}, {"outcome": "mended"}]
	run.state_changed.emit()
	check(int(profile.get_stat("streak_readings")) == 1,
		"resuming a run must not re-count its ledger, got %s" % profile.get_stat("streak_readings"))
	done("_test_the_streaks_count_and_break")


## THE DAY STREAK STARTS AT ONE. It read zero on the very first day of a
## profile — the day you played counts, which is not the same rule as a person
## who went home as they came counting for nothing.
func _test_the_day_streak() -> void:
	profile.reset()
	profile._count_today()
	check(int(profile.get_stat("streak_days")) == 1,
		"the first day played is a streak of 1, got %s" % profile.get_stat("streak_days"))

	# Twice in one day is still one day.
	profile._count_today()
	check(int(profile.get_stat("streak_days")) == 1,
		"a second run the same day does not add a day, got %s" % profile.get_stat("streak_days"))

	# Yesterday, then today: two.
	profile.set_stat("last_day", profile._the_day_before(Time.get_date_string_from_system()))
	profile._count_today()
	check(int(profile.get_stat("streak_days")) == 2,
		"playing the day after continues it, got %s" % profile.get_stat("streak_days"))

	# A gap starts again at one, and keeps the best.
	profile.set_stat("last_day", "2001-01-01")
	profile._count_today()
	check(int(profile.get_stat("streak_days")) == 1,
		"a missed day starts again at 1, got %s" % profile.get_stat("streak_days"))
	check(int(profile.get_stat("best_streak_days")) == 2,
		"the best run of days is kept, got %s" % profile.get_stat("best_streak_days"))
	done("_test_the_day_streak")


## Same trap as Settings: the defaults live in a `const`, so handing out the
## Array itself would let one caller corrupt it for the rest of the session.
func _test_stats_are_copied_out() -> void:
	var list: Array = profile.get_stat("readers_finished")
	list.append("not_really_finished")
	check(not profile.get_stat("readers_finished").has("not_really_finished"),
		"mutating a returned Array must not reach the stored stat")
	done("_test_stats_are_copied_out")
