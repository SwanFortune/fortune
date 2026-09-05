## THE GREEDY AUTO-PLAYER, on its own so two callers can share it: the
## tests/balance_sim.gd report, which prints the whole field, and
## tests/test_balance.gd, which fails when a reader drifts out of the field.
##
## A port of simFight()/simSweep()/simGroup() from Parlour v23.dc.html
## (~1583-1684). Touches Run.state only to set the difficulty level, since
## Run.level_fx() reads it; everything else is a throwaway fight dict, so none
## of this can leak into a real session.
##
## It plays ONE PLY: at every step it lays whichever single card scores best
## right now. That is enough to price restore bonuses and enough to rank the
## field, and it is why two traits come out under-priced and are exempted where
## this is used as a test — a bigger HAND is worth little to a player who never
## plans a whole reading, and MONEY is worth nothing at all to one that never
## shops.
extends RefCounted

var content: Node
var rules: Node
var run: Node

## Where in a run to measure, which rung, and whether the caller is an elite.
var at_night := 1
var at_step := 3
var at_level := 0
var elites := false
var only_sign := ""
var only_reader := ""


func _init(root: Node) -> void:
	content = root.get_node("Content")
	rules = root.get_node("Rules")
	run = root.get_node("Run")



func sim_ctx(reader: Dictionary) -> Dictionary:
	return {"reader": reader, "marks": [], "serp_el": reader["el"]}


func sim_turn_begin(f: Dictionary, ctx: Dictionary) -> void:
	f["energy"] = f["energyMax"]
	f["cross"] = []
	if not f["hand"].is_empty():
		f["disc"] = f["disc"] + f["hand"]
		f["hand"] = []
	var job: Dictionary = f["job"]
	var free1 := 2 if (job.get("fx", "") == "free1" and int(f["turn"]) == 1) else 0
	run.draw_to(f, int(f["handMax"]) + free1)
	var quirk: Dictionary = f["quirk"]
	if quirk.get("fx", "") == "steal" and not f["hand"].is_empty():
		var i: int = randi() % int(f["hand"].size())
		f["disc"] = f["disc"] + [f["hand"][i]]
		f["hand"].remove_at(i)


func sim_score(ctx: Dictionary, f: Dictionary) -> float:
	var s: Dictionary = rules.simulate(ctx, f)
	return float(s["applied"]) + float(s["bank"]) * 0.5


func sim_play_turn(ctx: Dictionary, f: Dictionary) -> void:
	var guard := 0
	while guard < 30:
		guard += 1
		var opts: Array = f["hand"].filter(func(c): return int(c.get("cost", 0)) <= int(f["energy"]))
		if opts.is_empty():
			break
		var base := sim_score(ctx, f)
		var best = null
		var best_gain := 0.01
		for c in opts:
			f["cross"].append(c)
			var gain: float = sim_score(ctx, f) - base
			f["cross"].pop_back()
			gain += float(c.get("draw", 0)) * 1.5 + float(c.get("energy", 0)) * 1.2 + float(c.get("turn", 0)) * 4.0 + float(c.get("coin", 0)) * 0.2
			if gain > best_gain:
				best_gain = gain
				best = c
		if best == null:
			break
		f["cross"].append(best)
		f["hand"] = f["hand"].filter(func(x): return x != best)
		f["energy"] = int(f["energy"]) - int(best.get("cost", 0))
		if best.has("energy"):
			f["energy"] = int(f["energy"]) + int(best["energy"])
		if best.has("draw"):
			run.draw_to(f, f["hand"].size() + int(best["draw"]))


func sim_fight(reader: Dictionary, sitter: Dictionary, quirk: Dictionary) -> Dictionary:
	var ctx := sim_ctx(reader)
	var job: Dictionary = content.get_job(sitter["role"])
	var denial_shield: Dictionary = content.denial_shield
	var f := {
		"sitter": sitter, "quirk": quirk, "job": job, "el": quirk["el"], "max": sitter["max"], "hp": 0,
		"denial": int(sitter["denial"]) if quirk.get("fx", "") == "shield" else 0,
		"denialUp": int(denial_shield.get(quirk.get("fx", ""), 0)) * int(sitter.get("shieldMul", 1)),
		"turn": 1,
		"turns": int(sitter["turns"]) + (rules.trait_amount("turn", 1) if rules.has(ctx, "turn") else 0) + (1 if job.get("fx", "") == "slow" else 0) - (1 if job.get("fx", "") == "rush" else 0),
		"energyMax": int(run.cfg_energy()) + (rules.trait_amount("energy", 1) if rules.has(ctx, "energy") else 0) + (1 if job.get("fx", "") == "energy1" else 0) - (1 if quirk.get("fx", "") == "energydown" else 0),
		# maxi() and the twist's hand bonus are not decoration: the top rung takes
		# a card away and one elite twist gives one back, and a handMax of zero
		# would deal nothing and lose every fight for the wrong reason.
		"handMax": maxi(1, int(run.cfg_hand()) - int(run.level_fx().get("hand_sub", 0))) + (rules.trait_amount("hand", 1) if rules.has(ctx, "hand") else 0) + (1 if job.get("fx", "") == "deal1" else 0) + int(sitter.get("twist", {}).get("hand", 0)) - (1 if job.get("fx", "") == "tax2" else 0),
		"readerEl": reader["el"], "hand": [], "draw": run.shuffle(run.base_deck(reader)), "disc": [],
		"cross": [], "gone": [], "faith": 0, "coin": 0,
	}
	var readings := 0
	while readings < 40:
		if rules.has(ctx, "serpent") and int(f["turn"]) > 1:
			var ring: Array = content.ring
			ctx["serp_el"] = ring[(ring.find(ctx["serp_el"]) + 1) % ring.size()]
		sim_turn_begin(f, ctx)
		sim_play_turn(ctx, f)
		var sim: Dictionary = rules.simulate(ctx, f)
		readings += 1
		f["hp"] = sim["hpAfter"]
		f["turns"] = int(f["turns"]) + int(sim["extraTurns"])
		var exhausted: Array = f["cross"].filter(func(c): return c.get("exhaust", false))
		var kept: Array = f["cross"].filter(func(c): return not c.get("exhaust", false))
		f["gone"] = f["gone"] + exhausted
		f["disc"] = f["disc"] + kept
		f["cross"] = []
		if int(f["hp"]) >= int(f["max"]):
			return {"win": true, "readings": readings, "hp": f["hp"], "max": f["max"]}
		f["denial"] = rules.next_wall(f, sim)
		if int(f["turn"]) >= int(f["turns"]):
			return {"win": false, "readings": readings, "hp": f["hp"], "max": f["max"]}
		f["turn"] = int(f["turn"]) + 1
	return {"win": false, "readings": readings, "hp": f["hp"], "max": f["max"]}


func sim_sweep(n: int) -> Array:
	var rows: Array = []
	var readers: Array = content.readers
	var sitters: Array = content.sitters
	var signs: Array = content.signs
	for i in n:
		var r: Dictionary = content.get_reader(only_reader) if only_reader != "" else readers[i % readers.size()]
		# elite_of() BEFORE scale_sitter(), the order make_options() uses — the
		# twist multiplies the base composure, then the night scales the result.
		var s: Dictionary = run.scale_sitter(run.elite_of(run.pick_rand(sitters), elites), at_night, at_step)
		var q: Dictionary = content.get_sign(only_sign) if only_sign != "" else run.pick_rand(signs)
		var res: Dictionary = sim_fight(r, s.duplicate(true), q)
		var max_hp: int = res["max"]
		rows.append({
			"reader": r["sign"], "sign": q["n"], "job": s["role"], "win": res["win"],
			"readings": res["readings"], "pct": (float(res["hp"]) / float(max_hp)) if max_hp > 0 else 0.0,
		})
	return rows


func sim_group(rows: Array, key: String) -> Array:
	var by: Dictionary = {}
	for r in rows:
		var k = r[key]
		if not by.has(k):
			by[k] = []
		by[k].append(r)
	var out: Array = []
	for k in by.keys():
		var g: Array = by[k]
		var wins := 0
		var readings_sum := 0.0
		var pct_sum := 0.0
		for x in g:
			if x["win"]:
				wins += 1
			readings_sum += x["readings"]
			pct_sum += x["pct"]
		out.append({"label": str(k), "n": g.size(), "rate": float(wins) / g.size(), "readings": readings_sum / g.size(), "pct": pct_sum / g.size()})
	out.sort_custom(func(a, b): return a["rate"] < b["rate"])
	return out
