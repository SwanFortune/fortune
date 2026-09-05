## NO READER IS A TRAP, AND NONE IS A FREE PASS.
##   godot --headless --path godot -s tests/test_balance.gd
##
## Thirteen readers are thirteen ways to play, and a player picks one before
## they know anything. Measured at the point where the field actually separates
## — night 2, hour 6, difficulty 2 — they ran from 14% to 94%, which makes the
## choice a trap rather than a choice. This fails if any of them drifts back
## out of the band.
##
## SLOWER THAN THE OTHER TESTS (a few thousand played-out fights, some seconds)
## and worth it: a balance pass with nothing holding it in place comes undone
## the next time somebody tunes a number, and nothing else in the suite would
## say a word.
##
## TWO READERS ARE EXEMPT, and named rather than quietly excluded, because the
## simulator cannot price what they do:
##
##   CAPRICORN's trait is money. This plays fights and never shops, so its
##   whole rule is invisible here — five centimes a sitter is about eighty a
##   run, five or six things off the apothecary's shelf, and none of that is
##   in the number below.
##
##   GEMINI's trait is a bigger hand. The auto-player is greedy and one ply
##   deep: it lays whichever single card scores best right now and never plans
##   a reading, so more choice buys it almost nothing and buys a person a lot.
##
## Both are floors, not verdicts. Neither may be used to excuse a THIRD name
## appearing here.
extends SceneTree

const SimEngine := preload("res://tests/sim_engine.gd")

## The source's own rule of thumb, and the band this file holds the field to.
const FLOOR := 0.35
const CEILING := 0.85

## Readers whose trait this simulator cannot price. See the header.
const CANNOT_PRICE := ["CAPRICORN", "GEMINI"]

## Fights per sweep. 5200 over the field is ~370 each: enough that the ceiling
## check has real margin under it rather than flickering on noise. Not trying to
## resolve five points either — this is a band, not a target.
const FIGHTS := 5200

var failures: Array[String] = []


func _initialize() -> void:
	var content: Node = root.get_node("Content")
	await process_frame
	content.reload()

	var sim := SimEngine.new(root)
	sim.at_night = 2
	sim.at_step = 6
	sim.at_level = 2
	sim.run.state["level"] = sim.at_level

	# BASE READERS ONLY. Content.reload() merges whatever packs are enabled on
	# the machine running this, and a mod's balance is its own author's problem —
	# the example pack's reader would otherwise fail this suite on a fresh clone.
	# Same pack stamp tests/test_art.gd reads for the same reason.
	var base := {}
	for r in content.readers:
		if str(r.get("_pack", "parlour.base")) == "parlour.base":
			base[str(r.get("sign", ""))] = true

	var rows := sim.sim_sweep(FIGHTS)
	var by_reader := sim.sim_group(rows, "reader")

	var lowest := 1.0
	var highest := 0.0
	print("--- by reader, night 2 hour 6, difficulty 2, %d fights ---" % FIGHTS)
	for g in by_reader:
		var name := str(g["label"])
		var rate: float = g["rate"]
		if not base.has(name):
			continue
		var exempt: bool = name in CANNOT_PRICE
		print("  %-16s %5.1f%%  n=%-4d%s" % [name, rate * 100.0, g["n"], "   (not priceable here)" if exempt else ""])
		if exempt:
			continue
		lowest = minf(lowest, rate)
		highest = maxf(highest, rate)
		if rate < FLOOR:
			failures.append("%s wins %.1f%% of its readings — under the %.0f%% floor, which is a reader nobody should pick"
				% [name, rate * 100.0, FLOOR * 100.0])
		if rate > CEILING:
			failures.append("%s wins %.1f%% of its readings — over the %.0f%% ceiling, which is a reader that asks nothing"
				% [name, rate * 100.0, CEILING * 100.0])

	# And the field has to stay a field. Every reader inside the band while they
	# all sit at one end of it would pass the two checks above and still mean
	# there was only ever one choice.
	var spread := highest - lowest
	if spread > 0.45:
		failures.append("the field spans %.0f points, from %.1f%% to %.1f%% — that is a ranking, not a choice"
			% [spread * 100.0, lowest * 100.0, highest * 100.0])

	if failures.is_empty():
		print("ALL PASS — the field spans %.0f points (%.1f%% to %.1f%%), everyone inside %.0f-%.0f%%"
			% [spread * 100.0, lowest * 100.0, highest * 100.0, FLOOR * 100.0, CEILING * 100.0])
		quit(0)
	else:
		for f in failures:
			printerr("FAIL: ", f)
		quit(1)
