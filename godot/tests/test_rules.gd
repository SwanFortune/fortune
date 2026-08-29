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

var failures: Array[String] = []
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
	_test_content_loaded()
	_test_mod_pack_merged()
	_test_simulate_basic_line()
	_test_simulate_shield_denial()
	_test_simulate_reader_opener_passive()
	_test_simulate_norepeat_sign()
	_test_auto_text()

	if failures.is_empty():
		print("ALL PASS")
		quit(0)
	else:
		for f in failures:
			printerr("FAIL: ", f)
		quit(1)


func check(cond: bool, label: String) -> void:
	if not cond:
		failures.append(label)


func _test_content_loaded() -> void:
	check(content.signs.size() == 12, "expected 12 signs, got %d" % content.signs.size())
	check(content.readers.size() == 13, "expected 13 readers, got %d" % content.readers.size())
	check(content.jobs.size() == 10, "expected 10 jobs, got %d" % content.jobs.size())
	check(content.sitters.size() == 9, "expected 9 sitters, got %d" % content.sitters.size())
	check(content.has_card("Pour The Tea"), "base card Pour The Tea should be loaded")
	check(content.cards_basics.size() == 7, "expected 7 basic cards, got %d" % content.cards_basics.size())


func _test_mod_pack_merged() -> void:
	check(content.LOAD_EXAMPLE_MODS, "example mods should be enabled for this test run")
	check(content.has_card("Warm The Cup"), "example mod's new card should have merged in")
	check(content.has_card("Pour The Tea"), "merging a mod pack should not drop base cards")


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


## Aries reader has fx:'opener' -> first card spoken restores +2 (on top of
## any card-level opener bonus). Card here has no opener field of its own.
func _test_simulate_reader_opener_passive() -> void:
	var ctx := _mk_run_ctx("aries")
	var why_card: Dictionary = content.get_card("Ask Them Why")  # f=3, air, no card-level opener bonus
	var fight := _mk_fight("earth", "", [why_card])   # off-element, sitter is earth not air
	var sim: Dictionary = rules.simulate(ctx, fight)
	# base 3, no el_bonus (air != earth, air != reader.el fire), +2 opener passive (n==0), no own-el +2.
	check(sim["rows"][0]["total"] == 5, "opener passive should add +2 to the first card, got %s" % sim["rows"][0]["total"])


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


func _test_auto_text() -> void:
	var name_card: Dictionary = content.get_card("Say Their Name")
	var text: String = rules.auto_text(name_card)
	check(text == "Straight through their denial.", "auto_text for a pierce card, got: %s" % text)
