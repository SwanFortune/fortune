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
##   - a service of several pages hands back every page, translated line by
##     line, and the screen turns them with SUITE and RETOUR; the tube prints
##     at the line's speed, a key finishes it, and motion off skips it;
##   - a code naming a stat or an event that does not exist is REPORTED. The
##     recurring failure this port keeps recording is content that silently
##     does nothing; a mod that misspells an event title should hear about it.
extends "res://tests/harness.gd"

var content: Node
var run: Node
var profile: Node
var minitel: Node
var i18n: Node


func setup() -> void:
	content = root.get_node("Content")
	run = root.get_node("Run")
	profile = root.get_node("Profile")
	minitel = root.get_node("Minitel")
	i18n = root.get_node("I18n")
	content.reload()


## Every test starts from a player who has typed nothing, and the last one puts
## the real profile back — this is the autoloaded Profile, not a copy.
func before_each(_test_name: String) -> void:
	profile.reset()


func teardown() -> void:
	profile.reset()


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
	done()


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
	done()


func _test_a_code_is_recorded_once() -> void:
	var first: Dictionary = minitel.submit("3615", "oeil")
	check(first["kind"] == minitel.OK, "the first dial should connect, got '%s'" % first["kind"])
	check(minitel.entered() == ["OEIL"], "it should be recorded in canonical form, got %s" % [minitel.entered()])

	var second: Dictionary = minitel.submit("3615", "OEIL")
	check(second["kind"] == minitel.ALREADY, "the second dial should say so, got '%s'" % second["kind"])
	check(minitel.entered() == ["OEIL"], "and must not record it twice, got %s" % [minitel.entered()])
	# The service's own text still prints — you can re-read what it said.
	check(second["lines"].size() > 1, "an already-dialled service should still show its screen")
	done()


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
	done()


func _test_grants_lever() -> void:
	var codes: Dictionary = content.minitel_codes
	var restore = codes.get("SOUS", {}).duplicate(true)
	codes["SOUS"] = {"screen": ["TEST"], "grants": {"stat": "best_faith", "add": 7}}

	profile.set_stat("best_faith", 3)
	minitel.submit("3615", "SOUS")
	check(int(profile.get_stat("best_faith")) == 10, "grants should add to the stat, got %s" % profile.get_stat("best_faith"))

	codes["SOUS"] = restore
	done()


func _test_arms_lever() -> void:
	check(minitel.armed_events().is_empty(), "nothing is armed on a fresh profile")
	minitel.submit("3615", "OEIL")
	var armed: Array = minitel.armed_events()
	check(armed.size() == 1, "OEIL should arm exactly one event, got %d" % armed.size())
	if armed.size() == 1:
		check(bool(armed[0].get("secret", false)), "what it armed should be a secret event")
		check(str(armed[0].get("title", "")) == "The number nobody answers",
			"got '%s'" % armed[0].get("title", ""))
	done()


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

	# And it is genuinely offered once armed. Driven through the night's PLAN and
	# then through make_options(), because that is now the whole path: the roll
	# that decides an evening has a secret in it happens when the night is
	# planned (Run.make_plan), and the agenda promises it before the hour
	# arrives. Asking make_options() on its own — which an earlier version of
	# this test did — gets the no-plan fallback, which offers two callers and
	# nothing else, forever.
	minitel.submit("3615", "OEIL")
	run.state = run.fresh()
	run.pick_reader(0)
	var promised := false
	var seen := false
	for _i in 400:
		var plan: Array = run.make_plan(0)
		for step in plan.size():
			if not plan[step].get("offers", []).has("secret"):
				continue
			promised = true
			for o in run.make_options(0, step, [], plan):
				if o.get("kind", "") == "break" and secret_titles.has(str(o.get("rest", {}).get("title", ""))):
					seen = true
	check(promised, "once armed, a night's plan should eventually have a secret hour in it")
	check(seen, "once armed, the secret event should eventually be offered on the map")
	done()


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
	done()


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
	done()


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
	done()


## A service of more than one page: every page comes back, in order, none of
## them empty, and a page after the first is translated under its own keys —
## the first cut of one key per block printed line one four times over, and a
## page keyed like the first would print page one twice.
func _test_a_service_has_pages() -> void:
	var said: Dictionary = minitel.submit("3615", "OEIL")
	var pages: Array = said.get("pages", [])
	var want: Array = content.minitel_codes["OEIL"].get("pages", [])
	check(pages.size() == 1 + want.size(), "OEIL should come back as %d pages, got %d" % [1 + want.size(), pages.size()])
	check(said["lines"] == pages[0], "`lines` should be the first page")
	check(pages.all(func(p): return p is Array and not p.is_empty()), "no page may be empty: %s" % [pages])
	if pages.size() > 1:
		check(pages[1] != pages[0], "the second page should not be the first again")
	# A page of its own in a locale: set a key for page two's first line and it
	# must be that line, and only that one, that changes.
	i18n._strings["minitel/OEIL/p1_0"] = "PAGE DEUX, TRADUITE"
	var again: Array = minitel.pages("OEIL", content.minitel_codes["OEIL"])
	check(again[1][0] == "PAGE DEUX, TRADUITE", "page two's first line should read its own key, got '%s'" % again[1][0])
	check(again[0][0] != "PAGE DEUX, TRADUITE", "and page one's first line should not")
	i18n.reload()
	# A refusal is one page, so the screen never has to ask.
	check(minitel.submit("3615", "ZZZZ").get("pages", []).size() == 1, "a refusal is a single page")
	done()


## THE SCREEN: the tube prints at the line's speed and a key finishes it; SUITE
## and RETOUR turn the pages and know where the ends are; with motion off the
## text is simply there.
func _test_the_screen_turns_pages_at_the_lines_speed() -> void:
	var settings: Node = root.get_node("Settings")
	var speed_before = settings.get_value("animation_scale")
	root.size = Vector2i(1280, 720)
	for motion in [true, false]:
		profile.reset()
		settings.set_value("animation_scale", 1.0 if motion else 0.0)
		var screen: Node = load("res://scenes/MinitelScreen.tscn").instantiate()
		root.add_child(screen)
		await process_frame
		screen._prefix_field.text = "3615"
		screen._code_field.text = "OEIL"
		screen._send()
		await process_frame
		var total: int = content.minitel_codes["OEIL"]["screen"].reduce(func(a, l): return a + str(l).length(), 0)
		if motion:
			check(screen.printing(), "a service should arrive at the line's speed, not all at once")
			var seconds: float = float(total) / minitel.chars_per_second()
			check(seconds > 0.2 and seconds < 3.0, "a first page of %d characters should take a moment to print, takes %.2fs" % [total, seconds])
			screen.finish_printing()
		check(not screen.printing(), "a key should finish the page (motion %s)" % motion)
		check(_all_shown(screen), "every character should be showing once the page is printed (motion %s)" % motion)
		check(screen._page_mark.text == "1/2", "the tube should say page 1/2, says '%s'" % screen._page_mark.text)
		check(screen._keys["retour"].disabled and not screen._keys["suite"].disabled, "on page one, RETOUR is off and SUITE is on")
		screen._turn(1)
		await process_frame
		screen.finish_printing()
		check(screen._page_mark.text == "2/2", "SUITE should turn to page 2/2, says '%s'" % screen._page_mark.text)
		check(_tube_text(screen).contains(str(content.minitel_codes["OEIL"]["pages"][0][0])), "page two should be on the tube: %s" % _tube_text(screen))
		check(screen._keys["suite"].disabled, "on the last page SUITE is off")
		screen._turn(1)
		check(screen._page == 1, "SUITE on the last page stays there")
		screen._turn(-1)
		await process_frame
		check(screen._page == 0, "RETOUR goes back a page")
		screen._home()
		await process_frame
		screen.finish_printing()
		check(_tube_text(screen).contains(minitel.SAY_IDLE), "SOMMAIRE should go back to the directory: %s" % _tube_text(screen))
		screen.queue_free()
		await process_frame
	settings.set_value("animation_scale", speed_before)
	done()


func _tube_labels(screen: Node) -> Array:
	return screen._lines_box.get_children().filter(func(c): return c is Label and not c.is_queued_for_deletion())


func _tube_text(screen: Node) -> String:
	return " / ".join(_tube_labels(screen).map(func(l): return l.text))


func _all_shown(screen: Node) -> bool:
	return _tube_labels(screen).all(func(l): return l.visible_characters == -1 or l.visible_characters >= l.get_total_character_count())
