## Headless balance simulator — a port of simFight()/simSweep()/simGroup()/
## runSim() from Parlour v23.dc.html (~lines 1583-1684), the greedy auto-player
## the source uses to sanity-check difficulty without playing every matchup by
## hand. Doesn't touch Run.state at all (unlike the source, which temporarily
## swaps `this.state` and restores it in a finally block) — builds its own
## throwaway run_ctx per fight instead, which is simpler and can't leak into
## a real game session since none of this runs during actual play.
##
## Run with:
##   godot --headless --path godot -s tests/balance_sim.gd [n]
## n = number of randomized fights to sample (default 400). Each fight pairs
## a reader (cycled through all 13) against a random sitter scaled to
## night=1/step=3 (matches the source's own baseline — "measures how the
## start of a night sits, not the whole run") and a random sign quirk.
##
## Reads as a report, not a pass/fail test: the source's own guidance
## (printed at the bottom) is under ~35% win rate is close to unwinnable,
## over ~85% asks nothing of you. Whether these ported numbers land in a
## good range is exactly what this is for finding out — see
## docs/PORTING_NOTES.md, which flags the source's own balance as an
## unfinished work in progress, not a spec to match exactly.
extends SceneTree

var content: Node
var rules: Node
var run: Node


func _initialize() -> void:
	content = root.get_node("Content")
	rules = root.get_node("Rules")
	run = root.get_node("Run")
	content.reload()

	var n := 400
	var args := OS.get_cmdline_user_args()
	if args.size() > 0 and args[0].is_valid_int():
		n = int(args[0])

	var t0 := Time.get_ticks_msec()
	var rows := sim_sweep(n)
	var ms := Time.get_ticks_msec() - t0

	var wins := 0
	for r in rows:
		if r["win"]:
			wins += 1
	var overall := float(wins) / rows.size()

	print("=== Parlour balance sweep: %d fights in %dms ===" % [n, ms])
	print("OVERALL WIN RATE: %.1f%%  (rule of thumb: <35%% ~unwinnable, >85%% asks nothing of you)" % (overall * 100.0))
	print("")
	_print_group("BY READER", sim_group(rows, "reader"))
	_print_group("BY SIGN (sitter denial)", sim_group(rows, "sign"))
	_print_group("BY JOB", sim_group(rows, "job"))

	quit(0)


func _print_group(title: String, groups: Array) -> void:
	print("--- %s (weakest matchup first) ---" % title)
	for g in groups:
		print("  %-16s  win %5.1f%%  n=%-4d  avg readings %5.2f  avg composure %5.1f%%" % [
			g["label"], g["rate"] * 100.0, g["n"], g["readings"], g["pct"] * 100.0
		])
	print("")


# ── ported engine (see class doc comment) ──────────────────────────────

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
		"turns": int(sitter["turns"]) + (1 if rules.has(ctx, "turn") else 0) + (1 if job.get("fx", "") == "slow" else 0) - (1 if job.get("fx", "") == "rush" else 0),
		"energyMax": int(run.cfg_energy()) + (1 if rules.has(ctx, "energy") else 0) + (1 if job.get("fx", "") == "energy1" else 0) - (1 if quirk.get("fx", "") == "energydown" else 0),
		"handMax": int(run.cfg_hand()) + (1 if rules.has(ctx, "hand") else 0) + (1 if job.get("fx", "") == "deal1" else 0) - (1 if job.get("fx", "") == "tax2" else 0),
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
		f["denial"] = int(f["denial"]) + int(f["denialUp"])
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
		var r: Dictionary = readers[i % readers.size()]
		var s: Dictionary = run.scale_sitter(run.pick_rand(sitters), 1, 3)
		var q: Dictionary = run.pick_rand(signs)
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
