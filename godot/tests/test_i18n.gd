## Headless test for localization.
##   godot --headless --path godot -s tests/test_i18n.gd
##
## The guarantees under test:
##   - switching locale actually changes what lookups return;
##   - an untranslated string falls back to correct English rather than
##     showing a raw key (the reason the English source doubles as the key);
##   - locale data arrives through the ordinary mod pipeline, so a mod can
##     ship or override translations;
##   - the generated template covers every id the game derives at runtime,
##     so no string is unreachable by a translator.
extends SceneTree

var failures: Array[String] = []
var content: Node
var i18n: Node
var settings: Node


func _initialize() -> void:
	content = root.get_node("Content")
	i18n = root.get_node("I18n")
	settings = root.get_node("Settings")
	await process_frame
	content.reload()

	var restore: String = str(settings.get_value("locale"))

	_test_english_is_passthrough()
	_test_french_translates()
	_test_untranslated_falls_back_to_english()
	_test_locale_rides_the_mod_pipeline()
	_test_template_covers_runtime_ids()
	_test_pronoun_tokens_are_filled()
	_test_no_unfilled_tokens_anywhere()
	_test_every_t_call_is_on_the_checklist()

	settings.set_value("locale", restore)
	i18n.reload()

	if failures.is_empty():
		var cov: Dictionary = i18n.coverage("fr")
		print("ALL PASS — fr coverage %d/%d" % [cov["translated"], cov["total"]])
		quit(0)
	else:
		for f in failures:
			printerr("FAIL: ", f)
		quit(1)


## EVERY `I18n.t("…")` IN THE SOURCE IS ON THE CHECKLIST.
##
## The coverage number counts the locale table, and the table is what was
## incomplete: the UI strings were enumerated by hand in gen_locale_template.gd
## and the list had fallen about a hundred strings behind, most of the reading
## screen among them. So the French build showed "Left to draw 5" and "You have
## not said anything yet. Elle est looking at your hands." while the counter
## read 100%, because everything in the table was translated and the table did
## not know about them.
##
## The template scrapes now. This is the guard that the scrape and the source
## agree — a literal in a `.gd` file that is not a key is a string no translator
## will ever be shown.
func _test_every_t_call_is_on_the_checklist() -> void:
	var table: Dictionary = content.registries.get("locale_fr", {})
	if table.is_empty():
		failures.append("the fr table should be loaded")
		return
	var missing: Array[String] = []
	for path in _gd_files("res://scenes") + _gd_files("res://autoload"):
		for literal in _t_literals(FileAccess.get_file_as_string(path)):
			if not table.has("ui/" + literal):
				missing.append("%s: \"%s\"" % [path.get_file(), literal.substr(0, 60)])
	if not missing.is_empty():
		failures.append("%d string(s) reach I18n.t() and are on no checklist — re-run tests/gen_locale_template.gd: %s"
			% [missing.size(), ", ".join(missing.slice(0, 5))])


## The double-quoted literal directly inside an I18n.t( call — the same narrow
## rule the template's scraper uses, and deliberately the same narrowness: a
## computed argument is a key from data, covered by the content half.
func _t_literals(text: String) -> Array[String]:
	var out: Array[String] = []
	var at := 0
	while true:
		var call_at := text.find("I18n.t(\"", at)
		if call_at < 0:
			break
		var i := call_at + 8
		var s := ""
		while i < text.length():
			var c := text[i]
			if c == "\\" and i + 1 < text.length():
				s += text[i + 1] if text[i + 1] != "n" else "\n"
				i += 2
				continue
			if c == "\"":
				break
			s += c
			i += 1
		at = i + 1
		if s != "":
			out.append(s)
	return out


func _gd_files(dir_path: String) -> Array[String]:
	var out: Array[String] = []
	var d := DirAccess.open(dir_path)
	if d == null:
		return out
	d.list_dir_begin()
	var name := d.get_next()
	while name != "":
		var full := dir_path.path_join(name)
		if d.current_is_dir():
			if not name.begins_with("."):
				out.append_array(_gd_files(full))
		elif name.ends_with(".gd"):
			out.append(full)
		name = d.get_next()
	d.list_dir_end()
	return out


func check(cond: bool, label: String) -> void:
	if not cond:
		failures.append(label)


func _set_locale(loc: String) -> void:
	settings.set_value("locale", loc)
	i18n.reload()


func _test_english_is_passthrough() -> void:
	_set_locale("en")
	check(i18n.t("SETTINGS") == "SETTINGS", "English should return the source string unchanged")
	var tea: Dictionary = content.get_card("Pour The Tea")
	check(i18n.card_name(tea) == "Pour The Tea", "English card name should be the base name")


func _test_french_translates() -> void:
	_set_locale("fr")
	check(i18n.t("SETTINGS") == "PARAMÈTRES", "UI string should translate, got '%s'" % i18n.t("SETTINGS"))
	check(i18n.t("BACK") == "RETOUR", "UI string should translate, got '%s'" % i18n.t("BACK"))
	var tea: Dictionary = content.get_card("Pour The Tea")
	check(i18n.card_name(tea) == "Servir le thé", "card name should translate, got '%s'" % i18n.card_name(tea))
	var aries: Dictionary = content.get_sign("aries")
	check(i18n.sign_field(aries, "n") == "BÉLIER", "sign name should translate, got '%s'" % i18n.sign_field(aries, "n"))
	check(i18n.element_field("fire", "label") == "FEU", "element label should translate, got '%s'" % i18n.element_field("fire", "label"))


## The whole point of source-string-as-key: a string nobody has translated
## yet must render as readable English, never as a bare identifier.
func _test_untranslated_falls_back_to_english() -> void:
	_set_locale("fr")
	var never := "This string is deliberately not in any locale file."
	check(i18n.t(never) == never, "an unknown UI string should come back unchanged")
	# Card flavor is intentionally left untranslated in the shipped fr file
	# (it's the game's authorial voice — see docs/LOCALIZATION.md), so it is
	# a real example of the fallback path rather than a synthetic one.
	var tea: Dictionary = content.get_card("Pour The Tea")
	var flavor: String = i18n.card_flavor(tea)
	check(flavor != "", "flavor should never come back empty")
	check(not flavor.begins_with("card/"), "flavor must fall back to prose, not leak a key: '%s'" % flavor)


func _test_locale_rides_the_mod_pipeline() -> void:
	check(content.registries.has("locale_fr"), "the fr table should be a merged registry like any other content")
	var table: Dictionary = content.registries["locale_fr"]
	check(table.size() > 300, "fr table should carry the full key set, got %d" % table.size())


## Every id the game asks I18n for at runtime must exist in the template, or
## a translator has no way to reach that string.
func _test_template_covers_runtime_ids() -> void:
	var f := FileAccess.open("res://data/base/locale/fr.json", FileAccess.READ)
	check(f != null, "fr.json should exist")
	if f == null:
		return
	var doc = JSON.parse_string(f.get_as_text())
	f.close()
	var src: Dictionary = doc.get("_source", {})
	check(not src.is_empty(), "template should carry the English source block")

	var art: Node = root.get_node("Art")
	var missing: Array[String] = []
	for c in content.cards_minor:
		if not src.has(art.card_id(c) + "/n"):
			missing.append(art.card_id(c))
	for s in content.sitters:
		if not src.has(art.sitter_id(s) + "/brings"):
			missing.append(art.sitter_id(s))
	for r in content.readers:
		if not src.has(art.reader_id(r) + "/line"):
			missing.append(art.reader_id(r))
	for sg in content.signs:
		if not src.has("sign/%s/rule" % sg["k"]):
			missing.append("sign/" + str(sg["k"]))
	check(missing.is_empty(), "template is missing ids: %s" % ", ".join(missing.slice(0, 8)))


## fill()/PRON, which the first porting pass missed entirely: sign rules are
## written with {S}/{es}/{o} tokens and were being shown to the player raw.
func _test_pronoun_tokens_are_filled() -> void:
	# Pin the locale: the tests above leave it on "fr", and with French pronoun
	# words now translated but the sentences around them not, the lookup would
	# correctly return "Elle needs it to be a performance" — right behaviour for
	# a half-finished locale, wrong thing to assert English agreement against.
	settings.set_value("locale", "en")
	i18n.reload()
	var leo: Dictionary = content.get_sign("leo")
	var she := {"p": "she"}
	var they := {"p": "they"}
	# The FLAVOUR half. A sign says two things — what they are like (`fl`) and
	# what that does (`rule`) — and the pronoun tokens are mostly in the first,
	# because it is the half that talks about the person.
	var f_she: String = i18n.sign_flavour(leo, she)
	var f_they: String = i18n.sign_flavour(leo, they)
	check(f_she.begins_with("She needs it"), "she/singular agreement, got '%s'" % f_she)
	check(f_they.begins_with("They need it"), "they/plural agreement, got '%s'" % f_they)
	# And the RULE half, which carries them too — Capricorn's is "Fire restores
	# nothing at {p} table." Both go through fill(), and a fix to one that
	# missed the other would have gone unnoticed with only the check above.
	var cap: Dictionary = content.get_sign("capricorn")
	var r_she: String = i18n.sign_rule(cap, she)
	var r_they: String = i18n.sign_rule(cap, they)
	check(r_she.contains("her table"), "she/possessive in a rule, got '%s'" % r_she)
	check(r_they.contains("their table"), "they/possessive in a rule, got '%s'" % r_they)
	# A job's flavour is filled by the same path and had no check at all.
	var laundress: Dictionary = content.get_job("THE LAUNDRESS")
	var j: String = i18n.fill(i18n.job_flavour("THE LAUNDRESS", laundress), "they")
	check(not j.contains("{"), "a job flavour still shows raw tokens: '%s'" % j)

	# A sitter with no pronoun field at all must not fall through to raw tokens.
	check(not i18n.sign_rule(leo, {}).contains("{"), "a sitter with no pronoun should still fill")

	# An unknown token stays visible rather than silently eating the sentence.
	check(i18n.fill("a {nosuchtoken} b", "she") == "a {nosuchtoken} b", "unknown tokens should be left alone")
	check(i18n.fill("no tokens here", "she") == "no tokens here", "token-free text should pass through")


## Nothing the player can be shown should still contain a {token}. This is the
## check that would have caught the missing fill() in the first place, so it
## covers every token-bearing field rather than just the one that was noticed.
func _test_no_unfilled_tokens_anywhere() -> void:
	for pronoun in ["she", "he", "they"]:
		for sg in content.signs:
			var out: String = i18n.fill(str(sg.get("rule", "")), pronoun)
			check(not out.contains("{"), "sign %s leaves a raw token for '%s': %s" % [sg.get("k", ""), pronoun, out])
		for tw in content.elite_twists:
			var out2: String = i18n.fill(str(tw.get("t", "")), pronoun)
			check(not out2.contains("{"), "twist %s leaves a raw token for '%s': %s" % [tw.get("tag", ""), pronoun, out2])
		for role in content.jobs:
			var out3: String = i18n.fill(str(content.jobs[role].get("t", "")), pronoun)
			check(not out3.contains("{"), "job %s leaves a raw token for '%s': %s" % [role, pronoun, out3])
