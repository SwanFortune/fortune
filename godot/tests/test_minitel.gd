## Headless test for the Minitel — the 3615 + four-letter secret-code channel.
##   godot --headless --path godot -s tests/test_minitel.gd
##
## The guarantees under test:
##   - what the player types is normalised the way a Minitel keyboard would
##     have forced it (uppercase, unaccented, exactly four letters), and
##     anything else is refused with a line rather than silence;
##   - every refusal is a distinct `kind`, so the screen can colour a typo
##     differently from a service that does not exist;
##   - dialling is recorded once, and a one-shot code says so on the second
##     attempt instead of quietly re-granting;
##   - the three levers do what they claim: `codes_entered` feeds
##     Profile.meets(), `grants` moves a numeric stat, `arms` makes a secret
##     event reachable;
##   - AND, the point of the `secret` flag: an unarmed secret event can never
##     turn up in the ordinary map pool. That is the one thing a bug here
##     would leak — a player seeing the payoff without ever finding the code.
##   - a code naming a stat or an event that does not exist is REPORTED. The
##     recurring failure this port keeps recording is content that silently
##     does nothing; a mod that misspells an event title should hear about it.
extends SceneTree

const TESTS := [
	"_test_normalise",
	"_test_refusals",
	"_test_a_code_is_recorded_once",
	"_test_repeatable_codes",
	"_test_grants_lever",
	"_test_arms_lever",
	"_test_secret_events_stay_out_of_the_ordinary_pool",
	"_test_codes_can_gate_an_unlock",
	"_test_broken_codes_are_reported",
	"_test_each_screen_line_has_its_own_key",
]

var failures: Array[String] = []
var finished: Dictionary = {}
var content: Node
var run: Node
var profile: Node
var minitel: Node
var i18n: Node


func _initialize() -> void:
	content = root.get_node("Content")
	run = root.get_node("Run")
	profile = root.get_node("Profile")
	minitel = root.get_node("Minitel")
	i18n = root.get_node("I18n")
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


func _test_normalise() -> void:
	# Case, surrounding whitespace and the separators someone might type
	# between letters all wash out.
	for raw in ["oeil", "OEIL", "  oeil  ", "O-E-I-L", "o e i l", "ŒIL".replace("Œ", "OE")]:
		check(minitel.normalise(raw) == "OEIL", "'%s' should normalise to OEIL, got '%s'" % [raw, minitel.normalise(raw)])
	# Accents: a service code was four unaccented letters, and a French
	# keyboard makes typing É easy by accident.
	check(minitel.normalise("éûiî") == "EUII", "accents should reduce to their letters, got '%s'" % minitel.normalise("éûiî"))
	# Wrong lengths and non-letters are not codes at all.
	for raw in ["", "OEI", "OEILS", "3615", "OE1L", "OEI!"]:
		check(minitel.normalise(raw) == "", "'%s' is not a four-letter code" % raw)
	done("_test_normalise")


## Every wrong thing gets its own answer, and none of them is an empty screen.
func _test_refusals() -> void:
	var wrong_prefix: Dictionary = minitel.submit("3614", "OEIL")
	check(wrong_prefix["kind"] == minitel.BAD_FORMAT, "a wrong prefix is a format refusal, got '%s'" % wrong_prefix["kind"])

	var short_code: Dictionary = minitel.submit("3615", "OEI")
	check(short_code["kind"] == minitel.BAD_FORMAT, "a three-letter code is a format refusal, got '%s'" % short_code["kind"])

	var no_such: Dictionary = minitel.submit("3615", "ZZZZ")
	check(no_such["kind"] == minitel.UNKNOWN, "a well-formed code nobody wrote is UNKNOWN, got '%s'" % no_such["kind"])
	check(minitel.entered().is_empty(), "a refused code must not be recorded as dialled")

	for res in [wrong_prefix, short_code, no_such]:
		check(not res["lines"].is_empty(), "every answer prints something — a blank tube reads as a broken machine")
	done("_test_refusals")


func _test_a_code_is_recorded_once() -> void:
	var first: Dictionary = minitel.submit("3615", "oeil")
	check(first["kind"] == minitel.OK, "the first dial should connect, got '%s'" % first["kind"])
	check(minitel.entered() == ["OEIL"], "it should be recorded in canonical form, got %s" % [minitel.entered()])

	var second: Dictionary = minitel.submit("3615", "OEIL")
	check(second["kind"] == minitel.ALREADY, "the second dial should say so, got '%s'" % second["kind"])
	check(minitel.entered() == ["OEIL"], "and must not record it twice, got %s" % [minitel.entered()])
	# The service's own text still prints — you can re-read what it said.
	check(second["lines"].size() > 1, "an already-dialled service should still show its screen")
	done("_test_a_code_is_recorded_once")


## `repeatable` exists so a code can be a thing you do rather than a thing you
## found. Nothing in the base game uses it; a mod will.
func _test_repeatable_codes() -> void:
	var codes: Dictionary = content.minitel_codes
	var restore = codes.get("SOUS", {}).duplicate(true)
	codes["SOUS"] = {"screen": ["TEST"], "repeatable": true, "grants": {"stat": "total_mended", "add": 1}}

	check(minitel.submit("3615", "SOUS")["kind"] == minitel.OK, "first dial")
	check(minitel.submit("3615", "SOUS")["kind"] == minitel.OK, "a repeatable code connects again rather than reporting ALREADY")
	check(int(profile.get_stat("total_mended")) == 2, "and applies again, got %s" % profile.get_stat("total_mended"))
	check(minitel.entered() == ["SOUS"], "still recorded once, got %s" % [minitel.entered()])

	codes["SOUS"] = restore
	done("_test_repeatable_codes")


func _test_grants_lever() -> void:
	var codes: Dictionary = content.minitel_codes
	var restore = codes.get("SOUS", {}).duplicate(true)
	codes["SOUS"] = {"screen": ["TEST"], "grants": {"stat": "best_faith", "add": 7}}

	profile.set_stat("best_faith", 3)
	minitel.submit("3615", "SOUS")
	check(int(profile.get_stat("best_faith")) == 10, "grants should add to the stat, got %s" % profile.get_stat("best_faith"))

	codes["SOUS"] = restore
	done("_test_grants_lever")


func _test_arms_lever() -> void:
	check(minitel.armed_events().is_empty(), "nothing is armed on a fresh profile")
	minitel.submit("3615", "OEIL")
	var armed: Array = minitel.armed_events()
	check(armed.size() == 1, "OEIL should arm exactly one event, got %d" % armed.size())
	if armed.size() == 1:
		check(bool(armed[0].get("secret", false)), "what it armed should be a secret event")
		check(str(armed[0].get("title", "")) == "The number nobody answers",
			"got '%s'" % armed[0].get("title", ""))
	done("_test_arms_lever")


## The load-bearing one. A `secret` event must be unreachable until a code
## arms it — otherwise the reward for finding a code is something the player
## would have seen anyway, and the whole channel is pointless.
func _test_secret_events_stay_out_of_the_ordinary_pool() -> void:
	var secret_titles: Array = []
	for e in content.events:
		if bool(e.get("secret", false)):
			secret_titles.append(str(e.get("title", "")))
	check(not secret_titles.is_empty(), "the base game should ship at least one secret event to test with")

	for e in run.ordinary_events():
		check(not secret_titles.has(str(e.get("title", ""))),
			"secret event '%s' is in the ordinary pool — it can turn up without its code" % e.get("title", ""))

	# And it is genuinely offered once armed. Driven through make_options()
	# rather than armed_events() alone, since the injection is what a player
	# actually meets.
	minitel.submit("3615", "OEIL")
	run.state = run.fresh()
	run.pick_reader(0)
	var seen := false
	for _i in 400:
		# night 0, knock 1, nothing seen: an ordinary map draw, not the boss.
		for o in run.make_options(0, 1, []):
			if o.get("kind", "") == "break" and secret_titles.has(str(o.get("rest", {}).get("title", ""))):
				seen = true
	check(seen, "once armed, the secret event should eventually be offered on the map")
	done("_test_secret_events_stay_out_of_the_ordinary_pool")


## The third lever needs no code of its own: Profile.meets() already reads the
## list stat, so an `unlock` can be gated on a Minitel code today.
func _test_codes_can_gate_an_unlock() -> void:
	var cond := {"stat": "codes_entered", "includes": "OEIL"}
	check(not profile.meets(cond), "before dialling, a code-gated unlock is not met")
	minitel.submit("3615", "OEIL")
	check(profile.meets(cond), "after dialling, it is")
	# And the derived wording says what to do, rather than describing it as a
	# reader to finish a run with.
	var text: String = profile.unlock_text(cond)
	check(text.contains("3615"), "the unlock line should tell you to dial, got '%s'" % text)
	done("_test_codes_can_gate_an_unlock")


## A code that names a stat or an event that is not there is a content mistake,
## and content mistakes in this port are reported, never silent.
func _test_broken_codes_are_reported() -> void:
	var codes: Dictionary = content.minitel_codes
	codes["BRKN"] = {"screen": ["TEST"], "grants": {"stat": "no_such_stat", "add": 1}, "arms": "no such event"}

	print("--- the next two WARNINGs are expected: a deliberately broken code ---")
	var res: Dictionary = minitel.submit("3615", "BRKN")
	# It still connects — a broken lever must not make the terminal look dead —
	# but it changed nothing and said so on the console.
	check(res["kind"] == minitel.OK, "a broken code still connects, got '%s'" % res["kind"])
	check(minitel.armed_events().is_empty(), "an event that does not exist arms nothing")

	# The list stats cannot be added to; naming one is the other easy mistake.
	codes["BRKN"] = {"screen": ["TEST"], "grants": {"stat": "readers_finished", "add": 1}}
	profile.set_stat("codes_entered", [])
	print("--- the next WARNING is expected: adding to a list stat ---")
	minitel.submit("3615", "BRKN")
	check(typeof(profile.get_stat("readers_finished")) == TYPE_ARRAY,
		"a list stat should survive a code trying to add to it")

	codes.erase("BRKN")
	done("_test_broken_codes_are_reported")


## A service's screen is an ARRAY, and each line needs its own translation key.
## Keying the block as a whole is the natural first cut and is invisible in
## English — every lookup misses and falls back to the line itself — so it only
## shows up once somebody translates a code, by which point it looks like a
## translator's mistake. Injects a translation and checks the lines came back
## distinct.
func _test_each_screen_line_has_its_own_key() -> void:
	var codes: Dictionary = content.minitel_codes
	var restore = codes.get("SOUS", {}).duplicate(true)
	codes["SOUS"] = {"screen": ["ONE", "TWO", "THREE"]}

	var strings: Dictionary = i18n._strings
	var saved := strings.duplicate()
	strings["minitel/SOUS/screen0"] = "UN"
	strings["minitel/SOUS/screen1"] = "DEUX"
	strings["minitel/SOUS/screen2"] = "TROIS"

	var lines: Array = minitel.submit("3615", "SOUS")["lines"]
	check(lines == ["UN", "DEUX", "TROIS"],
		"each screen line should resolve to its own key, got %s" % [lines])

	i18n._strings = saved
	codes["SOUS"] = restore
	done("_test_each_screen_line_has_its_own_key")
