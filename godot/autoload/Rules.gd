## Autoload. The scoring engine — a faithful line-for-line port of
## elOf()/linkOf()/simulate() from Parlour v23.dc.html (~lines 2034-2129),
## plus the small helpers they lean on (has()/myEl()/elBonus(), ~1775-1816).
##
## Per HANDOFF.md this is meant to be THE single source of truth for scoring:
## both a live per-card preview and the actual reading resolution should call
## simulate() and nothing else. Kept pure and stateless on purpose — every
## function takes its context as parameters instead of reading a global run
## state, so it can be unit-tested head-on (see tests/test_rules.gd) without
## booting a scene tree.
##
## Context shapes, by convention (plain Dictionaries, matching the JSON schema
## in data/base/*.json so a card/sign/job/reader record can be passed straight
## from Content with no translation step):
##   run_ctx = { "reader": <reader dict>, "marks": [<mark/relic dict>, ...], "serp_el": <element key or ""> }
##   fight   = { "sitter", "quirk" (a sign dict), "job" (a job dict), "el" (sitter's element),
##               "max", "hp", "denial", "denialUp", "turn", "turns",
##               "cross": [<card dict>, ...]   -- cards laid this reading, in spoken order
##             }
extends Node


func has(run_ctx: Dictionary, fx_key: String) -> bool:
	var reader: Dictionary = run_ctx.get("reader", {})
	if reader.get("fx", "") == fx_key:
		return true
	for m in run_ctx.get("marks", []):
		if m.get("fx", "") == fx_key:
			return true
	return false


func my_el(run_ctx: Dictionary) -> String:
	var reader: Dictionary = run_ctx.get("reader", {})
	if has(run_ctx, "serpent"):
		var se: String = run_ctx.get("serp_el", "")
		return se if se != "" else reader.get("el", "")
	return reader.get("el", "")


## Mirrors elBonus(el) (~1813): the flat table-wide bonus a card of element
## `el` gets from elemental marks/relics plus the reader's own-element bonus
## (own3/serpent give +3 instead of the default +1).
func el_bonus(run_ctx: Dictionary, el: String) -> int:
	if el == "":
		return 0
	var own := el == my_el(run_ctx)
	var mark_bonus := 0
	for m in run_ctx.get("marks", []):
		if m.get("fx", "") == "el" and m.get("el", "") == el:
			mark_bonus += 2
	var own_bonus := 0
	if own:
		own_bonus = 3 if (has(run_ctx, "serpent") or has(run_ctx, "own3")) else 1
	return mark_bonus + own_bonus


## Mirrors elOf(f, c) (~2034): the *effective* element of a laid card given the
## current fight — chroma cards take the reader's current element, wild/any
## cards take the sitter's element, everything else is just its own el.
func el_of(run_ctx: Dictionary, fight: Dictionary, card: Dictionary) -> String:
	if card.get("chroma", false):
		return my_el(run_ctx)
	if card.get("wild", false) or card.get("any", false):
		return fight.get("el", "")
	return card.get("el", "") if card.get("el") != null else ""


## Mirrors linkOf(f, carried, cur) (~2037): classifies how `cur`'s element
## relates to the element `carried` over from the previous non-neutral card.
func link_of(run_ctx: Dictionary, fight: Dictionary, carried: String, cur: Dictionary) -> String:
	var b := el_of(run_ctx, fight, cur)
	if b == "" or cur.get("neutral", false):
		return "flat"
	if carried == "":
		return "open"
	if carried == b:
		return "same"
	var elements: Dictionary = Content.next_el
	if elements.get(carried, "") == b:
		return "turn"
	if elements.get(b, "") == carried:
		return "back"
	return "break"


## Mirrors simulate(f) (~2048-2129): resolves the whole laid line (fight.cross)
## in spoken order and returns the same shape the source does — rows (per-card
## breakdown), gross/pierced/absorbed/applied totals, bank (faith-only cards),
## over (composure overflow -> faith), hpAfter, extraTurns, coin, and
## shieldNext (what the sitter's denial wall grows to for their next reading).
func simulate(run_ctx: Dictionary, fight: Dictionary) -> Dictionary:
	var quirk: Dictionary = fight.get("quirk", {})
	var laid: Array = fight.get("cross", [])
	var pierce_trait := 4 if has(run_ctx, "pierce") else 0
	var blank := {
		"rows": [], "gross": 0, "pierced": 0, "absorbed": 0, "applied": 0, "bank": 0, "over": 0,
		"hpAfter": fight.get("hp", 0), "extraTurns": 0, "coin": 0, "halveNote": null,
		"denial": max(0, fight.get("denial", 0) - pierce_trait),
		"shieldNext": fight.get("denial", 0) + fight.get("denialUp", 0),
	}
	if laid.is_empty():
		return blank

	var pending := 0
	var gross := 0
	var pierced := 0
	var bank := 0
	var extra_turns := 0
	var coin := 0
	var rows: Array = []
	var said: Array = []
	var job: Dictionary = fight.get("job", {})
	var no_bonus: bool = quirk.get("fx", "") == "nobonus"

	var carried := ""
	for n in laid.size():
		var c: Dictionary = laid[n]
		var prev: Dictionary = laid[n - 1] if n > 0 else {}
		var link := link_of(run_ctx, fight, carried, c)
		var is_last := n == laid.size() - 1
		var el := el_of(run_ctx, fight, c)
		var follows_kind: String = c.get("follows", "")
		var follows: bool = c.has("follows") and not prev.is_empty() and (
			(follows_kind == "same" and link == "same") or (follows_kind == "turn" and link == "turn")
		)

		var b: int = int(c.get("f", 0)) + el_bonus(run_ctx, el) + pending
		pending = 0
		if c.has("perEl") and c.has("perAmt"):
			var count := 0
			for x in laid:
				if x != c and el_of(run_ctx, fight, x) == c["perEl"]:
					count += 1
			b += int(c["perAmt"]) * count
		if c.has("bonusFlat"):
			b += int(c["bonusFlat"])
		if c.has("solo") and laid.size() == 1:
			b += int(c["solo"])
		if c.has("perLaid"):
			b += int(c["perLaid"]) * n
		if follows and not no_bonus:
			b += int(c.get("bonus", 0))
		if not no_bonus and n == 0:
			if c.has("opener"):
				b += int(c["opener"])
			if has(run_ctx, "opener"):
				b += 2
			if job.get("fx", "") == "opener3":
				b += 3
		if not no_bonus and is_last:
			if c.has("closer"):
				b += int(c["closer"])
			if has(run_ctx, "closer"):
				b += 3
			if job.get("fx", "") == "closer3":
				b += 3
		if link == "same":
			if has(run_ctx, "steady"):
				b += 2
			if job.get("fx", "") == "steady3":
				b += 3
		if link == "turn" and has(run_ctx, "switch2"):
			b += 2
		if el != "" and has(run_ctx, "perOwn") and el == my_el(run_ctx):
			var count2 := 0
			for x in laid:
				if x != c and el_of(run_ctx, fight, x) == el:
					count2 += 1
			b += count2
		if c.get("neutral", false) and has(run_ctx, "white"):
			b += 3
		if el != "" and el == fight.get("el", ""):
			b += 2

		var total: int = max(0, b)
		var qfx: String = quirk.get("fx", "")
		if qfx == "mutefirst" and n == 0:
			total = 0
		if qfx == "lasthalf" and is_last:
			total = int(floor(total / 2.0))
		if qfx == "halfown" and el == fight.get("el", ""):
			total = int(floor(total / 2.0))
		if qfx == "deadel" and el == quirk.get("dead", ""):
			total = 0
		if qfx == "norepeat" and el != "" and said.has(el):
			total = 0
		if el != "":
			said.append(el)

		if c.has("turn"):
			extra_turns += int(c["turn"])
		if c.has("coin"):
			coin += int(c["coin"])
		var is_bank: bool = c.get("bank", false)
		if is_bank:
			bank += total
		else:
			gross += total
			if c.get("pierce", false):
				pierced += total

		if c.has("next"):
			pending = int(c["next"])
		if el != "" and not c.get("neutral", false):
			carried = el

		var notes: Array = []
		if n == 0:
			notes.append("opens")
		elif is_last:
			notes.append("closes")
		if follows:
			notes.append("follows well")
		if c.get("pierce", false):
			notes.append("past denial")
		if is_bank:
			notes.append("into your faith")
		rows.append({
			"i": n, "name": c.get("n", ""), "el": el, "total": total,
			"bank": is_bank, "pierce": c.get("pierce", false), "link": link,
			"note": " · ".join(notes),
		})

	if quirk.get("fx", "") == "halfbest" and not rows.is_empty():
		var bi := 0
		for n in rows.size():
			if rows[n]["total"] > rows[bi]["total"]:
				bi = n
		var cut: int = rows[bi]["total"] - int(floor(rows[bi]["total"] / 2.0))
		if cut > 0 and not rows[bi]["bank"]:
			rows[bi]["total"] -= cut
			rows[bi]["note"] = (rows[bi]["note"] + " · " if rows[bi]["note"] != "" else "") + "taken back inside"
			gross = max(0, gross - cut)
			if rows[bi]["pierce"]:
				pierced = max(0, pierced - cut)

	var halve_note = null
	if quirk.get("fx", "") == "minthree" and laid.size() < 3:
		gross = 0
		pierced = 0
		halve_note = "fewer than three — wants a performance"

	var denial: int = max(0, fight.get("denial", 0) - pierce_trait)
	var soft: int = gross - pierced
	var absorbed: int = min(denial, soft)
	var applied: int = pierced + max(0, soft - absorbed)
	var max_hp: int = fight.get("max", 0)
	var hp_after: int = min(max_hp, fight.get("hp", 0) + applied)
	var over: int = max(0, fight.get("hp", 0) + applied - max_hp)

	return {
		"rows": rows, "gross": gross, "pierced": pierced, "denial": denial, "absorbed": absorbed,
		"applied": applied, "bank": bank, "over": over, "hpAfter": hp_after, "extraTurns": extra_turns,
		"coin": coin, "halveNote": halve_note, "shieldNext": denial + fight.get("denialUp", 0),
	}


## Mirrors autoText(c) (~1251): generates a card's printed effect text from its
## mechanical fields, so a moddable card never needs its text hand-written
## unless it explicitly sets custom=true.
func auto_text(card: Dictionary) -> String:
	var el: Dictionary = Content.elements
	var glyph_of = func(k): return el.get(k, {}).get("glyph", "")
	var numw = ["no", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten", "eleven", "twelve"]
	var word = func(n: int) -> String: return numw[n] if n >= 0 and n < numw.size() else str(n)
	var capw = func(s: String) -> String: return s.substr(0, 1).to_upper() + s.substr(1)
	var prev_el := {"earth": "fire", "air": "earth", "water": "air", "fire": "water"}

	var p: Array = []
	if card.get("wild", false):
		p.append("Counts as every element.")
	if card.get("chroma", false):
		p.append("Counts as whatever your element is now.")
	if card.get("any", false):
		p.append("Reads as whatever element they answer to.")
	if card.has("bonusFlat"):
		p.append("Restores %d more." % card["bonusFlat"])
	if card.has("follows") and card.has("bonus"):
		var target_el: String = card.get("el", "") if card["follows"] == "same" else prev_el.get(card.get("el", ""), "")
		p.append("+%d more if it follows %s." % [card["bonus"], glyph_of.call(target_el)])
	if card.has("opener"):
		p.append("+%d more if you say it first." % card["opener"])
	if card.has("closer"):
		p.append("+%d more if you say it last." % card["closer"])
	if card.has("solo"):
		p.append("Restores %d more if it is the only thing you say." % card["solo"])
	if card.has("perLaid"):
		p.append("Restores %d more for every card said before it." % card["perLaid"])
	if card.has("perEl") and card.has("perAmt"):
		p.append("+%d for every other %s in the reading." % [card["perAmt"], glyph_of.call(card["perEl"])])
	if card.has("next"):
		p.append("Whatever you say next restores %d more." % card["next"])
	if card.has("energy"):
		p.append("%s energy back." % capw.call(word.call(int(card["energy"]))))
	if card.has("draw"):
		p.append("Draw %s." % word.call(int(card["draw"])))
	if card.has("coin"):
		p.append("%s centimes." % capw.call(word.call(int(card["coin"]))))
	if card.has("turn"):
		p.append("One reading longer." if card["turn"] == 1 else "%s readings longer." % capw.call(word.call(int(card["turn"]))))
	if card.get("bank", false):
		p.append("Restores faith instead of composure.")
	if card.get("pierce", false):
		p.append("Straight through their denial.")
	if card.get("exhaust", false):
		p.append("Once.")
	return " ".join(p)
