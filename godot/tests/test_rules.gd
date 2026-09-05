## Headless smoke test. Run with:
##   godot --headless --path godot -s tests/test_rules.gd
## Exits 0 and prints "ALL PASS" if every assertion holds, exits 1 and prints
## the first failure otherwise. Not a Godot-native GUT test suite (none is
## installed) — a minimal SceneTree script is enough to boot autoloads
## (Content/Rules/etc.) headlessly and exercise them without any UI.
##
## Autoloads are fetched via get_node() at runtime (root.get_node("Content"))
## rather than referenced by their bare global name (Content.foo): a script
## passed to Godot via -s is compiled before the engine registers autoloads
## as global script identifiers, so the bare names aren't resolvable from
## this particular file (they work fine from ordinary scene scripts, which
## load only after the game has finished booting).
extends SceneTree

## Every test method, called in order. Listed rather than hand-called so the
## "did it actually finish?" guard below can't fall out of step with the calls.
const TESTS := [
	"_test_content_loaded",
	"_test_mod_pack_merged",
	"_test_pack_can_be_disabled",
	"_test_simulate_basic_line",
	"_test_simulate_shield_denial",
	"_test_simulate_wall_growth",
	"_test_simulate_reader_opener_passive",
	"_test_simulate_white_cap",
	"_test_simulate_norepeat_sign",
	"_test_auto_text",
]

var failures: Array[String] = []
var finished: Dictionary = {}
var content: Node
var rules: Node


func _initialize() -> void:
	content = root.get_node("Content")
	rules = root.get_node("Rules")
	# A -s script's _initialize() runs before autoloads' own _ready() has had a
	# chance to fire (no frame has been processed yet), so Content's registries
	# would still be empty here. Force the load explicitly rather than relying
	# on node-lifecycle timing that doesn't apply in this headless entry point.
	content.reload()

	print("[test] Content load errors: ", content.load_errors)
	for t in TESTS:
		call(t)
		# A GDScript runtime error (reading a property that no longer exists,
		# say) aborts the function it happens in, prints SCRIPT ERROR, and then
		# lets execution carry on in the caller with no exception to catch and
		# no exit code set. A test that died half-way therefore used to report
		# ALL PASS — which is exactly how a stale reference in
		# _test_mod_pack_merged survived several commits. Each test signs off at
		# its own last line; anything that didn't reach it is a failure.
		if not finished.has(t):
			failures.append("%s aborted before finishing — see the SCRIPT ERROR above" % t)

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


## Last line of every test method: see the guard in _initialize().
func done(name: String) -> void:
	finished[name] = true


func _test_content_loaded() -> void:
	check(content.signs.size() == 12, "expected 12 signs, got %d" % content.signs.size())
	# Base readers by key rather than a count of the merged list: the example
	# pack now adds a fourteenth to demonstrate the unlock field, and a mod
	# adding a reader is the point of the pipeline rather than a regression.
	for key in ["aries", "taurus", "gemini", "cancer", "leo", "virgo", "libra",
			"scorpio", "sagittarius", "capricorn", "aquarius", "pisces", "serpentarius"]:
		check(not content.get_reader(key).is_empty(), "base reader '%s' should be loaded" % key)
	check(content.jobs.size() == 10, "expected 10 jobs, got %d" % content.jobs.size())
	check(content.sitters.size() == 9, "expected 9 sitters, got %d" % content.sitters.size())
	check(content.has_card("Pour The Tea"), "base card Pour The Tea should be loaded")
	check(content.cards_basics.size() == 7, "expected 7 basic cards, got %d" % content.cards_basics.size())
	done("_test_content_loaded")


func _test_mod_pack_merged() -> void:
	check(bool(root.get_node("Settings").get_value("load_example_mods")),
		"the load_example_mods setting must be on for this test run")
	check(content.has_card("Warm The Cup"), "example mod's new card should have merged in")
	check(content.has_card("Pour The Tea"), "merging a mod pack should not drop base cards")
	done("_test_mod_pack_merged")


## The Mods screen's one real power: switching a pack off has to actually
## unload its records, and switching it back on has to bring them back. The
## base pack is exempt — there is no game left without it — so that is checked
## too rather than left to trust.
func _test_pack_can_be_disabled() -> void:
	var settings: Node = root.get_node("Settings")
	var restore: Array = Array(settings.get_value("disabled_mods")).duplicate()

	check(content.has_card("Warm The Cup"), "precondition: the example pack's card should be loaded")
	var base_records: int = content.cards_minor.size()

	settings.set_value("disabled_mods", ["example.a_new_card"])
	content.reload()
	check(not content.has_card("Warm The Cup"), "a disabled pack's card should be gone")
	check(content.has_card("Pour The Tea"), "disabling a mod must not touch base content")
	check(content.cards_minor.size() == base_records - 1,
		"exactly the disabled pack's records should go, got %d vs %d" % [content.cards_minor.size(), base_records - 1])
	for p in content.packs:
		if str(p.get("id", "")) == "example.a_new_card":
			check(not bool(p["enabled"]), "the pack should still be listed, marked off")

	# The base pack ignores the list entirely.
	settings.set_value("disabled_mods", ["parlour.base"])
	content.reload()
	check(content.has_card("Pour The Tea"), "the base pack must not be disableable")

	settings.set_value("disabled_mods", restore)
	content.reload()
	check(content.has_card("Warm The Cup"), "re-enabling should bring the pack back")
	done("_test_pack_can_be_disabled")


func _mk_run_ctx(reader_key: String, marks: Array = []) -> Dictionary:
	return {"reader": content.get_reader(reader_key), "marks": marks, "serp_el": ""}


func _mk_fight(sitter_el: String, sign_key: String, cross: Array, hp: int = 0, denial: int = 0, max_hp: int = 100) -> Dictionary:
	var sign: Dictionary = content.get_sign(sign_key) if sign_key != "" else {"fx": ""}
	return {
		"el": sitter_el, "quirk": sign, "job": {"fx": ""}, "hp": hp, "max": max_hp,
		"denial": denial, "denialUp": 0, "cross": cross,
	}


## A plain line with no reader passives, no sign denial: total should just be
## the sum of each card's base f (+2 for matching the sitter's element, per
## the "el === f.el" rule in simulate()).
func _test_simulate_basic_line() -> void:
	var ctx := _mk_run_ctx("gemini")  # air reader, no relevant passive for this line
	var tea: Dictionary = content.get_card("Pour The Tea")      # water, f=3
	var palm: Dictionary = content.get_card("Read Their Palm")  # earth, f=3
	var fight := _mk_fight("water", "", [tea, palm])
	var sim: Dictionary = rules.simulate(ctx, fight)
	# tea: f=3, el=water=fight.el -> +2 => 5. palm: f=3, el=earth != water -> 3.
	check(sim["rows"][0]["total"] == 5, "tea should score 5 (3 base +2 own-element), got %s" % sim["rows"][0]["total"])
	check(sim["rows"][1]["total"] == 3, "palm should score 3 (earth, off-element), got %s" % sim["rows"][1]["total"])
	check(sim["gross"] == 8, "gross should be 8, got %s" % sim["gross"])
	check(sim["hpAfter"] == 8, "hpAfter should be 8 (denial=0), got %s" % sim["hpAfter"])
	done("_test_simulate_basic_line")


## Taurus sitter (shield fx): a numeric wall absorbs the first `denial` points
## of non-pierced total. cross = [f=5 pierce card, f=3 plain card], denial=4.
## Reader (taurus, earth) and sitter element (earth) are both chosen to NOT
## match the air card, so no incidental own-element bonus muddies the numbers
## (every reader's elBonus gives +1 to their own element regardless of their
## unique fx — see el_bonus() — so this has to be picked deliberately).
func _test_simulate_shield_denial() -> void:
	var ctx := _mk_run_ctx("taurus")
	var name_card: Dictionary = content.get_card("Say Their Name")  # f=5, pierce:true, neutral
	var why_card: Dictionary = content.get_card("Ask Them Why")     # f=3, air
	var fight := _mk_fight("earth", "taurus", [name_card, why_card], 0, 4)
	var sim: Dictionary = rules.simulate(ctx, fight)
	# gross = 5 + 3 = 8. pierced = 5 (from the pierce card). soft = gross-pierced = 3.
	# absorbed = min(denial=4, soft=3) = 3. applied = pierced + max(0, soft-absorbed) = 5 + 0 = 5.
	check(sim["gross"] == 8, "gross should be 8, got %s" % sim["gross"])
	check(sim["pierced"] == 5, "pierced should be 5, got %s" % sim["pierced"])
	check(sim["absorbed"] == 3, "absorbed should be 3, got %s" % sim["absorbed"])
	check(sim["applied"] == 5, "applied should be 5 (pierce bypasses the wall), got %s" % sim["applied"])
	done("_test_simulate_shield_denial")


## next_wall(): the port's own rule (NOT in the source), driven by the
## denial_wall registry — a Taurus wall is worn down by whatever it absorbs and
## thickens 2 again after every reading, and never passes base denial x cap.
## Pisces (tide) keeps the source's undrainable, uncapped wall.
func _test_simulate_wall_growth() -> void:
	var base := 10
	var f := {
		"quirk": content.get_sign("taurus"), "sitter": {"denial": base},
		"denial": base, "denialUp": 2,
	}
	check(rules.next_wall(f, {"absorbed": 0}) == base + 2, "an untouched wall just thickens, got %s" % rules.next_wall(f, {"absorbed": 0}))
	check(rules.next_wall(f, {"absorbed": 6}) == base - 6 + 2, "absorbing should wear the wall down before it thickens, got %s" % rules.next_wall(f, {"absorbed": 6}))
	check(rules.next_wall(f, {"absorbed": 99}) == 2, "a wall worn through cannot go negative, got %s" % rules.next_wall(f, {"absorbed": 99}))

	# Ceiling: at base x cap (2) the wall stops, however many readings bounce.
	f["denial"] = base * 2 - 1
	check(rules.next_wall(f, {"absorbed": 0}) == base * 2, "growth should clamp to base x cap, got %s" % rules.next_wall(f, {"absorbed": 0}))
	f["denial"] = base * 2
	check(rules.next_wall(f, {"absorbed": 0}) == base * 2, "a capped wall should stop growing, got %s" % rules.next_wall(f, {"absorbed": 0}))

	# Pisces: no drain, no ceiling — unchanged from the source.
	var t := {"quirk": content.get_sign("pisces"), "sitter": {"denial": 0}, "denial": 40, "denialUp": 4}
	check(rules.next_wall(t, {"absorbed": 40}) == 44, "tide should not be worn down by what it absorbs, got %s" % rules.next_wall(t, {"absorbed": 40}))

	# A sign with no wall at all must stay at 0 rather than picking up a rule.
	var none := {"quirk": content.get_sign("leo"), "sitter": {"denial": 7}, "denial": 0, "denialUp": 0}
	check(rules.next_wall(none, {"absorbed": 0}) == 0, "a sign with no wall should stay at 0, got %s" % rules.next_wall(none, {"absorbed": 0}))

	# simulate() must report the same number Run will actually set, including
	# for a Scorpio reader, whose pierce trait lowers the *displayed* denial but
	# not the wall itself — these two used to disagree by exactly 4.
	var ctx := _mk_run_ctx("scorpio")
	var why_card: Dictionary = content.get_card("Ask Them Why")
	var fight := _mk_fight("earth", "taurus", [why_card], 0, base)
	fight["denialUp"] = 2
	fight["sitter"] = {"denial": base}
	var sim: Dictionary = rules.simulate(ctx, fight)
	check(sim["shieldNext"] == rules.next_wall(fight, sim),
		"shieldNext must equal what Run will set the wall to, got %s" % sim["shieldNext"])
	done("_test_simulate_wall_growth")


## Virgo reader (fx:'white'): elementless cards restore +3, but only the first
## `fx.white.cap` of them in a reading. NOT the source's rule — see the comment
## on white_cap in Rules.simulate().
## HOW MUCH is data now (fx.json's `amount`/`cap`, see Rules.trait_amount) and
## this reads it from there. WHICH CARD and WHEN is the mechanic, and that is
## what these hand-traced cases are for — a test that hard-codes the magnitude
## goes red on every balance pass and teaches nobody anything.
func _test_simulate_white_cap() -> void:
	var cap: int = int(content.fx.get("white", {}).get("cap", 0))
	var amt: int = rules.trait_amount("white", 3)
	check(cap >= 1 and amt >= 1, "the white trait should pay something to at least one card, got %d x %d" % [cap, amt])
	var ctx := _mk_run_ctx("virgo")
	# Three elementless cards, all with a plain base f and no conditional
	# bonuses of their own that would muddy the arithmetic.
	var a: Dictionary = content.get_card("Say Their Name")   # f=5, neutral, pierce
	var b: Dictionary = content.get_card("Take Their Coat")  # f=1, neutral
	var c: Dictionary = content.get_card("Take Their Coat")
	var fight := _mk_fight("earth", "", [a, b, c])
	var sim: Dictionary = rules.simulate(ctx, fight)
	check(sim["rows"][0]["total"] == 5 + amt,
		"the 1st elementless card takes the white bonus, got %s" % sim["rows"][0]["total"])
	check(sim["rows"][1]["total"] == 1 + (amt if cap > 1 else 0),
		"the 2nd elementless card takes it only within the cap, got %s" % sim["rows"][1]["total"])
	check(sim["rows"][2]["total"] == 1 + (amt if cap > 2 else 0),
		"the 3rd elementless card is past the cap and takes nothing, got %s" % sim["rows"][2]["total"])
	done("_test_simulate_white_cap")


## Aries reader has fx:'opener' -> first card spoken restores +2 (on top of
## any card-level opener bonus). Card here has no opener field of its own.
func _test_simulate_reader_opener_passive() -> void:
	var ctx := _mk_run_ctx("aries")
	var why_card: Dictionary = content.get_card("Ask Them Why")  # f=3, air, no card-level opener bonus
	var fight := _mk_fight("earth", "", [why_card])   # off-element, sitter is earth not air
	var sim: Dictionary = rules.simulate(ctx, fight)
	# base 3, no el_bonus (air != earth, air != reader.el fire), the opener
	# amount for being spoken first, no own-el +2.
	var opener: int = rules.trait_amount("opener", 2)
	check(opener >= 1, "the opener trait should be worth something, got %d" % opener)
	check(sim["rows"][0]["total"] == 3 + opener,
		"the opener passive should add %d to the first card, got %s" % [opener, sim["rows"][0]["total"]])
	done("_test_simulate_reader_opener_passive")


## Virgo (norepeat fx): a sign already spoken in this reading restores nothing
## the *second* time. Two water cards in a row -> second one scores 0.
func _test_simulate_norepeat_sign() -> void:
	var ctx := _mk_run_ctx("gemini")
	var tea: Dictionary = content.get_card("Pour The Tea")               # water, f=3
	var agree: Dictionary = content.get_card("Agree That It Is Unfair")  # water, f=2
	var fight := _mk_fight("earth", "virgo", [tea, agree])
	var sim: Dictionary = rules.simulate(ctx, fight)
	check(sim["rows"][0]["total"] == 3, "first water card should score normally (3), got %s" % sim["rows"][0]["total"])
	check(sim["rows"][1]["total"] == 0, "second water card should score 0 under norepeat, got %s" % sim["rows"][1]["total"])
	done("_test_simulate_norepeat_sign")


func _test_auto_text() -> void:
	var name_card: Dictionary = content.get_card("Say Their Name")
	var text: String = rules.auto_text(name_card)
	check(text == "Straight through their denial.", "auto_text for a pierce card, got: %s" % text)
	done("_test_auto_text")
