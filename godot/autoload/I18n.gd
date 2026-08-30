## Autoload. Localization for both halves of the game's text.
##
## There are two kinds of translatable string here and they need different
## handling, so this exposes two lookups:
##
##  1. UI chrome — "SETTINGS", "BACK", "YOUR HAND". Written in .gd files.
##     Looked up with t(). The ENGLISH SOURCE STRING IS THE KEY (the gettext
##     approach) rather than an invented code like UI_SETTINGS_TITLE: the
##     call sites stay readable, no key registry has to be kept in sync, and
##     an untranslated string falls back to correct English instead of
##     showing a raw key to the player.
##
##  2. Content — card names, flavor, sitter dialogue, sign rules. Lives in
##     data/*.json, is moddable, and is addressed by the SAME slug ids the
##     art manifest uses (card/pour-the-tea, sitter/mme-perrot), plus the
##     field: "card/pour-the-tea/n". Looked up with content().
##
## Locale data rides the ordinary mod pipeline: a locale file is just another
## registry ("locale_fr") merged by ModLoader like any other, so a mod ships
## translations — of its own content or of the base game's — exactly the way
## it ships cards, with no separate mechanism.
extends Node

signal locale_changed

## Locales offered in Settings. "en" is the source language: the base JSON
## and the .gd string literals ARE English, so it needs no locale file.
const LOCALES := {
	"en": "English",
	"fr": "Français",
}

var _strings: Dictionary = {}


func _ready() -> void:
	reload()
	Settings.changed.connect(func(key: String):
		if key == "locale" or key == "":
			reload()
	)


func current() -> String:
	var loc: String = str(Settings.get_value("locale"))
	return loc if LOCALES.has(loc) else "en"


func reload() -> void:
	var loc := current()
	_strings = {} if loc == "en" else Content.registries.get("locale_" + loc, {})
	# TranslationServer isn't used for lookups (this class owns them) but
	# keeping it in step means any built-in Godot control that localizes
	# itself — file dialogs, default button text — follows the same setting.
	TranslationServer.set_locale(loc)
	locale_changed.emit()


## UI chrome. Pass the English source string; get the translation, or the
## source back unchanged when there isn't one.
func t(source: String) -> String:
	if source == "":
		return source
	return _lookup("ui/" + source, source)


## Content field. `id` is the art-manifest-style slug id, `field` the JSON
## key ("n" for name, "fl" for flavor, ...). `fallback` is the base-language
## value already loaded from the data files, returned unchanged when no
## translation exists.
func content(id: String, field: String, fallback: String) -> String:
	if id == "":
		return fallback
	return _lookup("%s/%s" % [id, field], fallback)


## An EMPTY value in a locale table means "not translated yet", not
## "translate this to nothing". The generated template pre-creates every key
## with an empty string so a translator can see the full checklist, so
## without this a half-finished locale would blank out most of the game
## rather than showing English for the parts nobody has reached yet.
func _lookup(key: String, fallback: String) -> String:
	var hit: String = str(_strings.get(key, ""))
	return hit if hit.strip_edges() != "" else fallback


# ── convenience wrappers for the shapes the UI actually passes around ────
# These take the record itself so callers don't have to know the id scheme.

func card_name(card: Dictionary) -> String:
	return content(Art.card_id(card), "n", str(card.get("n", "")))


func card_flavor(card: Dictionary) -> String:
	return content(Art.card_id(card), "fl", str(card.get("fl", "")))


func sitter_field(sitter: Dictionary, field: String) -> String:
	return content(Art.sitter_id(sitter), field, str(sitter.get(field, "")))


func reader_field(reader: Dictionary, field: String) -> String:
	return content(Art.reader_id(reader), field, str(reader.get(field, "")))


func sign_field(sign: Dictionary, field: String) -> String:
	return content("sign/" + str(sign.get("k", "")), field, str(sign.get(field, "")))


func job_text(role: String, job: Dictionary) -> String:
	return content("job/" + Art.slug(role), "t", str(job.get("t", "")))


func element_field(el: String, field: String) -> String:
	var rec: Dictionary = Content.elements.get(el, {})
	return content("element/" + el, field, str(rec.get(field, "")))


## How complete a locale is, for the Settings readout and the generator's
## report. Returns {translated, total}.
func coverage(loc: String) -> Dictionary:
	if loc == "en":
		return {"translated": 0, "total": 0}
	var table: Dictionary = Content.registries.get("locale_" + loc, {})
	var translated := 0
	for k in table:
		if str(table[k]).strip_edges() != "":
			translated += 1
	return {"translated": translated, "total": table.size()}
