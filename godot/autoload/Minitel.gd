## Autoload. The Minitel: dial 3615, type a four-letter code, press ENVOI.
##
## This is the game's secret-code channel, and it is deliberately built as
## MACHINERY WITH ALMOST NO CONTENT. The codes themselves are the author's to
## write — what lives here is validation, persistence, and the three levers a
## code can pull. Two demonstrator codes ship so the feature is exercised
## rather than merely present (the same reasoning as the example pack's locked
## reader); they are marked as such in data/base/minitel.json and are meant to
## be replaced.
##
## WHY IT FITS THE EXISTING SYSTEMS. A code does not get its own progression
## store. Entering one appends it to the `codes_entered` profile stat, and
## Profile.meets() already understands `{"stat": "codes_entered", "includes":
## "OEIL"}` — so any reader's `unlock` condition can be gated behind a code
## with no new code at all. The other two levers are equally small:
##
##   grants  {stat, add}  bumps a numeric profile stat (see Profile.STATS)
##   arms    <event title> makes a `secret: true` event eligible on the map
##
## Three levers, all data, all checkable. A general effect language would be
## more than anyone has asked for and impossible to validate; an unknown stat
## or a missing event is reported here rather than silently doing nothing —
## which is precisely the failure mode docs/PORTING_NOTES.md keeps recording.
extends Node

## The tariff prefix. Historically there were several (3611, 3614, 3615,
## 3617...) at different per-minute rates; 3615 is the one everyone remembers,
## so it is the only one the game accepts. Kept as a constant rather than
## inlined so a mod-facing change stays a one-line change.
const PREFIX := "3615"

## Codes are exactly four letters. A Minitel service code was a short word you
## read off a magazine ad or a TV corner, and four letters is both period-true
## and long enough that guessing is not a strategy (456,976 combinations).
const CODE_LENGTH := 4

## Result kinds from submit(), so callers switch on a value rather than
## sniffing the text.
const OK := "ok"
const ALREADY := "already"
const UNKNOWN := "unknown"
const BAD_FORMAT := "bad_format"

## The terminal's own words. NOT run through I18n, deliberately, and the only
## strings in the game that are exempt.
##
## Everything else in this port is source-English-as-key with a locale file
## beside it. A Minitel is not part of the interface, though: it is a French
## object sitting in the parlour, and it printed French — unaccented, in
## capitals, because the character set it had could do nothing else. Putting
## these through I18n would mean a German player's Minitel greets them in
## German, which is not a translation of anything, and would invite a
## translator to render "ANNUAIRE ELECTRONIQUE" as if it were UI chrome.
##
## The chrome AROUND the machine — the button that opens it, the list of
## services you have reached — is ordinary UI and is translated as usual. The
## line is between the game talking to the player and the machine talking to
## the player. Codes supply their own `screen` text and, being content, remain
## translatable (a mod set in another country may want its own terminal).
const SAY_FORMAT := "COMPOSEZ 3615 PUIS QUATRE LETTRES."
const SAY_UNKNOWN := "SERVICE NON DISPONIBLE."
const SAY_ALREADY := "DEJA CONNECTE A CE SERVICE."
const SAY_CONNECTED := "CONNEXION ETABLIE."
const SAY_IDLE := "ANNUAIRE ELECTRONIQUE"


## Normalises what the player typed into a canonical code, or "" if it cannot
## be one. Uppercases, strips accents (a Minitel keyboard had no way to enter
## them into a service code) and rejects anything that is not four letters.
func normalise(raw: String) -> String:
	var out := ""
	for ch in raw.strip_edges().to_upper():
		var c := _deaccent(ch)
		if c >= "A" and c <= "Z":
			out += c
		elif c != " " and c != "-":
			return ""   # a digit or symbol means this was never a code
	return out if out.length() == CODE_LENGTH else ""


func _deaccent(ch: String) -> String:
	const FROM := ["À", "Â", "Ä", "Ç", "É", "È", "Ê", "Ë", "Î", "Ï", "Ô", "Ö", "Ù", "Û", "Ü"]
	const TO := ["A", "A", "A", "C", "E", "E", "E", "E", "I", "I", "O", "O", "U", "U", "U"]
	var i := FROM.find(ch)
	return TO[i] if i >= 0 else ch


func known(code: String) -> bool:
	return Content.minitel_codes.has(normalise(code))


func entered() -> Array:
	return Array(Profile.get_stat("codes_entered"))


## Dials `prefix` and submits `raw`. Returns
## {kind, code, lines} — `lines` is what the Minitel prints, ready to show,
## and is never empty so the screen always says something.
##
## Everything is refused politely: a wrong prefix, a code that is not four
## letters, a code nobody wrote. A terminal that goes blank on bad input is
## indistinguishable from a broken one.
func submit(prefix: String, raw: String) -> Dictionary:
	var code := normalise(raw)
	if prefix.strip_edges() != PREFIX or code == "":
		return {"kind": BAD_FORMAT, "code": code, "lines": [SAY_FORMAT]}

	var rec: Dictionary = Content.minitel_codes.get(code, {})
	if rec.is_empty():
		return {"kind": UNKNOWN, "code": code, "lines": [SAY_UNKNOWN]}

	var seen := entered()
	var repeatable := bool(rec.get("repeatable", false))
	if seen.has(code) and not repeatable:
		return {"kind": ALREADY, "code": code, "lines": _lines(code, rec) + [SAY_ALREADY]}

	if not seen.has(code):
		seen.append(code)
		Profile.set_stat("codes_entered", seen)
	_apply(code, rec)
	return {"kind": OK, "code": code, "lines": _lines(code, rec)}


## The service's own text, from content (so it translates and mods can write
## their own). Falls back to something rather than nothing.
func _lines(code: String, rec: Dictionary) -> Array:
	var out: Array = []
	var screen: Array = rec.get("screen", [])
	for i in screen.size():
		# One key PER LINE, not one for the whole block. Keying them all as
		# "minitel/<CODE>/screen" (the obvious first cut, and what this did)
		# meant a translated service printed its first line four times over —
		# invisible in English, where every lookup misses and falls back to the
		# line itself. Same shape as the event options' opt0/opt1 keys.
		out.append(I18n.content("minitel/" + code, "screen%d" % i, str(screen[i])))
	if out.is_empty():
		out.append(SAY_CONNECTED)
	return out


func _apply(code: String, rec: Dictionary) -> void:
	var grants: Dictionary = rec.get("grants", {})
	if not grants.is_empty():
		var stat := str(grants.get("stat", ""))
		if not Profile.STATS.has(stat):
			push_warning("[Minitel] %s grants unknown stat '%s'; ignored." % [code, stat])
		elif typeof(Profile.STATS[stat]) == TYPE_ARRAY:
			push_warning("[Minitel] %s grants list stat '%s'; only numbers can be added to." % [code, stat])
		else:
			Profile.set_stat(stat, int(Profile.get_stat(stat)) + int(grants.get("add", 0)))

	var arms := str(rec.get("arms", ""))
	if arms != "" and _secret_event(arms).is_empty():
		push_warning("[Minitel] %s arms '%s', which is not a secret event." % [code, arms])


## Secret events armed by a code the player has entered. Run.make_options()
## asks for these; they are excluded from the ordinary random pool by their
## `secret` flag, so an unarmed one can never turn up on its own.
func armed_events() -> Array:
	var out: Array = []
	for code in entered():
		var rec: Dictionary = Content.minitel_codes.get(str(code), {})
		var arms := str(rec.get("arms", ""))
		if arms == "":
			continue
		var ev := _secret_event(arms)
		if not ev.is_empty():
			out.append(ev)
	return out


func _secret_event(title: String) -> Dictionary:
	for e in Content.events:
		if str(e.get("title", "")) == title and bool(e.get("secret", false)):
			return e
	return {}
