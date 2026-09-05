## Headless balance simulator — a port of simFight()/simSweep()/simGroup()/
## runSim() from Parlour v23.dc.html (~lines 1583-1684), the greedy auto-player
## the source uses to sanity-check difficulty without playing every matchup by
## hand. Doesn't touch Run.state at all (unlike the source, which temporarily
## swaps `this.state` and restores it in a finally block) — builds its own
## throwaway run_ctx per fight instead, which is simpler and can't leak into
## a real game session since none of this runs during actual play.
##
## Run with:
##   godot --headless --path godot -s tests/balance_sim.gd -- [n] [filters]
## n = number of randomized fights to sample (default 400). Each fight pairs
## a reader (cycled through all 13) against a random sitter and a random sign
## quirk, scaled to night=1/step=3 by default (the source's own baseline —
## "measures how the start of a night sits, not the whole run").
##
## Filters, any combination:
##   sign=<key> / reader=<key>   pin one axis. A whole-field sweep gives ~n/13
##                               samples per cell, which is too few to tell a
##                               real shift from noise; pin the cell you are
##                               tuning and give it the whole n.
##   night=<n> / step=<n>        measure at a different point in the run.
##   level=<n>                   climb the difficulty ladder (data/base/
##                               difficulty.json). Cumulative, as in play.
##   elite=1                     every caller is a difficult one, twist and all.
##
##   ... -- 1300 sign=taurus          every reader against the hardest sign
##   ... -- 6500 night=2 step=6       the whole field, late in the last night
##   ... -- 3000 level=5              the whole field on the top rung
##
## TWO LADDER RUNGS THIS CANNOT MEASURE, and neither is a bug in them:
## `coin_sub` (level 2) only moves the purse a run starts with, and this
## simulator never shops; `elite_chance` (level 4) only changes how OFTEN a
## difficult caller is OFFERED, and here the fight is handed over rather than
## chosen. Use `elite=1` for what an elite costs you once you sit with one —
## that number times how often one turns up is the rung's real weight.
##
## Reads as a report, not a pass/fail test: the source's own guidance
## (printed at the bottom) is under ~35% win rate is close to unwinnable,
## over ~85% asks nothing of you. Whether these ported numbers land in a
## good range is exactly what this is for finding out — see
## docs/PORTING_NOTES.md, which flags the source's own balance as an
## unfinished work in progress, not a spec to match exactly.
extends SceneTree

const SimEngine := preload("res://tests/sim_engine.gd")

var content: Node
var sim: SimEngine


func _initialize() -> void:
	content = root.get_node("Content")
	content.reload()
	sim = SimEngine.new(root)

	var n := 400
	var args := OS.get_cmdline_user_args()
	for a in args:
		if a.is_valid_int():
			n = int(a)
		elif a.begins_with("sign="):
			sim.only_sign = a.substr(5).to_lower()
		elif a.begins_with("reader="):
			sim.only_reader = a.substr(7).to_lower()
		elif a.begins_with("night="):
			sim.at_night = int(a.substr(6))
		elif a.begins_with("step="):
			sim.at_step = int(a.substr(5))
		elif a.begins_with("level="):
			sim.at_level = int(a.substr(6))
		elif a.begins_with("elite="):
			sim.elites = a.substr(6) != "0"
		else:
			printerr("unknown argument \"%s\" — expected a count, sign=<key>, reader=<key>, night=<n>, step=<n>, level=<n> or elite=1" % a)
			quit(1)
			return
	if sim.only_sign != "" and content.get_sign(sim.only_sign).is_empty():
		printerr("no such sign key: %s" % sim.only_sign)
		quit(1)
		return
	if sim.only_reader != "" and content.get_reader(sim.only_reader).is_empty():
		printerr("no such reader key: %s" % sim.only_reader)
		quit(1)
		return
	var top := 0
	for rung in content.difficulty:
		top = maxi(top, int(rung.get("n", 0)))
	if sim.at_level < 0 or sim.at_level > top:
		printerr("no such difficulty level: %d (the ladder is 0..%d)" % [sim.at_level, top])
		quit(1)
		return
	# The ONE piece of shared state this touches, and deliberately: Run.level_fx()
	# reads it, so setting it here means the ladder under test is the one the game
	# plays. Safe because nothing else in this process has a run.
	sim.run.state["level"] = sim.at_level

	var t0 := Time.get_ticks_msec()
	var rows := sim.sim_sweep(n)
	var ms := Time.get_ticks_msec() - t0

	var wins := 0
	for r in rows:
		if r["win"]:
			wins += 1
	var overall := float(wins) / rows.size()

	var scope := ", night %d step %d, level %d" % [sim.at_night, sim.at_step, sim.at_level]
	if sim.elites:
		scope += ", elites"
	if sim.only_reader != "":
		scope += ", reader=%s" % sim.only_reader
	if sim.only_sign != "":
		scope += ", sign=%s" % sim.only_sign
	print("=== Parlour balance sweep: %d fights in %dms%s ===" % [n, ms, scope])
	print("OVERALL WIN RATE: %.1f%%  (rule of thumb: <35%% ~unwinnable, >85%% asks nothing of you)" % (overall * 100.0))
	print("")
	_print_group("BY READER", sim.sim_group(rows, "reader"))
	_print_group("BY SIGN (sitter denial)", sim.sim_group(rows, "sign"))
	_print_group("BY JOB", sim.sim_group(rows, "job"))

	quit(0)


func _print_group(title: String, groups: Array) -> void:
	print("--- %s (weakest matchup first) ---" % title)
	for g in groups:
		print("  %-16s  win %5.1f%%  n=%-4d  avg readings %5.2f  avg composure %5.1f%%" % [
			g["label"], g["rate"] * 100.0, g["n"], g["readings"], g["pct"] * 100.0
		])
	print("")


