## Autoload. The run/game state machine — a port of the Component class's
## state-mutating methods in Parlour v23.dc.html (fresh(), startFight(),
## beginTurn(), resolveRead(), win()/lose(), advance(), endRun(), the reward/
## shop/event builders, takePick()). UI scenes read `Run.state` (a plain
## Dictionary mirroring the source's `this.state`) and call these methods;
## they never touch Rules or Content directly for game-flow decisions.
##
## DISPLAY-STRING CONVENTION. This file is game logic and must not compose
## finished, human-facing prose — doing so was an i18n dead end (~30 strings
## that could never be translated) as well as a layering violation. Instead,
## any user-facing text emitted into `state` is one of:
##   - a plain String, which is a translation key (the English source text
##     itself, per I18n.t's source-as-key scheme);
##   - an Array [format_key, arg, ...], for text that interpolates data —
##     the key is translated first, then "%" applied to the args.
## The display layer resolves both through UIKit.tr_line(). Numbers and
## names stay unlocalized on purpose; only the words around them are keys.
##
## Deliberately NOT ported: the letter-by-letter "mumble" reveal animation
## (tick()/resolveRead's setTimeout chain) and card-table dev tooling (AUDIT/
## BALANCE/HANDOFF tabs, simFight/simSweep). See docs/PORTING_NOTES.md.
extends Node

signal state_changed

## Baseline energy per reading and cards dealt per hand, before any
## reader/relic/job/sign modifier. These mirror the prototype's own cfg()
## props (energy: 3, handSize: 5) and are player-adjustable in Settings —
## the source exposed them as tweakable knobs too, so treating them as
## settings rather than constants matches its intent.
static func cfg_energy() -> int:
	return int(Settings.get_value("start_energy"))


static func cfg_hand() -> int:
	return int(Settings.get_value("hand_size"))

var state: Dictionary = {}


func _ready() -> void:
	state = fresh()


# ── setup ────────────────────────────────────────────────────────────────

## `seed_text` is what the player typed on the sign screen, or "" for a new one.
## Seeded FIRST, before the deck is built or the night is planned, or the seed
## would govern everything except the two things a player would notice.
func fresh(seed_text: String = "", level: int = 0) -> Dictionary:
	var reader: Dictionary = Content.readers[0]
	var seed_used := _seed_from(seed_text)
	var st := {
		"screen": "sign", "night": 0, "step": 0, "coin": 5, "faith": 0, "mended": 0,
		"reader": reader, "deck": [], "marks": [], "seen": [], "seq": 0,
		"serp_el": "", "options": [], "f": {}, "pick": {}, "res": {}, "over": {}, "sel": "",
		# The night's shape, and what each hour of it turned into. See
		# make_plan() and the agenda on the map screen.
		"plan": [], "log": [],
		"seed": seed_used, "level": level,
		# Who came, and what became of them. Written by _close_the_hour().
		"ledger": [],
	}
	# level_fx() reads state["level"], and this state is not live yet.
	var was := state
	state = st
	st["coin"] = maxi(0, int(st["coin"]) - int(level_fx().get("coin_sub", 0)))
	state = was
	st["deck"] = base_deck(reader)
	state = st
	st["plan"] = make_plan(0)
	st["log"] = []
	st["options"] = make_options(0, 0, [], st["plan"])
	return st


## Difficulty keys a higher rung REPLACES rather than adds to — a chance and a
## multiplier, where "and also" would mean nothing.
const SET_OUTRIGHT := ["elite_chance", "max_mul"]


## THE LADDER. Everything the chosen difficulty level does, folded into one
## dictionary — every level at or below the chosen one, so level 3 carries its
## own line and the two under it.
##
## Cumulative rather than a set of independent presets because that is how a
## ladder reads: "and also" at each rung, not "instead". See
## data/base/difficulty.json for the levels and what each key does.
func level_fx() -> Dictionary:
	var want: int = int(state.get("level", 0))
	var out := {}
	for rung in Content.difficulty:
		if int(rung.get("n", 0)) > want:
			continue
		for key in rung.get("fx", {}):
			# Later rungs win outright on a key both name, and add up on the ones
			# that are amounts. WHICH IS WHICH IS LISTED, not inferred from the
			# value: JSON has no integer type, so 2 and 0.85 both arrive as floats
			# and a type test would fold 1.1 down to 1.
			if key in SET_OUTRIGHT:
				out[key] = float(rung["fx"][key])
			else:
				out[key] = int(out.get(key, 0)) + int(rung["fx"][key])
	return out


## Which rungs the player may choose, by how many runs they have finished.
## A level above the highest they have reached is SHOWN and refused rather than
## hidden — a ladder you cannot see is not something to climb.
func level_open(rung: Dictionary) -> bool:
	return int(Profile.get_stat("runs_finished")) >= int(rung.get("unlock_at", 0))


func base_deck(reader: Dictionary) -> Array:
	var names: Array = []
	for c in Content.cards_basics:
		names.append(c["n"])
	for n in reader.get("deck", []):
		names.append(n)
	var deck: Array = []
	for n in names:
		var c: Dictionary = Content.get_card(n).duplicate(true)
		c["uid"] = uid()
		deck.append(c)
	return deck


func run_ctx() -> Dictionary:
	return {"reader": state["reader"], "marks": state["marks"], "serp_el": state.get("serp_el", "")}


func has(fx: String) -> bool:
	return Rules.has(run_ctx(), fx)


func pick_reader(i: int) -> void:
	var reader: Dictionary = Content.readers[i]
	state["reader"] = reader
	state["serp_el"] = reader.get("el", "")
	state["deck"] = base_deck(reader)
	state["screen"] = "pick"
	state["pick"] = build_gift(reader)
	state_changed.emit()


func build_gift(reader: Dictionary) -> Dictionary:
	var neigh: Array = Content.neighbors.get(reader["el"], [])
	var opts: Array = []
	if neigh.size() > 0:
		var ca = minor_of_el(neigh[0], [])
		if ca != null:
			opts.append({"card": ca, "kind": "", "cost": 0})
	if neigh.size() > 1:
		var cb = minor_of_el(neigh[1], [])
		if cb != null:
			opts.append({"card": cb, "kind": "", "cost": 0})
	return {
		"head": "", "title": "Borrowed from what comes before, or after…", "kind": "gift",
		"body": "Ten cards. Seven of them are only the basic decency. Two are from deep inside you, your sign. This is the tenth.",
		"opts": opts, "skippable": false,
	}


# ── small helpers ───────────────────────────────────────────────────────

## THE EVENING'S SEED. Every roll a run makes comes out of this one generator,
## so a seed IS a run: the same eight hours, the same callers, the same signs,
## the same shuffles.
##
## Every roll in this file must go through `rng`, never through the global RNG —
## which is left alone deliberately, because Audio's pitch jitter uses it and a
## run must not sound different for having been re-seeded.
##
## HONEST LIMIT: a seed reproduces a run FROM THE START. It does not survive a
## reload mid-run — the generator's position is not saved, only the seed — so a
## resumed run diverges from that point. Saving the position would mean writing
## it on every roll, and the value here is "play this run again", not "prove
## this save was untampered".
var rng := RandomNumberGenerator.new()


## Points the generator at `text`, and returns what it settled on. An empty
## string means "pick one", which is the ordinary case and is what keeps the
## field on the sign screen a convenience rather than a chore.
##
## The fresh seed comes from the GLOBAL randi(), not from rng — rng has not been
## seeded yet at that moment, so asking it would hand out the same "random" seed
## on every launch of the game, forever.
func _seed_from(text: String) -> String:
	var clean := text.strip_edges()
	if clean == "":
		clean = str(randi() % 100000)
	# hash() over the text, so "grandmother" and "41822" are both usable seeds
	# and neither is special.
	rng.seed = clean.hash()
	return clean


func uid() -> String:
	state["seq"] = int(state.get("seq", 0)) + 1
	return "c%d%d" % [state["seq"], rng.randi() % 100000]


func pick_rand(a: Array):
	return a[rng.randi() % a.size()]


## Fisher-Yates against the run's own generator. Array.shuffle() uses Godot's
## global RNG, which is exactly the one thing a seeded run must not touch — and
## it is the single most consequential roll in the game, since it is the deck.
func shuffle(a: Array) -> Array:
	var b := a.duplicate()
	for i in range(b.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = b[i]
		b[i] = b[j]
		b[j] = tmp
	return b


# ── map / knocks ────────────────────────────────────────────────────────

func scale_sitter(s: Dictionary, night: int, step: int) -> Dictionary:
	var prog := night * 8 + step
	var k := 1.0 + prog * 0.045
	var out := s.duplicate(true)
	var harder := level_fx()
	# The one difficulty key every encounter feels. A wall only exists for the two
	# signs that raise one, so `denial_add` below is a spike against those and
	# nothing anywhere else — see data/base/difficulty.json.
	out["max"] = int(round(s["max"] * k * float(harder.get("max_mul", 1.0))))
	out["denial"] = int(s["denial"]) + int(prog / 5) + int(harder.get("denial_add", 0))
	# Never below one reading: a level that made an encounter unplayable would
	# not be a harder game, it would be a broken one.
	out["turns"] = maxi(1, int(s["turns"]) - int(harder.get("turns_sub", 0)))
	return out


## THE EVENING'S HOURS. Eight knocks, half-hourly, from when it gets dark to
## when a village stops calling on people.
##
## Written out rather than computed so they can be edited: this is the one part
## of the run's shape a player reads as a clock rather than as a number, and
## "22:30" carries more than "knock 6 of 8".
const HOURS := ["20:00", "20:30", "21:00", "21:30", "22:00", "22:30", "23:00", "23:30"]


## What is on offer at each hour of a night, decided at the START of the night
## rather than at each knock — which is the whole point.
##
## The rolls are exactly make_options()' own — an elite from the third knock,
## the apothecary from the second, the last hour a single caller with no way
## out. ALL THAT MOVED IS WHEN THEY HAPPEN: decided in advance, they can be
## shown in advance, which is what the agenda on the map draws.
##
## Deliberately holds STRINGS AND NOTHING ELSE. A plan carrying sitter or sign
## objects would be a third place Save.gd has to re-resolve content on load
## (see its _relive_* helpers), and a stale copy of a sitter is exactly the kind
## of bug that shows up three nights into somebody's run.
func make_plan(night: int) -> Array:
	var plan: Array = []
	for step in HOURS.size():
		var is_last := step == 7
		var offers: Array = []
		if night == 2 and is_last:
			offers = ["boss"]
		elif is_last:
			offers = ["sitter"]
		else:
			offers = ["sitter"]
			var elite_at: float = float(level_fx().get("elite_chance", 0.55))
			offers.append("elite" if step >= 2 and rng.randf() < elite_at else "sitter")
			if step >= 1 and rng.randf() < 0.45:
				offers.append("shop")
			if offers.size() < 4 and rng.randf() < 0.55:
				offers.append("event")
			# A Minitel code can arm a secret event. Offered rarely and only once
			# the code has been dialled — armed_events() is empty otherwise, so a
			# player who has not found the code can never be shown one by
			# accident. Rolled here so the agenda can promise it and then keep
			# the promise.
			if not Minitel.armed_events().is_empty() and offers.size() < 4 and rng.randf() < 0.2:
				offers.append("secret")
		plan.append({"at": HOURS[step], "offers": offers})
	return plan


## The actual callers and breaks for one hour, built from that hour's plan.
## Nobody knocks twice in one night, which is why the pool is filtered by
## `seen` here rather than when the plan was made — the plan is a shape, and
## who fills it depends on how the night has gone.
func make_options(night: int, step: int, seen: Array, plan: Array = []) -> Array:
	var slot: Dictionary = plan[step] if step < plan.size() else {}
	var offers: Array = slot.get("offers", [])
	if offers.is_empty():
		# No plan (an old save, or a caller that predates one): fall back to the
		# shape this hour would have had, minus the dice.
		offers = ["boss"] if night == 2 and step == 7 else (["sitter"] if step == 7 else ["sitter", "sitter"])
	if offers.has("boss"):
		return [{"kind": "boss", "sitter": Content.boss.duplicate(true), "quirk": pick_rand(Content.signs)}]

	var pool: Array = []
	for s in Content.sitters:
		if not seen.has(s["name"]):
			pool.append(s)
	if pool.is_empty():
		pool = Content.sitters.duplicate()
	pool = shuffle(pool)

	var mk = func(s: Dictionary, elite: bool) -> Dictionary:
		return {"kind": "elite" if elite else "sitter", "sitter": scale_sitter(elite_of(s, elite), night, step), "quirk": pick_rand(Content.signs)}

	var opts: Array = []
	var next_caller := 0
	for offer: String in offers:
		match offer:
			"sitter", "elite":
				var who: Dictionary = pool[next_caller % pool.size()]
				next_caller += 1
				opts.append(mk.call(who, offer == "elite"))
			"shop":
				opts.append({"kind": "break", "rest": Content.shop})
			"event":
				opts.append({"kind": "break", "rest": pick_rand(ordinary_events())})
			"secret":
				var armed: Array = Minitel.armed_events()
				# The code can be un-dialled between the plan and the hour only
				# by a reload onto a different profile; nothing to show then.
				if not armed.is_empty():
					opts.append({"kind": "break", "rest": pick_rand(armed)})
	return opts.slice(0, min(4, opts.size()))


## Events eligible for the ordinary random pool: everything not flagged
## `secret`. Without this filter a secret event would simply turn up on its
## own, and the code that arms it would be pointless.
func ordinary_events() -> Array:
	var out: Array = []
	for e in Content.events:
		if not bool(e.get("secret", false)):
			out.append(e)
	return out if not out.is_empty() else Content.events


func elite_of(s: Dictionary, elite: bool) -> Dictionary:
	if not elite:
		return s
	var tw: Dictionary = pick_rand(Content.elite_twists)
	var out := s.duplicate(true)
	out["elite"] = true
	out["twist"] = tw
	out["max"] = int(round(s["max"] * float(tw.get("maxMul", 1.35))))
	out["denial"] = int(s["denial"]) + 2 + int(tw.get("denial", 0))
	out["shieldMul"] = tw.get("shieldMul", 1)
	out["turns"] = int(s["turns"]) + 1 + int(tw.get("turns", 0))
	return out


func roll_relic():
	var pool: Array = []
	for r in Content.relics:
		var already := false
		for m in state["marks"]:
			if m["n"] == r["n"]:
				already = true
				break
		if not already:
			pool.append(r)
	return pick_rand(pool) if not pool.is_empty() else null


func choose(i: int) -> void:
	var o: Dictionary = state["options"][i]
	_write_in_the_book(o)
	if o["kind"] != "break":
		start_fight(o)
		return
	var rest: Dictionary = o["rest"]
	if rest.get("kind", "") == "SHOP":
		state["screen"] = "pick"
		state["pick"] = build_shop()
	else:
		state["screen"] = "pick"
		state["pick"] = build_event(rest)
	state_changed.emit()


## Fills in this hour on the night's page: who came, or what you did instead.
## The outcome is written later, by win() or lose() — an hour on the agenda is
## a name first and a result afterwards, the same order it happens in.
func _write_in_the_book(o: Dictionary) -> void:
	var log: Array = state.get("log", [])
	var step: int = int(state.get("step", 0))
	while log.size() <= step:
		log.append({})
	var kind := str(o.get("kind", ""))
	if kind == "break":
		var rest: Dictionary = o.get("rest", {})
		log[step] = {"kind": "break", "name": str(rest.get("head", rest.get("kind", "")))}
	else:
		log[step] = {"kind": kind, "name": str(o.get("sitter", {}).get("name", "")), "outcome": ""}
	state["log"] = log


## How the hour ended. "mended" or "left"; anything else leaves it blank.
func _close_the_hour(outcome: String) -> void:
	var log: Array = state.get("log", [])
	var step: int = int(state.get("step", 0))
	if step < log.size() and typeof(log[step]) == TYPE_DICTIONARY:
		log[step]["outcome"] = outcome
		state["log"] = log
	# And into the run's own ledger, which outlives the night. This is what the
	# end of a run is made of: not four numbers, but a list of people and what
	# became of each of them. See RunOver.
	var f: Dictionary = state.get("f", {})
	var sitter: Dictionary = f.get("sitter", {})
	if sitter.is_empty():
		return
	var ledger: Array = state.get("ledger", [])
	ledger.append({
		"name": str(sitter.get("name", "")),
		"role": str(sitter.get("role", "")),
		"outcome": outcome,
		"night": int(state.get("night", 0)),
		"at": str(HOURS[step]) if step < HOURS.size() else "",
		# The sitter's own two endings, written in sitters.json: what they do if
		# you get through to them, and what they do if you do not. Carried on the
		# ledger rather than looked up later, because an entry has to survive a
		# pack being switched off between the run and the end of it.
		"said": str(sitter.get("win" if outcome == "mended" else "fail", "")),
	})
	state["ledger"] = ledger


func build_event(e: Dictionary) -> Dictionary:
	return {
		"head": e["head"], "title": e["title"], "kind": "rest", "body": e["line"],
		"opts": e["opts"], "skippable": true, "skipLabel": "LET IT GO BY",
	}


# ── the reading itself ──────────────────────────────────────────────────

func start_fight(o: Dictionary) -> void:
	# A reading, a new turn and a new sitter all end the window in which the
	# last card can be taken back.
	_before_last_card = {}
	var s: Dictionary = o["sitter"]
	var q: Dictionary = o["quirk"]
	var job: Dictionary = Content.get_job(s["role"])
	var wall := int(s["denial"]) if q.get("fx", "") == "shield" else 0
	var denial_shield: Dictionary = Content.denial_shield
	var f := {
		"sitter": s, "quirk": q, "job": job, "boss": o["kind"] == "boss", "elite": o["kind"] == "elite",
		"el": q["el"], "max": s["max"], "hp": 0,
		"denial": wall, "denialUp": int(denial_shield.get(q.get("fx", ""), 0)) * int(s.get("shieldMul", 1)),
		"turn": 1,
		"turns": int(s["turns"]) + (Rules.trait_amount("turn", 1) if has("turn") else 0) + (1 if job.get("fx", "") == "slow" else 0) - (1 if job.get("fx", "") == "rush" else 0),
		"energyMax": cfg_energy() + (Rules.trait_amount("energy", 1) if has("energy") else 0) + (1 if job.get("fx", "") == "energy1" else 0) - (1 if q.get("fx", "") == "energydown" else 0),
		"handMax": maxi(1, cfg_hand() - int(level_fx().get("hand_sub", 0))) + (Rules.trait_amount("hand", 1) if has("hand") else 0) + (1 if job.get("fx", "") == "deal1" else 0) + int(s.get("twist", {}).get("hand", 0)) - (1 if job.get("fx", "") == "tax2" else 0),
		"readerEl": state["reader"]["el"], "hand": [], "draw": shuffle(state["deck"].duplicate(true)), "disc": [],
		"cross": [], "gone": [], "faith": 0, "coin": 0, "energy": 0, "swept": 0, "taken": null,
	}
	begin_turn(f)
	state["screen"] = "read"
	state["f"] = f
	state["sel"] = ""
	state["res"] = {}
	state["seen"] = state["seen"] + [s["name"]]
	state_changed.emit()


## The _prevHp/_prevEnergy/_justDrawn/_justDiscarded fields below are ANIMATION
## BOOKKEEPING, not game state: Reading.gd rebuilds itself from scratch on every
## action, so there is no persistent node to interpolate from. They snapshot
## what changed this action, are read once by the UI, and are never consulted by
## Rules.gd or by the rest of this file.
func begin_turn(f: Dictionary) -> void:
	# A reading, a new turn and a new sitter all end the window in which the
	# last card can be taken back.
	_before_last_card = {}
	if has("serpent") and f["turn"] > 1:
		var cur: String = state.get("serp_el", "") if state.get("serp_el", "") != "" else state["reader"]["el"]
		var ring: Array = Content.ring
		state["serp_el"] = ring[(ring.find(cur) + 1) % ring.size()]
	f["_prevEnergy"] = 0  # a new reading's energy bar animates as a full recharge, not a jump
	f["energy"] = f["energyMax"]
	f["cross"] = []
	f["_justDiscarded"] = []
	if not f["hand"].is_empty():
		f["swept"] = f["hand"].size()
		f["_justDiscarded"] = f["hand"].map(func(c): return c["n"])
		f["disc"] = f["disc"] + f["hand"]
		f["hand"] = []
	else:
		f["swept"] = 0
	var free1_bonus := 2 if (f.get("job", {}).get("fx", "") == "free1" and f["turn"] == 1) else 0
	draw_to(f, int(f["handMax"]) + free1_bonus)
	f["_justDrawn"] = f["hand"].map(func(c): return c["uid"])
	f["taken"] = null
	var quirk: Dictionary = f.get("quirk", {})
	if quirk.get("fx", "") == "steal" and not f["hand"].is_empty():
		var i: int = rng.randi() % int(f["hand"].size())
		f["taken"] = f["hand"][i]["n"]
		f["disc"] = f["disc"] + [f["hand"][i]]
		f["hand"].remove_at(i)


func draw_to(f: Dictionary, n: int) -> void:
	var guard := 0
	while f["hand"].size() < n and guard < 90:
		guard += 1
		if f["draw"].is_empty():
			if f["disc"].is_empty():
				break
			f["draw"] = shuffle(f["disc"])
			f["disc"] = []
		f["hand"].append(f["draw"].pop_front())


## THE FIGHT AS IT WAS BEFORE THE LAST CARD WENT DOWN.
##
## A whole-dict snapshot rather than an inverse of lay_card(): laying a card can
## draw more, refund energy, exhaust itself and shuffle the deck, and unpicking
## all of that by hand is four ways to be subtly wrong about somebody's run. A
## copy is exactly right by construction.
##
## Deliberately NOT in `state`, so it is never saved. Undo lasting across a
## reload would mean Save.gd re-resolving a second whole fight's worth of
## content on load, for a convenience that is about the last ten seconds.
var _before_last_card: Dictionary = {}


## Whether there is a card to take back. The reading screen asks this to decide
## whether to offer the button at all.
func can_unlay() -> bool:
	return not _before_last_card.is_empty() and not state.get("f", {}).is_empty()


## Puts the last card laid back in your hand, with its energy.
##
## Every deckbuilder settles this differently and both answers are defensible;
## this game is a conversation, and a person who has just said the wrong thing
## in a room can generally take it back before the other one answers. You cannot
## un-READ a reading — that is the commitment.
func unlay() -> void:
	if not can_unlay():
		return
	state["f"] = _before_last_card
	_before_last_card = {}
	state_changed.emit()


## Moves a card from hand to the laid line (f.cross), paying its energy cost.
## Ported from _lay(uid) (~2021).
##
## A card's draw/energy fields resolve IMMEDIATELY on lay, not at read time —
## only simulate()'s scoring is deferred to READ IT.
func lay_card(card_uid: String) -> void:
	var f: Dictionary = state["f"]
	if f.is_empty():
		return
	var c: Dictionary = {}
	for x in f["hand"]:
		if x["uid"] == card_uid:
			c = x
			break
	if c.is_empty() or int(c.get("cost", 0)) > int(f["energy"]):
		return
	# Before anything is touched. See _before_last_card.
	_before_last_card = f.duplicate(true)
	f["_prevEnergy"] = f["energy"]
	f["_prevHp"] = f["hp"]  # unchanged by laying a card — avoids replaying a stale hp animation from a prior reading
	f["_justDiscarded"] = []
	f["cross"].append(c)
	f["hand"] = f["hand"].filter(func(x): return x["uid"] != card_uid)
	f["energy"] -= int(c.get("cost", 0))
	if c.has("energy"):
		f["energy"] += int(c["energy"])
	var before_uids: Array = f["hand"].map(func(x): return x["uid"])
	if c.has("draw"):
		draw_to(f, f["hand"].size() + int(c["draw"]))
	f["_justDrawn"] = f["hand"].filter(func(x): return not before_uids.has(x["uid"])).map(func(x): return x["uid"])
	state["sel"] = ""
	state_changed.emit()


## Whether READ IT should do anything.
##
## The prototype's rule is "not with an empty line" (readIt returns early, and
## the button is greyed out via `cannotRead`). That protects against throwing a
## reading away by misclicking — but it also DEADLOCKS: if nothing in hand is
## affordable and nothing is laid, there is no legal action left and the run
## cannot continue. tests/test_soak.gd reaches that state 7 times in 60 runs at
## start_energy=1, which is a supported setting, so it is not theoretical.
##
## So: keep the protection while the player still has a play available, and
## lift it when they genuinely have none. Reading an empty line then costs a
## reading and scores nothing — a bad move, but a legal one, and always
## better than a stuck game.
func can_read() -> bool:
	var f: Dictionary = state.get("f", {})
	if f.is_empty():
		return false
	if not f["cross"].is_empty():
		return true
	for c in f["hand"]:
		if int(c.get("cost", 0)) <= int(f["energy"]):
			return false   # you can still play something — play it
	return true


## Resolves the laid line via Rules.simulate() and applies the result. The
## source animates this card by card (tick()); this port applies it at once —
## see docs/PORTING_NOTES.md.
func read_it() -> void:
	# A reading, a new turn and a new sitter all end the window in which the
	# last card can be taken back.
	_before_last_card = {}
	if not can_read():
		return
	var sim := Rules.simulate(run_ctx(), state["f"])
	resolve_read(sim)


func resolve_read(sim: Dictionary) -> void:
	var f: Dictionary = state["f"]
	f["_prevHp"] = f["hp"]
	f["hp"] = sim["hpAfter"]
	f["faith"] = int(f["faith"]) + int(sim["over"]) + int(sim["bank"])
	f["coin"] = int(f["coin"]) + int(sim["coin"])
	f["turns"] = int(f["turns"]) + int(sim["extraTurns"])
	var exhausted: Array = f["cross"].filter(func(c): return c.get("exhaust", false))
	var kept: Array = f["cross"].filter(func(c): return not c.get("exhaust", false))
	f["gone"] = f["gone"] + exhausted
	f["disc"] = f["disc"] + kept
	f["cross"] = []

	if int(f["hp"]) >= int(f["max"]):
		win(f)
		return

	if f.get("job", {}).get("fx", "") == "coin3":
		f["coin"] = int(f["coin"]) + 3
	f["denial"] = Rules.next_wall(f, sim)

	if int(f["turn"]) >= int(f["turns"]):
		lose(f, "left")
		return

	f["turn"] = int(f["turn"]) + 1
	begin_turn(f)
	state["f"] = f
	state["sel"] = ""
	state_changed.emit()


func win(f: Dictionary) -> void:
	var relic = roll_relic() if f.get("elite", false) else null
	var usury := Rules.trait_amount("usury", 5) if has("usury") else 0
	var faith: int = int(f["faith"]) + 12 + (40 if f.get("boss", false) else 0) + (18 if f.get("elite", false) else 0) + (int(f["turns"]) - int(f["turn"])) * 4
	var coin_gain: int = int(f["coin"]) + usury + 6
	state["coin"] = int(state["coin"]) + coin_gain
	state["faith"] = int(state["faith"]) + faith
	state["mended"] = int(state["mended"]) + 1
	_close_the_hour("mended")
	if relic != null:
		state["marks"] = state["marks"] + [relic]
	var sitter: Dictionary = f["sitter"]
	var lines: Array = [
		{"left": "Composure", "right": "%s / %s" % [f["max"], f["max"]]},
		{"left": "Readings used", "right": "%s / %s" % [f["turn"], f["turns"]]},
		{"left": "Faith earned", "right": "+%s" % faith,
			"note": ["(%s of it overflow)", f["faith"]] if int(f["faith"]) > 0 else null},
		{"left": "Centimes", "right": "+%s" % coin_gain},
	]
	if relic != null:
		lines.append({"left": "Off a hard one", "right": relic["n"], "note": ["it stays on your hands"]})
	state["res"] = {
		"kind": "win", "head": "GOES HOME WHOLE", "title": ["%s is whole enough", sitter["name"]],
		"said": sitter["win"], "lines": lines, "cta": "TAKE SOMETHING FOR IT", "sitter": sitter,
	}
	state_changed.emit()


func lose(f: Dictionary, _how: String) -> void:
	_close_the_hour("left")
	var sitter: Dictionary = f["sitter"]
	var faith_kept: int = int(floor(int(f["faith"]) / 2.0))
	var coin_gain: int = int(f["coin"]) + 3
	state["coin"] = int(state["coin"]) + coin_gain
	state["faith"] = int(state["faith"]) + faith_kept
	state["res"] = {
		"kind": "lose", "head": "PUTS THE COAT BACK ON",
		"title": ["%s leaves as they came, only later", sitter["name"]],
		"said": sitter["fail"],
		"lines": [
			{"left": "Composure at the end", "right": "%s / %s" % [max(0, f["hp"]), f["max"]]},
			{"left": "Readings used", "right": "%s / %s" % [f["turn"], f["turns"]]},
			{"left": "Faith kept", "right": "+%s" % faith_kept},
			{"left": "Centimes", "right": "+%s" % coin_gain, "note": ["the money was on the table"]},
			{"left": "And that is the whole of it", "right": "", "note": ["one is all it takes"]},
		],
		"cta": "SEE WHAT THEY SAY", "sitter": sitter,
	}
	state_changed.emit()


func after_res() -> void:
	if state["res"].get("kind", "") == "win":
		var pick := build_reward(state["f"])
		state["res"] = {}
		state["screen"] = "pick"
		state["pick"] = pick
		state_changed.emit()
	else:
		end_run("failed")


func advance() -> void:
	var night: int = state["night"]
	var step: int = int(state["step"]) + 1
	var seen: Array = state["seen"]
	var plan: Array = state.get("plan", [])
	var log: Array = state.get("log", [])
	if step > 7:
		step = 0
		night += 1
		seen = []
		# A new page in the book: a new night is planned as a whole, and what
		# happened on the last one stops being on screen.
		plan = make_plan(night)
		log = []
	if night > 2:
		end_run("done")
		return
	state["screen"] = "map"
	state["f"] = {}
	state["pick"] = {}
	state["res"] = {}
	state["night"] = night
	state["step"] = step
	state["seen"] = seen
	state["plan"] = plan
	state["log"] = log
	state["options"] = make_options(night, step, seen, plan)
	state_changed.emit()


## Which ending `mended` people earns. Its own function so a test can ask it
## the question directly — the alternative is playing runs until every line
## turns up, and two of these lines used to be unreachable at any count.
##
## Descending, first match wins, and a line with no `mended_from` covers
## everything — so a pack that adds an ending without the field gets a
## catch-all rather than nothing.
## The locale id of an ending, which is its head slugged — the same scheme the
## art manifest and every other content id use.
func _ending_id(ending: Dictionary) -> String:
	var head := str(ending.get("head", ""))
	return "ending/" + Art.slug(head) if head != "" else ""


func ending_for(mended: int) -> Dictionary:
	for e in Content.endings:
		if mended >= int(e.get("mended_from", 0)):
			return e
	return {}


func end_run(why: String) -> void:
	var score: int = state["faith"]
	var tier := "You are still the one in the back room"
	if score >= 640:
		tier = "They come from the next village now"
	elif score >= 400:
		tier = "You are the one they send for"
	elif score >= 200:
		tier = "You make rent and a reputation"
	state["screen"] = "over"
	state["f"] = {}
	state["pick"] = {}
	state["res"] = {}
	# WHAT BECOMES OF THE VILLAGE, and of you, chosen by how many of them you got
	# through to. The screen that ends a run used to be a tier line and four
	# numbers, which is the one place in the game that did not know what the game
	# was about. See data/base/endings.json and ending_for() below.
	var ledger: Array = state.get("ledger", [])
	var after: Dictionary = ending_for(int(state.get("mended", 0)))
	state["over"] = {
		# A run that ENDED because somebody left says so, which is a different
		# sentence from a run that reached the end of the third night. Folding
		# both into the ending's own head was a regression: the ending describes
		# what became of the village, and "one of them went home as they came"
		# describes why you are reading it now.
		"head": "ONE OF THEM WENT HOME AS THEY CAME" if why == "failed"
			else "THREE NIGHTS, AND THE KNOCKING STOPS",
		"title": tier,
		"body": ["Word travels the length of a village in an afternoon. One person sat at your table and left with exactly what they arrived with, and nobody needs telling twice."] if why == "failed"
			else ["You mended %s of them. What they say about you afterwards is the only score that was ever being kept.", state["mended"]],
		# TRANSLATED HERE, by the ending's own id, rather than copied out of the
		# registry: these three paragraphs are the last thing anybody reads and
		# they were the only part of a French run that closed in English.
		"after": I18n.content(_ending_id(after), "head", str(after.get("head", ""))),
		"village": I18n.content(_ending_id(after), "village", str(after.get("village", ""))),
		"reader": I18n.content(_ending_id(after), "reader", str(after.get("reader", ""))),
		"ledger": ledger,
		"lines": [
			{"left": "Faith", "right": str(score)},
			{"left": "Restored", "right": str(state["mended"])},
			{"left": "Deck", "right": ["%s cards", state["deck"].size()]},
			{"left": "Centimes left", "right": str(state["coin"])},
			{"left": "Evening no.", "right": str(state.get("seed", ""))},
		],
	}
	state_changed.emit()


# ── rewards / shop ──────────────────────────────────────────────────────

func roll_mark(kind: String = ""):
	var pool: Array = []
	for m in Content.marks:
		if kind != "" and kind != "ANY" and m["kind"] != kind:
			continue
		var already := false
		for x in state["marks"]:
			if x["n"] == m["n"]:
				already = true
				break
		if not already:
			pool.append(m)
	return pick_rand(pool) if not pool.is_empty() else null


func weighted(pool: Array):
	if pool.is_empty():
		return null
	const RARW := {"basic": 0, "common": 6, "uncommon": 3, "rare": 1}
	var total := 0
	for c in pool:
		total += int(RARW.get(c.get("r", "common"), 1))
	var roll := rng.randf() * total
	for c in pool:
		roll -= float(RARW.get(c.get("r", "common"), 1))
		if roll <= 0:
			return c
	return pool[pool.size() - 1]


func minor_of_el(el: String, ex: Array):
	var pool: Array = []
	for m in Content.cards_minor:
		if m["el"] == el and not ex.has(m["n"]):
			pool.append(m)
	return weighted(pool)


func arcanum_of(el, ex: Array):
	var pool: Array = []
	for a in Content.cards_arcana:
		if a["el"] == el and not ex.has(a["n"]):
			pool.append(a)
	return weighted(pool)


func arcanum(ex: Array):
	var pool: Array = []
	for a in Content.cards_arcana:
		if not ex.has(a["n"]):
			pool.append(a)
	return weighted(pool)


func roll_offer(f: Dictionary, ex: Array):
	var own := rng.randf() < 0.5
	var neigh: Array = Content.neighbors.get(f["el"], [])
	var el: String = f["el"] if own else pick_rand(neigh)
	if own and rng.randf() < 0.35:
		var signless := rng.randf() < 0.15
		var arc = arcanum_of(null if signless else el, ex)
		if arc != null:
			return {"card": arc, "kind": ("AN ARCANUM WITH NO SIGN" if signless else "AN ARCANUM OF THEIR SIGN") + " · " + arc["num"], "cost": 0}
	var c = minor_of_el(el, ex)
	return {"card": c, "kind": "THEIR SIGN" if el == f["el"] else "", "cost": 0} if c != null else null


func build_reward(f: Dictionary) -> Dictionary:
	var ex: Array = []
	var opts: Array = []
	for k in range(3):
		var o = roll_offer(f, ex)
		if o != null:
			ex.append(o["card"]["n"])
			opts.append(o)
	var quirk: Dictionary = f.get("quirk", {})
	return {
		"head": "PAYS IN MORE THAN COIN", "title": "Take one card out of the evening", "kind": "reward",
		"pack": {"el": f["el"], "sign": quirk.get("k", "aries"), "name": quirk.get("n", "")},
		"body": "Three came out of the evening. What got better decides what turns up.",
		"opts": opts, "skippable": true, "skipLabel": "TAKE NOTHING · +8 FAITH",
	}


func build_shop() -> Dictionary:
	var shop: Dictionary = Content.shop
	var a = arcanum([])
	var m = roll_mark()
	var opts: Array = []
	if a != null:
		opts.append({"card": a, "kind": "AN ARCANUM · " + a["num"], "cost": int(shop.get("arcanum_price", 14))})
	if m != null:
		opts.append({"mark": m, "kind": m["kind"], "cost": int(shop.get("mark_price", 11))})
	opts.append({"burn": true, "kind": "THE REMOVAL OF THINGS", "cost": int(shop.get("burn_price", 8)), "name": shop.get("burn_name", "Burn A Card"), "text": shop.get("burn_text", "")})
	return {
		"head": shop.get("head", "THE APOTHECARY"), "title": shop.get("line", ""), "kind": "shop",
		"body": shop.get("body", ""), "opts": opts, "skippable": true, "skipLabel": "LEAVE WITH YOUR MONEY",
	}


func take_pick(i: int) -> void:
	var pick: Dictionary = state["pick"]
	var o: Dictionary = resolve_named(pick["opts"][i])
	if pick.get("kind", "") == "gift":
		var c: Dictionary = o["card"].duplicate(true)
		c["uid"] = uid()
		state["deck"] = state["deck"] + [c]
		state["pick"] = {}
		state["screen"] = "map"
		state_changed.emit()
		return

	var deck: Array = state["deck"].duplicate(true)
	var marks: Array = state["marks"].duplicate(true)
	var coin: int = state["coin"]
	var cost := int(o.get("cost", 0))
	if cost > 0:
		if coin < cost:
			return
		coin -= cost
	if o.has("card"):
		var c: Dictionary = o["card"].duplicate(true)
		c["uid"] = uid()
		deck.append(c)
	if o.has("mark"):
		marks.append(o["mark"])
	if o.get("burn", false):
		var worst_idx := -1
		var worst_score := INF
		for idx in deck.size():
			var d: Dictionary = deck[idx]
			var score: float = float(d.get("f", 0)) + float(d.get("cost", 0)) * 2.0
			if score < worst_score:
				worst_score = score
				worst_idx = idx
		if worst_idx >= 0:
			deck.remove_at(worst_idx)
	var reward: Dictionary = o.get("reward", {})
	if reward.has("coin"):
		coin += int(reward["coin"])
	if reward.has("faith"):
		state["faith"] = int(state["faith"]) + int(reward["faith"])
	if reward.get("burn", false) and not deck.is_empty():
		var worst_idx2 := -1
		var worst_score2 := INF
		for idx in deck.size():
			var d: Dictionary = deck[idx]
			var score: float = float(d.get("f", 0)) + float(d.get("cost", 0)) * 2.0
			if score < worst_score2:
				worst_score2 = score
				worst_idx2 = idx
		if worst_idx2 >= 0:
			deck.remove_at(worst_idx2)

	state["deck"] = deck
	state["marks"] = marks
	state["coin"] = coin
	state["pick"] = {}
	advance()


## An option may NAME the card or mark it gives instead of carrying a whole copy
## of one: `"card": "Pour The Tea"` rather than the card object.
##
## This exists for the events. An events file that inlines a copy of a card is a
## SECOND COPY OF THAT CARD'S RULES — it goes stale the moment the card is
## balanced, a mod that rebalances the card does not rebalance the copy, and
## Save.gd's content re-resolution has no way to tell the copy from the
## original. A name is resolved here, against whatever content is loaded now.
##
## A name nothing answers to is dropped with a warning rather than crashing or
## handing out an empty card: a pack that removes a card an event names is a
## mistake to report, not a run to end.
func resolve_named(o: Dictionary) -> Dictionary:
	if not (o.get("card") is String or o.get("mark") is String):
		return o
	var out := o.duplicate(true)
	if out.get("card") is String:
		var named := Content.get_card(str(out["card"]))
		if named.is_empty():
			push_warning("[Run] an option names the card '%s', which no loaded pack has." % out["card"])
			out.erase("card")
		else:
			out["card"] = named
	if out.get("mark") is String:
		var wanted := str(out["mark"])
		var found := {}
		for m in Content.marks + Content.relics:
			if str(m.get("n", "")) == wanted:
				found = m
				break
		if found.is_empty():
			push_warning("[Run] an option names the mark '%s', which no loaded pack has." % wanted)
			out.erase("mark")
		else:
			out["mark"] = found
	return out


func skip_pick() -> void:
	var pick: Dictionary = state["pick"]
	if pick.get("kind", "") == "reward":
		state["faith"] = int(state["faith"]) + 8
	state["pick"] = {}
	advance()


func restart() -> void:
	state = fresh()
	state_changed.emit()
