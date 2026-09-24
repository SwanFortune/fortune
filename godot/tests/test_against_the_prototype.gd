## Rules.gd against the SPECIFICATION ITSELF, not a transcription of it.
##   godot --headless --path godot -s tests/test_against_the_prototype.gd
##
## CLAUDE.md says `project/` is the prototype this was ported from, that it is
## still the specification, and that where the two disagree the prototype is
## right. Until this file, the only thing checking that sentence was a handful
## of cases in tests/test_rules.gd traced by hand — a human transcription of
## what the prototype does. A transcription can be wrong, and worse, it can be
## wrong IN THE SAME DIRECTION as the port: somebody reads the JS, writes the
## GDScript, then writes the expected numbers from the GDScript they just wrote.
## This repository has shipped three tests that passed for the wrong reason and
## one of them was exactly that shape.
##
## The specification is executable. So this runs it. tests/prototype_bridge.js
## cuts simulate() and the five helpers it uses out of the .html at run time and
## runs them under node; both engines are handed the SAME randomly generated
## readings, and every field of both answers has to match.
##
## SOURCE MODE, DERIVED RATHER THAN LISTED. Rules.gd is deliberately not a
## literal port: reader traits take their size from data/base/fx.json, the white
## bonus is capped, pierce pays a `spare` when there is no wall, and the denial
## wall has drain/cap rules the prototype never had. Every one of those says in
## its own comment that 0-or-absent restores the source's behaviour exactly. So
## this empties `fx` and `denial_wall` instead of listing the source's constants
## here — a list of twelve numbers copied out of the JS would be one more copy
## that stops tracking what it copied, in the file whose whole subject is that.
## It also means this test CHECKS those comments: if "absent restores the
## source" is not true of some trait, the run disagrees and says which.
##
## WHAT IS FUZZED AND WHAT IS HELD. Cards, readers, marks, jobs, quirks, walls
## and hand order are all random. Two things are held to what a real game
## produces, and both would otherwise report divergences that no game can reach:
## a sitter always has an element (the two engines disagree about a card with no
## element sitting opposite a sitter with no element, because JS `null === null`
## is true and the port asks for a real element first), and every card carries
## `f` (the port defaults it to 0, JS would make it NaN and poison the sum).
##
## Cases come from the global generator, which Run.gd pins from PARLOUR_SEED —
## so a failing run replays with the seed tests/run_all.sh prints.
extends "res://tests/harness.gd"

## Enough that the rarer combinations (halfbest landing on a banked card,
## minthree with two cards, a wall bigger than the reading) turn up in most
## runs, and still under a second.
const CASES := 2000

## Fewer than the readings: a card's text has no ordering or carry-over, so the
## shapes run out faster.
const CARDS := 600

## Each one carries every content table across to node, so fewer than the cards.
const AUDITS := 150

## A pool and one roll each.
const PICKS := 1000

## Each one is up to thirteen steps of a whole fight.
const FIGHTS := 300

const BRIDGE := "res://tests/prototype_bridge.js"

## Every trait the engine asks `has()` about, plus nothing. Derived from what
## Rules.gd actually branches on rather than from fx.json, because a trait in
## the data that the engine ignores is not what is under test here.
const READER_FX := ["", "pierce", "opener", "closer", "steady", "switch2", "perOwn", "white", "serpent", "own3"]
const JOB_FX := ["", "opener3", "closer3", "steady3"]
const QUIRK_FX := ["", "nobonus", "mutefirst", "lasthalf", "halfown", "deadel", "norepeat", "halfbest", "minthree"]
const ELS := ["fire", "earth", "air", "water"]

var content: Node
var rules: Node

var _fx_before: Dictionary = {}
var _wall_before: Dictionary = {}
var _cases: Array = []
var _theirs: Array = []
var _skipped := ""


func setup() -> void:
	content = root.get_node("Content")
	rules = root.get_node("Rules")
	content.reload()
	# Source mode. Restored in teardown() — these are the live registries the
	# rest of the process reads.
	_fx_before = content.fx.duplicate(true)
	_wall_before = content.denial_wall.duplicate(true)
	content.fx = {}
	content.denial_wall = {}

	_cases = _invent(CASES)
	_theirs = _what_the_prototype_says(_cases)


func teardown() -> void:
	content.fx = _fx_before
	content.denial_wall = _wall_before
	content.reload()


func summary() -> String:
	if _skipped != "":
		return _skipped
	return "%d reading(s), %d card(s), the pronouns, the ladder, the content audit, the rarity roll and whole fights agreed with the prototype" % [_cases.size(), CARDS]


## THE WHOLE TEST. Both engines, the same readings, every field.
func _test_the_port_and_the_prototype_agree() -> void:
	if _skipped != "":
		print("  (skipping: %s)" % _skipped)
		done()
		return
	check(_theirs.size() == _cases.size(),
		"the bridge answered %d of %d readings" % [_theirs.size(), _cases.size()])

	var shown := 0
	for i in min(_theirs.size(), _cases.size()):
		var one: Dictionary = _cases[i]
		var mine: Dictionary = rules.simulate(one["ctx"], one["f"])
		var theirs: Dictionary = _theirs[i]
		var where := _first_disagreement(mine, theirs)
		if where == "":
			continue
		# Every mismatch is the same bug until proven otherwise, and two thousand
		# copies of it would bury the case that shows it.
		shown += 1
		if shown > 3:
			continue
		check(false, "reading %d disagrees: %s\n  the reading: %s\n  the port:   %s\n  the spec:   %s"
			% [i, where, JSON.stringify(one["f"]), JSON.stringify(mine), JSON.stringify(theirs)])
	if shown > 3:
		check(false, "%d readings of %d disagree in all; the first three are above"
			% [shown, _cases.size()])
	done()


## THE BRIDGE IS CUTTING OUT THE REAL THING. If the prototype were ever renamed,
## moved, or rewritten so the extractor found nothing, the test above would have
## nothing to compare against — and the cheapest way for that to go wrong is
## silently, with an empty answer that agrees with everything.
func _test_the_bridge_is_reading_the_specification() -> void:
	if _skipped != "":
		print("  (skipping: %s)" % _skipped)
		done()
		return
	check(not _theirs.is_empty(), "the bridge returned nothing at all")
	if _theirs.is_empty():
		done()
		return
	var moved := 0
	for r in _theirs:
		if int(r.get("gross", 0)) != 0 or not r.get("rows", []).is_empty():
			moved += 1
	check(moved > _theirs.size() / 2,
		"only %d of %d readings scored anything — the extractor is probably returning a stub"
		% [moved, _theirs.size()])
	done()


## WHAT IS PRINTED ON EVERY CARD, against the prototype's autoText().
##
## The other half of the specification, and the half a player actually reads.
## Fifty-six cards' mechanical text is generated rather than written, so a
## divergence here is not one wrong card — it is every card of that shape, on
## the face, in the hand's hint line, and on every shop and reward row.
##
## Compared in English, where I18n.t() returns its own key unchanged; the port
## routes every fragment through it so a French build does not say "Piochez
## two", which is a translation decision and not a difference in what is said.
func _test_the_printed_card_text_matches_the_prototype() -> void:
	if _skipped != "":
		print("  (skipping: %s)" % _skipped)
		done()
		return
	var cards: Array = []
	for _i in CARDS:
		cards.append(_a_printable_card())
	var theirs := _ask_the_prototype(cards.map(func(c): return {"kind": "autoText", "card": c}))
	check(theirs.size() == cards.size(), "the bridge printed %d of %d cards" % [theirs.size(), cards.size()])

	var shown := 0
	for i in min(theirs.size(), cards.size()):
		var mine: String = rules.auto_text(cards[i])
		var spec := str(theirs[i])
		if mine == spec:
			continue
		shown += 1
		if shown > 3:
			continue
		check(false, "card %d reads differently:\n  the card: %s\n  the port: '%s'\n  the spec: '%s'"
			% [i, JSON.stringify(cards[i]), mine, spec])
	if shown > 3:
		check(false, "%d cards of %d read differently; the first three are above" % [shown, cards.size()])
	done()


## THE GLYPHS ARE THE PROTOTYPE'S GLYPHS. autoText() prints them into the card
## text on both sides, so if elements.json and the prototype's EL ever disagreed
## the comparison above would fail for a reason that has nothing to do with the
## generator. Asked directly, so the answer says which it is.
func _test_the_elements_carry_the_prototypes_glyphs() -> void:
	if _skipped != "":
		print("  (skipping: %s)" % _skipped)
		done()
		return
	var answer := _ask_the_prototype([{"kind": "elements"}])
	check(answer.size() == 1, "the bridge should have handed back one element table")
	if answer.is_empty():
		done()
		return
	var theirs: Dictionary = answer[0]
	for key in theirs:
		var mine: Dictionary = content.elements.get(key, {})
		check(not mine.is_empty(), "the prototype has an element '%s' and the port does not" % key)
		check(str(mine.get("glyph", "")) == str(theirs[key].get("glyph", "")),
			"%s: the port's glyph is '%s', the prototype's is '%s'"
			% [key, mine.get("glyph", ""), theirs[key].get("glyph", "")])
	check(content.elements.size() == theirs.size(),
		"the port has %d elements and the prototype %d" % [content.elements.size(), theirs.size()])
	done()


## THE PRONOUN TABLE IS THE PROTOTYPE'S PRONOUN TABLE. Every token the
## specification fills must be in data/base/pronouns.json with the same English
## word, or every sign rule reads differently for a sitter of that pronoun.
##
## Tokens the PORT ADDED (the `e` agreement slot French needs) are derived as
## "in ours and not in theirs", and each must be EMPTY in English: the
## specification leaves an unknown {token} printed as-is, so an addition is only
## invisible to an English player while it fills to nothing.
func _test_the_pronouns_are_the_prototypes_pronouns() -> void:
	if _skipped != "":
		print("  (skipping: %s)" % _skipped)
		done()
		return
	var answer := _ask_the_prototype([{"kind": "pronouns"}])
	check(answer.size() == 1, "the bridge should have handed back one pronoun table")
	if answer.is_empty():
		done()
		return
	var theirs: Dictionary = answer[0]
	for key in theirs:
		var mine: Dictionary = content.pronouns.get(key, {})
		check(not mine.is_empty(), "the prototype has a pronoun set '%s' and the port does not" % key)
		for token in theirs[key]:
			check(str(mine.get(token, "<missing>")) == str(theirs[key][token]),
				"%s {%s}: the port says '%s', the prototype says '%s'"
				% [key, token, mine.get(token, "<missing>"), theirs[key][token]])
		for token in mine:
			if not theirs[key].has(token):
				check(str(mine[token]) == "",
					"%s {%s} is the port's own token and should fill to nothing in English, not '%s'"
					% [key, token, mine[token]])
	done()


## WHAT fill() MAKES OF A SENTENCE, against the prototype's fill().
##
## Every sign rule and slot label goes through it, so a divergence reads wrong
## on every card of the sign-select screen and every encounter. Fed the real
## sentences the content ships AND invented ones, because the shipped ones only
## ever use tokens that are spelled right: the other half of the contract is what
## happens to {typo}, to {S} with nothing after it, and to a pronoun key no set
## has — and those are what a hand-written mod gets.
func _test_sentences_fill_as_the_prototype_fills_them() -> void:
	if _skipped != "":
		print("  (skipping: %s)" % _skipped)
		done()
		return
	var spec_table: Array = _ask_the_prototype([{"kind": "pronouns"}])
	if spec_table.is_empty():
		check(false, "the bridge handed back no pronoun table to build sentences from")
		done()
		return
	# Tokens drawn from the SPECIFICATION's table, not ours: the port's additions
	# are checked above, and a sentence using one would report that on purpose.
	var tokens: Array = spec_table[0]["they"].keys()
	var keys: Array = spec_table[0].keys() + ["", "nobody"]

	var sentences: Array = []
	for sign in content.signs:
		for field in ["rule", "flavour"]:
			if str(sign.get(field, "")).contains("{"):
				sentences.append(str(sign[field]))
	check(not sentences.is_empty(), "the shipped signs should have tokens to fill — nothing real is being compared")
	for _i in 300:
		sentences.append(_a_sentence(tokens))

	var questions: Array = []
	for text in sentences:
		for key in keys:
			questions.append({"kind": "fill", "text": text, "pronoun": key})
	var theirs := _ask_the_prototype(questions)
	check(theirs.size() == questions.size(), "the bridge filled %d of %d sentences" % [theirs.size(), questions.size()])

	var shown := 0
	for i in min(theirs.size(), questions.size()):
		var q: Dictionary = questions[i]
		var mine: String = root.get_node("I18n").fill(q["text"], q["pronoun"])
		if mine == str(theirs[i]):
			continue
		shown += 1
		if shown > 3:
			continue
		check(false, "'%s' for '%s':\n  the port: '%s'\n  the spec: '%s'" % [q["text"], q["pronoun"], mine, theirs[i]])
	if shown > 3:
		check(false, "%d sentences of %d fill differently; the first three are above" % [shown, questions.size()])
	done()


## A sentence a mod author might write: real tokens, misspelt ones, a brace with
## nothing in it, one never closed, and words between them.
func _a_sentence(tokens: Array) -> String:
	var bits := ["", " ", "need", "it", ".", "{", "}", "{}", "{typo}", "{S", "{{S}}", "{ S}", "{S2}", "{é}"]
	var out := ""
	for _i in 1 + randi() % 6:
		if randf() < 0.55:
			out += "{%s}" % tokens[randi() % tokens.size()]
		else:
			out += bits[randi() % bits.size()]
	return out


## THE DIFFICULTY LADDER, against the prototype's scaleSitter().
##
## Three lines that decide how much harder every knock is than the one before —
## which is the whole curve of an evening, and CLAUDE.md records that "the ladder
## makes the game harder" was once believed and false. At level 0 the port adds
## nothing (data/base/difficulty.json's first rung is empty), so level 0 must be
## the specification exactly: every caller the content ships, plain and elite,
## at every knock of every night, and every field of the result.
func _test_callers_grow_through_the_night_as_the_prototype_grows_them() -> void:
	if _skipped != "":
		print("  (skipping: %s)" % _skipped)
		done()
		return
	var run: Node = root.get_node("Run")
	var before: Dictionary = run.state
	run.state = run.fresh("the ladder against the specification", 0)
	check(run.level_fx().is_empty(), "level 0 should add nothing, or this is not comparing the source's ladder")

	var callers: Array = []
	for s in content.sitters:
		callers.append(s)
		callers.append(run.elite_of(s, true))
	check(not callers.is_empty(), "there are no sitters to scale — nothing real is being compared")
	var questions: Array = []
	for s in callers:
		for night in 3:
			for step in 8:
				questions.append({"kind": "scaleSitter", "sitter": s, "night": night, "step": step})
	var theirs := _ask_the_prototype(questions)
	check(theirs.size() == questions.size(), "the bridge scaled %d of %d callers" % [theirs.size(), questions.size()])

	var shown := 0
	for i in min(theirs.size(), questions.size()):
		var q: Dictionary = questions[i]
		var mine: Dictionary = run.scale_sitter(q["sitter"], q["night"], q["step"])
		var where := _first_field_apart(mine, theirs[i])
		if where == "":
			continue
		shown += 1
		if shown > 3:
			continue
		check(false, "%s at night %d, knock %d: %s" % [q["sitter"].get("name", "?"), q["night"], q["step"], where])
	if shown > 3:
		check(false, "%d callers of %d grow differently; the first three are above" % [shown, questions.size()])
	run.state = before
	done()


## A WHOLE FIGHT, against the prototype's startFight() and resolveRead().
##
## The four checks above are pure functions. This is the flow that strings them
## together: the fight a knock builds (how many readings, how much energy, how
## big a hand, how thick a wall), what each reading does to it, when it is won
## or lost, and what the run is paid. The part a player lives in, and the part
## a transcription is likeliest to get subtly wrong, because nothing about one
## reading shows it.
##
## Each engine shuffles with its own dice, so a fight's deck is N copies of ONE
## random card: then the shuffle cannot matter, and hand, draw pile and discard
## are compared as SIZES. Cards go down from the front of the hand — half the
## fights through the prototype's own _lay() and the port's lay_card(), paying
## cost and taking back energy and draws, the other half placed directly so a
## fight with no energy left still reaches its verdict — and each fight is
## compared after startFight, after each line is laid, and after each reading.
func _test_a_fight_goes_as_the_prototype_says() -> void:
	if _skipped != "":
		print("  (skipping: %s)" % _skipped)
		done()
		return
	var run: Node = root.get_node("Run")
	var before: Dictionary = run.state
	var fights: Array = []
	for _i in FIGHTS:
		fights.append(_a_fight(run))
	var theirs := _ask_the_prototype(fights)
	check(theirs.size() == fights.size(), "the bridge played %d of %d fights" % [theirs.size(), fights.size()])

	var shown := 0
	var ended := 0
	for i in min(theirs.size(), fights.size()):
		var mine := _play_the_fight(run, fights[i])
		var spec: Array = theirs[i]
		if not spec.is_empty() and str(spec[-1].get("res", "")) != "":
			ended += 1
		var where := ""
		if mine.size() != spec.size():
			where = "the port took %d steps, the prototype %d" % [mine.size(), spec.size()]
		else:
			for step in mine.size():
				where = _first_field_apart(mine[step], spec[step])
				if where != "":
					where = "step %d: %s" % [step, where]
					break
		if where == "":
			continue
		shown += 1
		if shown > 3:
			continue
		var o: Dictionary = fights[i]["o"]
		check(false, "fight %d (%s, %s, sign %s, reader %s) went differently — %s"
			% [i, o["sitter"].get("name", "?"), o["kind"], o["quirk"].get("fx", ""),
				fights[i]["state"]["reader"].get("fx", ""), where])
	if shown > 3:
		check(false, "%d fights of %d went differently; the first three are above" % [shown, fights.size()])
	check(ended > fights.size() / 2,
		"only %d of %d fights reached a verdict — the win/lose/pay-out half is barely being compared" % [ended, fights.size()])
	run.state = before
	done()


## The same fight on the port, reported in the same words as the bridge.
func _play_the_fight(run: Node, one: Dictionary) -> Array:
	var st: Dictionary = one["state"].duplicate(true)
	run.state = run.fresh("a fight against the specification", 0)
	for key in ["reader", "marks", "deck", "coin", "faith", "mended", "seen"]:
		run.state[key] = st[key]
	run.state["serp_el"] = st["serpEl"]
	var seen: Array = []
	run.start_fight(one["o"].duplicate(true))
	seen.append(_look_at(run))
	for k in one["lays"]:
		if not run.state.get("res", {}).is_empty():
			break
		if one["viaLay"]:
			for _j in int(k):
				if run.state["f"]["hand"].is_empty():
					break
				run.lay_card(run.state["f"]["hand"][0]["uid"])
		else:
			var f: Dictionary = run.state["f"]
			var take: int = mini(int(k), f["hand"].size())
			f["cross"] = f["hand"].slice(0, take)
			f["hand"] = f["hand"].slice(take)
		seen.append(_look_at(run))
		run.resolve_read(rules.simulate(run.run_ctx(), run.state["f"]))
		seen.append(_look_at(run))
	return seen


func _look_at(run: Node) -> Dictionary:
	var st: Dictionary = run.state
	var f: Dictionary = st["f"]
	return {
		"hp": f["hp"], "faith": f["faith"], "coin": f["coin"], "turn": f["turn"], "turns": f["turns"],
		"denial": f["denial"], "denialUp": f["denialUp"], "energy": f["energy"], "energyMax": f["energyMax"],
		"handMax": f["handMax"], "swept": f["swept"], "hand": f["hand"].size(), "draw": f["draw"].size(),
		"disc": f["disc"].size(), "gone": f["gone"].size(), "taken": f["taken"] != null, "max": f["max"],
		"cross": f["cross"].size(),
		"runCoin": st["coin"], "runFaith": st["faith"], "mended": st["mended"], "marks": st["marks"].size(),
		"serpEl": str(st.get("serp_el", "")), "res": str(st.get("res", {}).get("kind", "")), "seen": st["seen"].size(),
	}


## A knock: a real sitter (scaled for a random hour, elite a third of the time,
## the boss now and then), a real sign, a real reader wearing up to three real
## marks, and a deck of one card.
func _a_fight(run: Node) -> Dictionary:
	run.state = run.fresh("inventing a fight", 0)
	var kind := "sitter"
	var sitter: Dictionary
	if randf() < 0.08 and not content.boss.is_empty():
		kind = "boss"
		sitter = content.boss.duplicate(true)
	else:
		sitter = content.sitters[randi() % content.sitters.size()]
		if randf() < 0.33:
			kind = "elite"
			sitter = run.elite_of(sitter, true)
		sitter = run.scale_sitter(sitter, randi() % 3, randi() % 8)
	var marks: Array = []
	var pool: Array = content.marks + content.relics
	for _m in randi() % 4:
		marks.append(pool[randi() % pool.size()])
	var card := _a_card(0)
	if randf() < 0.2:
		card["exhaust"] = true
	# What laying reads: a cost, and the two things a card gives back at once.
	card["cost"] = randi() % 3
	if randf() < 0.25:
		card["energy"] = randi() % 3
	if randf() < 0.25:
		card["draw"] = randi() % 3
	var deck: Array = []
	for n in 5 + randi() % 16:
		var c: Dictionary = card.duplicate(true)
		c["uid"] = "u%d" % n
		deck.append(c)
	var lays: Array = []
	for _r in 12:
		lays.append(randi() % 6)
	return {
		"kind": "fight",
		"o": {"kind": kind, "sitter": sitter, "quirk": content.signs[randi() % content.signs.size()]},
		"state": {"reader": content.readers[randi() % content.readers.size()], "marks": marks, "deck": deck,
			"coin": randi() % 40, "faith": randi() % 200, "mended": randi() % 6, "seen": [], "serpEl": ""},
		"props": {"energy": run.cfg_energy(), "handSize": run.cfg_hand()},
		"lays": lays,
		# Half the fights put their cards down through _lay()/lay_card(), the
		# other half straight from the hand, so a fight with no energy left
		# still reaches its verdict.
		"viaLay": randf() < 0.5,
		"JOBS": content.jobs, "RELICS": content.relics, "DENIAL_SHIELD": content.denial_shield,
	}


## WHY shieldNext IS LEFT OUT OF THE READING COMPARISON, checked rather than
## asserted: the prototype must still never READ it. The day it does — a preview
## comes back, or resolveRead() starts taking it — the field means something
## again and has to be compared.
func _test_the_prototype_still_never_reads_shieldNext() -> void:
	var spec := FileAccess.get_file_as_string(ProjectSettings.globalize_path(BRIDGE).get_base_dir()
		.path_join("../../project/Parlour v23.dc.html"))
	check(spec.length() > 0, "could not open the specification to look")
	var writes := RegEx.create_from_string("shieldNext\\s*:").search_all(spec).size()
	var every := RegEx.create_from_string("shieldNext").search_all(spec).size()
	check(writes > 0, "the prototype no longer writes shieldNext at all — this check is looking at the wrong thing")
	check(every == writes,
		"the prototype now READS shieldNext (%d mention(s), %d of them writes) — compare it again in _first_disagreement()"
		% [every, writes])
	done()


## WHICH CARD A REWARD OR THE SHOP OFFERS, against the prototype's weighted().
##
## The rarity weighting decides what a player is ever shown. Both engines draw
## from their own dice, so the port's weighted() is split into weighted_at(pool,
## u) and the prototype's runs with Math.random() pinned to the same u: then they
## must pick the same card, every time. Pools are drawn from the cards the game
## can offer, plus what a mod might write — no rarity, "basic", a rarity nobody
## defined, a null — because the base game names a known rarity on every
## offerable card and would never show the difference.
func _test_rewards_are_weighted_as_the_prototype_weighs_them() -> void:
	if _skipped != "":
		print("  (skipping: %s)" % _skipped)
		done()
		return
	var run: Node = root.get_node("Run")
	var offerable: Array = content.cards_minor + content.cards_arcana
	var questions: Array = []
	for _i in PICKS:
		var pool: Array = []
		for _c in 1 + randi() % 8:
			var c: Dictionary = offerable[randi() % offerable.size()].duplicate(true)
			# The same card twice is equal as a Dictionary, and find() would name
			# the first copy whichever one was picked.
			c["_at"] = pool.size()
			match randi() % 6:
				0:
					c.erase("r")
				1:
					c["r"] = "basic"
				2:
					c["r"] = ["legendary", null, ""][randi() % 3]
			pool.append(c)
		var u: float = [0.0, 0.999999, randf()][randi() % 3]
		# A roll that lands EXACTLY on the line between two cards, which is the
		# only place `roll <= 0` and `roll < 0` part company. Aimed with the
		# port's weights: this chooses the input, the prototype still judges it.
		if randf() < 0.3:
			var total := 0.0
			for c in pool:
				total += run.rarity_weight(c)
			var upto := 0.0
			for j in 1 + randi() % pool.size():
				upto += run.rarity_weight(pool[j])
			u = upto / total
		questions.append({"kind": "weighted", "pool": pool, "u": u})
	var theirs := _ask_the_prototype(questions)
	check(theirs.size() == questions.size(), "the bridge rolled %d of %d pools" % [theirs.size(), questions.size()])

	var shown := 0
	for i in min(theirs.size(), questions.size()):
		var q: Dictionary = questions[i]
		var picked = run.weighted_at(q["pool"], q["u"])
		var mine: int = q["pool"].find(picked) if picked != null else -1
		if mine == int(theirs[i]):
			continue
		shown += 1
		if shown > 3:
			continue
		check(false, "rolling %s over rarities %s: the port picks #%d, the prototype #%d"
			% [q["u"], JSON.stringify(q["pool"].map(func(c): return c.get("r", "<none>"))), mine, int(theirs[i])])
	if shown > 3:
		check(false, "%d rolls of %d picked differently; the first three are above" % [shown, questions.size()])
	done()


## THE CONTENT AUDIT, against the prototype's fxAudit().
##
## This is the check a mod author is told to run (tests/test_content_audit.gd)
## after writing a pack, so what it lets through is what reaches a player. Fed
## the shipped tables with a few records broken on purpose each time — an fx that
## does not exist, one borrowed from the wrong kind of record, an elemental one
## with its element missing, empty, or null, an fx that is null — and the two
## lists of complaints must be the same list, in the same order, word for word.
func _test_the_content_audit_complains_as_the_prototype_does() -> void:
	if _skipped != "":
		print("  (skipping: %s)" % _skipped)
		done()
		return
	var shipped := {
		"readers": content.readers, "relics": content.relics, "marks": content.marks,
		"signs": content.signs, "jobs": content.jobs, "fx": content.fx,
	}
	# The shipped fx registry, not the emptied one setup() leaves for simulate().
	shipped["fx"] = _fx_before

	var worlds: Array = []
	var questions: Array = []
	for _i in AUDITS:
		var w := _a_broken_world(shipped)
		worlds.append(w)
		questions.append({"kind": "fxAudit", "FX": w["fx"], "READERS": w["readers"], "RELICS": w["relics"],
			"MARKS": w["marks"], "SIGNS": w["signs"], "JOBS": w["jobs"]})
	var theirs := _ask_the_prototype(questions)
	check(theirs.size() == worlds.size(), "the bridge audited %d of %d worlds" % [theirs.size(), worlds.size()])

	var complained := 0
	var shown := 0
	for i in min(theirs.size(), worlds.size()):
		var w: Dictionary = worlds[i]
		content.readers = w["readers"]
		content.relics = w["relics"]
		content.marks = w["marks"]
		content.signs = w["signs"]
		content.jobs = w["jobs"]
		content.fx = w["fx"]
		var mine: Array = Array(rules.fx_audit())
		var spec: Array = theirs[i]
		if not spec.is_empty():
			complained += 1
		if mine == spec:
			continue
		shown += 1
		if shown > 3:
			continue
		check(false, "world %d is audited differently:\n  the port: %s\n  the spec: %s"
			% [i, JSON.stringify(mine), JSON.stringify(spec)])
	for key in shipped:
		content.set(key, shipped[key])
	content.fx = {}
	if shown > 3:
		check(false, "%d worlds of %d are audited differently; the first three are above" % [shown, worlds.size()])
	# A breaker that never breaks anything compares two empty lists forever.
	check(complained > worlds.size() / 2,
		"only %d of %d broken worlds drew a complaint from the prototype — the breaker is not breaking" % [complained, worlds.size()])
	done()


## The shipped content with one to three records broken. The ways to break one
## are the ways the audit knows about, plus the values JavaScript and GDScript
## disagree about: an empty string and a null.
func _a_broken_world(shipped: Dictionary) -> Dictionary:
	var w: Dictionary = shipped.duplicate(true)
	var fx_keys: Array = w["fx"].keys().filter(func(k): return not str(k).begins_with("_"))
	var tables := ["readers", "relics", "marks", "signs", "jobs"]
	for _n in 1 + randi() % 3:
		var table: String = tables[randi() % tables.size()]
		var rec: Dictionary
		if table == "jobs":
			var keys: Array = w["jobs"].keys()
			if keys.is_empty():
				continue
			rec = w["jobs"][keys[randi() % keys.size()]]
		else:
			if w[table].is_empty():
				continue
			rec = w[table][randi() % w[table].size()]
		match randi() % 4:
			0:
				rec["fx"] = fx_keys[randi() % fx_keys.size()]
			1:
				rec["fx"] = ["typo", "", null][randi() % 3]
			2:
				rec.erase("fx")
			_:
				# Elemental fx are the only ones that read `el`/`dead`, and only on
				# the kind of record they belong to — anywhere else the audit stops
				# at "belongs to" and never looks. So aim one at its own kind.
				var kind: String = {"signs": "sign", "jobs": "job"}.get(table, "trait")
				var elemental: Array = fx_keys.filter(func(k):
					return w["fx"][k].get("needsEl", false) and w["fx"][k].get("on", "") == kind)
				if not elemental.is_empty():
					rec["fx"] = elemental[randi() % elemental.size()]
		for field in ["el", "dead"]:
			match randi() % 5:
				0:
					rec.erase(field)
				1:
					rec[field] = ""
				2:
					rec[field] = null
				3:
					rec[field] = ELS[randi() % ELS.size()]
	return w


## Every field the specification returns, in the port's answer and equal to it.
## Numbers as numbers, and anything else as canonical JSON so a nested elite
## twist is compared whole.
func _first_field_apart(mine: Dictionary, theirs: Dictionary) -> String:
	for key in theirs:
		if not mine.has(key):
			return "the port has no '%s'" % key
		var a = mine[key]
		var b = theirs[key]
		if (a is int or a is float) and (b is int or b is float):
			if float(a) != float(b):
				return "%s: the port says %s, the prototype says %s" % [key, a, b]
		elif _canonical(a) != _canonical(b):
			return "%s: the port says %s, the prototype says %s" % [key, JSON.stringify(a), JSON.stringify(b)]
	return ""


## Sent through JSON once, so the port's int 2 and the bridge's float 2.0 inside a
## nested record read the same — that difference is the transport, not the game.
func _canonical(v) -> String:
	return JSON.stringify(JSON.parse_string(JSON.stringify(v)), "", true)


## One card, for its PRINTED text. Every field autoText() reads, and zeros on
## purpose: JS omits a sentence for a falsey number and the port was asking
## whether the key is present, which are the same thing until a card carries 0.
func _a_printable_card() -> Dictionary:
	var c := {}
	var roll := randf()
	if roll < 0.15:
		c["wild"] = true
	elif roll < 0.30:
		c["chroma"] = true
	elif roll < 0.40:
		c["any"] = true
	c["el"] = ELS[randi() % ELS.size()]
	for field in ["bonusFlat", "opener", "closer", "solo", "perLaid", "next", "energy", "draw", "coin", "turn"]:
		if randf() < 0.22:
			c[field] = randi() % 4          # 0 included, and that is the point
	if randf() < 0.25:
		c["follows"] = "same" if randf() < 0.5 else "turn"
		c["bonus"] = randi() % 5
	if randf() < 0.15:
		c["perEl"] = ELS[randi() % ELS.size()]
		c["perAmt"] = randi() % 4
	for flag in ["bank", "pierce", "exhaust"]:
		if randf() < 0.18:
			c[flag] = true
	return c


# ── the two engines ─────────────────────────────────────────────────────

func _what_the_prototype_says(cases: Array) -> Array:
	var for_them: Array = []
	for one in cases:
		for_them.append({"state": one["state"], "f": one["f"]})
	return _ask_the_prototype(for_them)


func _ask_the_prototype(questions: Array) -> Array:
	var here := ProjectSettings.globalize_path("user://")
	var cases_path := here.path_join("prototype_cases.json")
	var out_path := here.path_join("prototype_out.json")

	var f := FileAccess.open("user://prototype_cases.json", FileAccess.WRITE)
	# sort_keys OFF. Godot sorts by default, and the prototype walks a table like
	# JOBS in the order its keys arrive — so a sorted transport reorders what the
	# spec reports and blames the port for it.
	# full_precision ON. Godot writes a float to fourteen digits by default, so a
	# roll aimed exactly at the line between two cards arrived a hair off it and
	# the prototype picked the neighbour.
	f.store_string(JSON.stringify(questions, "", false, true))
	f.close()

	# IS NODE HERE AT ALL — asked separately, and this is not a detail. The first
	# version had one path for both answers, so renaming the function the
	# extractor looks for made the whole file SKIP AND REPORT ALL PASS. A test
	# that cannot find the thing it checks must fail, not excuse itself; only a
	# missing interpreter is a reason to stand down, because this needs a second
	# language to run at all and refusing the whole suite over that is worse.
	var version: Array = []
	if OS.execute("/usr/bin/env", ["node", "--version"], version, true) != 0:
		_skipped = "node is not installed here, so the prototype cannot be run"
		return []

	var said: Array = []
	var code := OS.execute("/usr/bin/env",
		["node", ProjectSettings.globalize_path(BRIDGE), cases_path, out_path], said, true)
	if code != 0:
		# Node works and the bridge did not. Something is wrong with the bridge or
		# with the specification it reads, and either way nothing is being checked.
		failures.append("the bridge could not run the specification:\n%s" % "\n".join(said).strip_edges())
		return []
	var body := FileAccess.get_file_as_string("user://prototype_out.json")
	DirAccess.remove_absolute("user://prototype_cases.json")
	DirAccess.remove_absolute("user://prototype_out.json")
	var parsed = JSON.parse_string(body)
	if not (parsed is Array):
		failures.append("the bridge wrote something that is not a list of readings")
		return []
	return parsed


## The first field where the two answers differ, or "" when they agree.
##
## `shieldNext` is NOT compared. The prototype's simulate() writes it and
## nothing in the prototype reads it; the wall a sitter actually has next reading
## is what resolveRead() does, and _test_a_fight_goes_as_the_prototype_says()
## compares THAT. Comparing the dead field once made the port follow it, and
## pierce compounded across every fight — see Rules.next_wall().
## _test_the_prototype_still_never_reads_shieldNext() says if that ever changes.
##
## `halveNote` is compared as PRESENT OR ABSENT, not as text: the prototype
## builds its wording from the sitter's pronoun and the port keeps the wording
## in the locale, which is a translation decision rather than arithmetic.
func _first_disagreement(mine: Dictionary, theirs: Dictionary) -> String:
	for field in ["gross", "pierced", "denial", "absorbed", "applied", "bank", "over",
			"hpAfter", "extraTurns", "coin"]:
		if int(mine.get(field, 0)) != int(theirs.get(field, 0)):
			return "%s: the port says %s, the prototype says %s" % [field, mine.get(field), theirs.get(field)]
	if (mine.get("halveNote") == null) != (theirs.get("halveNote") == null):
		return "halveNote: the port says %s, the prototype says %s" % [mine.get("halveNote"), theirs.get("halveNote")]

	var my_rows: Array = mine.get("rows", [])
	var their_rows: Array = theirs.get("rows", [])
	if my_rows.size() != their_rows.size():
		return "rows: the port laid out %d, the prototype %d" % [my_rows.size(), their_rows.size()]
	for i in my_rows.size():
		var a: Dictionary = my_rows[i]
		var b: Dictionary = their_rows[i]
		for field in ["i", "total"]:
			if int(a.get(field, 0)) != int(b.get(field, 0)):
				return "row %d %s: the port says %s, the prototype says %s" % [i, field, a.get(field), b.get(field)]
		for field in ["bank", "pierce"]:
			if bool(a.get(field, false)) != bool(b.get(field, false)):
				return "row %d %s: the port says %s, the prototype says %s" % [i, field, a.get(field), b.get(field)]
		# An element the prototype never set comes back as null; the port says "".
		for field in ["el", "link", "note", "name"]:
			var mine_s := str(a.get(field, "")) if a.get(field) != null else ""
			var their_s := str(b.get(field, "")) if b.get(field) != null else ""
			if mine_s != their_s:
				return "row %d %s: the port says '%s', the prototype says '%s'" % [i, field, mine_s, their_s]
	return ""


# ── inventing readings ──────────────────────────────────────────────────

func _invent(how_many: int) -> Array:
	var out: Array = []
	for _i in how_many:
		var reader := {"fx": READER_FX[randi() % READER_FX.size()], "el": ELS[randi() % ELS.size()]}
		var marks: Array = []
		for _m in randi() % 3:
			if randf() < 0.5:
				marks.append({"fx": "el", "el": ELS[randi() % ELS.size()]})
			else:
				marks.append({"fx": READER_FX[randi() % READER_FX.size()]})
		var serp_el: String = ELS[randi() % ELS.size()] if randf() < 0.3 else ""

		var quirk := {"fx": QUIRK_FX[randi() % QUIRK_FX.size()]}
		if quirk["fx"] == "deadel":
			quirk["dead"] = ELS[randi() % ELS.size()]

		var cross: Array = []
		for _c in randi() % 7:
			cross.append(_a_card(cross.size()))
		var sitter_el: String = ELS[randi() % ELS.size()]
		var wall := randi() % 9
		var f := {
			"quirk": quirk,
			"cross": cross,
			"hp": randi() % 20,
			"max": 10 + randi() % 40,
			"denial": wall,
			"denialUp": randi() % 4,
			"el": sitter_el,
			"job": {"fx": JOB_FX[randi() % JOB_FX.size()]},
			"sitter": {"p": "they", "denial": wall, "el": sitter_el},
		}
		out.append({
			"f": f,
			# The same thing said two ways: the prototype keeps it on this.state,
			# the port passes it in.
			"state": {"reader": reader, "marks": marks, "serpEl": serp_el},
			"ctx": {"reader": reader, "marks": marks, "serp_el": serp_el},
		})
	return out


## One laid card. Every field the engine reads, present about as often as the
## base content has it — a fuzzer that gave every card every field would spend
## two thousand readings on a card that exists nowhere.
func _a_card(n: int) -> Dictionary:
	var c := {"n": "c%d" % n, "f": randi() % 9}
	var roll := randf()
	if roll < 0.12:
		c["neutral"] = true
	elif roll < 0.18:
		c["chroma"] = true
	elif roll < 0.24:
		c["wild"] = true
	else:
		c["el"] = ELS[randi() % ELS.size()]
	if randf() < 0.18:
		c["follows"] = "same" if randf() < 0.5 else "turn"
		c["bonus"] = 1 + randi() % 5
	if randf() < 0.10:
		c["perEl"] = ELS[randi() % ELS.size()]
		c["perAmt"] = 1 + randi() % 3
	if randf() < 0.08:
		c["bonusFlat"] = 1 + randi() % 4
	if randf() < 0.08:
		c["solo"] = 1 + randi() % 6
	if randf() < 0.08:
		c["perLaid"] = 1 + randi() % 3
	if randf() < 0.10:
		c["opener"] = 1 + randi() % 4
	if randf() < 0.10:
		c["closer"] = 1 + randi() % 4
	if randf() < 0.08:
		c["next"] = 1 + randi() % 4
	if randf() < 0.06:
		c["turn"] = 1
	if randf() < 0.06:
		c["coin"] = 1 + randi() % 5
	if randf() < 0.10:
		c["bank"] = true
	if randf() < 0.10:
		c["pierce"] = true
	return c
