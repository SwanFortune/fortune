## Autoload. The run/game state machine — a port of the Component class's
## state-mutating methods in Parlour v23.dc.html (fresh(), startFight(),
## beginTurn(), resolveRead(), win()/lose(), advance(), endRun(), the reward/
## shop/event builders, takePick()). UI scenes read `Run.state` (a plain
## Dictionary mirroring the source's `this.state`) and call these methods;
## they never touch Rules or Content directly for game-flow decisions.
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

func fresh() -> Dictionary:
	var reader: Dictionary = Content.readers[0]
	var st := {
		"screen": "sign", "night": 0, "step": 0, "coin": 5, "faith": 0, "mended": 0,
		"reader": reader, "deck": [], "marks": [], "seen": [], "seq": 0,
		"serp_el": "", "options": [], "f": {}, "pick": {}, "res": {}, "over": {}, "sel": "",
	}
	st["deck"] = base_deck(reader)
	st["options"] = make_options(0, 0, [])
	return st


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

func uid() -> String:
	state["seq"] = int(state.get("seq", 0)) + 1
	return "c%d%d" % [state["seq"], randi() % 100000]


func pick_rand(a: Array):
	return a[randi() % a.size()]


func shuffle(a: Array) -> Array:
	var b := a.duplicate()
	b.shuffle()
	return b


# ── map / knocks ────────────────────────────────────────────────────────

func scale_sitter(s: Dictionary, night: int, step: int) -> Dictionary:
	var prog := night * 8 + step
	var k := 1.0 + prog * 0.045
	var out := s.duplicate(true)
	out["max"] = int(round(s["max"] * k))
	out["denial"] = int(s["denial"]) + int(prog / 5)
	return out


## Ported from makeOptions() (~1825). Nobody knocks twice in one night.
func make_options(night: int, step: int, seen: Array) -> Array:
	var is_last := step == 7
	if night == 2 and is_last:
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

	var opts: Array = [mk.call(pool[0], false)]
	if is_last:
		return opts
	var second: Dictionary = pool[1] if pool.size() > 1 else pool[0]
	opts.append(mk.call(second, step >= 2 and randf() < 0.55))
	if step >= 1 and randf() < 0.45:
		opts.append({"kind": "break", "rest": Content.shop})
	if opts.size() < 4 and randf() < 0.55:
		opts.append({"kind": "break", "rest": pick_rand(Content.events)})
	return opts.slice(0, min(4, opts.size()))


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


func build_event(e: Dictionary) -> Dictionary:
	return {
		"head": e["head"], "title": e["title"], "kind": "rest", "body": e["line"],
		"opts": e["opts"], "skippable": true, "skipLabel": "LET IT GO BY",
	}


# ── the reading itself ──────────────────────────────────────────────────

func start_fight(o: Dictionary) -> void:
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
		"turns": int(s["turns"]) + (1 if has("turn") else 0) + (1 if job.get("fx", "") == "slow" else 0) - (1 if job.get("fx", "") == "rush" else 0),
		"energyMax": cfg_energy() + (1 if has("energy") else 0) + (1 if job.get("fx", "") == "energy1" else 0) - (1 if q.get("fx", "") == "energydown" else 0),
		"handMax": cfg_hand() + (1 if has("hand") else 0) + (1 if job.get("fx", "") == "deal1" else 0) + int(s.get("twist", {}).get("hand", 0)) - (1 if job.get("fx", "") == "tax2" else 0),
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


## Animation bookkeeping note: the UI (Reading.gd) fully rebuilds itself from
## Run.state on every action rather than staying alive and being incrementally
## updated (see UIKit.gd's doc comment), so there's no persistent node around
## to interpolate FROM. The fields below (_prevHp/_prevEnergy/_justDrawn/
## _justDiscarded) exist purely so the next rebuild can still animate
## correctly: they snapshot "what changed this action" onto the fight dict
## itself, read once by the UI and not treated as real game state anywhere
## in Rules.gd or elsewhere in Run.gd.
func begin_turn(f: Dictionary) -> void:
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
		var i: int = randi() % int(f["hand"].size())
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


## Ported from _lay(uid) (~2021): moves a card from hand to the laid line
## (f.cross), paying its energy cost. draw/energy card fields resolve
## immediately on lay, not at read time — only simulate()'s scoring math is
## deferred to READ IT.
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


## Resolves the laid line via Rules.simulate() and applies the result. The
## source animates this card-by-card (tick()); this port applies it
## immediately — see docs/PORTING_NOTES.md for why that's fine for this pass.
func read_it() -> void:
	var f: Dictionary = state["f"]
	if f.is_empty() or f["cross"].is_empty():
		return
	var sim := Rules.simulate(run_ctx(), f)
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
	f["denial"] = int(f["denial"]) + int(f["denialUp"])

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
	var usury := 5 if has("usury") else 0
	var faith: int = int(f["faith"]) + 12 + (40 if f.get("boss", false) else 0) + (18 if f.get("elite", false) else 0) + (int(f["turns"]) - int(f["turn"])) * 4
	var coin_gain: int = int(f["coin"]) + usury + 6
	state["coin"] = int(state["coin"]) + coin_gain
	state["faith"] = int(state["faith"]) + faith
	state["mended"] = int(state["mended"]) + 1
	if relic != null:
		state["marks"] = state["marks"] + [relic]
	var sitter: Dictionary = f["sitter"]
	var lines: Array = [
		{"left": "Composure", "right": "%s / %s" % [f["max"], f["max"]]},
		{"left": "Readings used", "right": "%s of %s" % [f["turn"], f["turns"]]},
		{"left": "Faith earned", "right": "+%s%s" % [faith, (" (%s of it overflow)" % f["faith"]) if int(f["faith"]) > 0 else ""]},
		{"left": "Centimes", "right": "+%s" % coin_gain},
	]
	if relic != null:
		lines.append({"left": "Off a hard one", "right": "%s — it stays on your hands" % relic["n"]})
	state["res"] = {
		"kind": "win", "head": "GOES HOME WHOLE", "title": "%s is whole enough" % sitter["name"],
		"said": sitter["win"], "lines": lines, "cta": "TAKE SOMETHING FOR IT", "sitter": sitter,
	}
	state_changed.emit()


func lose(f: Dictionary, _how: String) -> void:
	var sitter: Dictionary = f["sitter"]
	var faith_kept: int = int(floor(int(f["faith"]) / 2.0))
	var coin_gain: int = int(f["coin"]) + 3
	state["coin"] = int(state["coin"]) + coin_gain
	state["faith"] = int(state["faith"]) + faith_kept
	state["res"] = {
		"kind": "lose", "head": "PUTS THE COAT BACK ON", "title": "%s leaves as they came, only later" % sitter["name"],
		"said": sitter["fail"],
		"lines": [
			{"left": "Composure at the end", "right": "%s / %s" % [max(0, f["hp"]), f["max"]]},
			{"left": "Readings used", "right": "%s of %s" % [f["turn"], f["turns"]]},
			{"left": "Faith kept", "right": "+%s" % faith_kept},
			{"left": "Centimes", "right": "+%s — the money was on the table" % coin_gain},
			{"left": "And that is the whole of it", "right": "one is all it takes"},
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
	if step > 7:
		step = 0
		night += 1
		seen = []
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
	state["options"] = make_options(night, step, seen)
	state_changed.emit()


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
	state["over"] = {
		"head": "ONE OF THEM WENT HOME AS THEY CAME" if why == "failed" else "THREE NIGHTS, AND THE KNOCKING STOPS",
		"title": tier,
		"body": "Word travels the length of a village in an afternoon. One person sat at your table and left with exactly what they arrived with, and nobody needs telling twice." if why == "failed"
			else "You mended %s of them. What they say about you afterwards is the only score that was ever being kept." % state["mended"],
		"lines": [
			{"left": "Faith", "right": str(score)},
			{"left": "Restored", "right": str(state["mended"])},
			{"left": "Deck", "right": "%s cards" % state["deck"].size()},
			{"left": "Centimes left", "right": str(state["coin"])},
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
	var roll := randf() * total
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
	var own := randf() < 0.5
	var neigh: Array = Content.neighbors.get(f["el"], [])
	var el: String = f["el"] if own else pick_rand(neigh)
	if own and randf() < 0.35:
		var signless := randf() < 0.15
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
	var o: Dictionary = pick["opts"][i]
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


func skip_pick() -> void:
	var pick: Dictionary = state["pick"]
	if pick.get("kind", "") == "reward":
		state["faith"] = int(state["faith"]) + 8
	state["pick"] = {}
	advance()


func restart() -> void:
	state = fresh()
	state_changed.emit()
