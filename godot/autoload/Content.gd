## Autoload. The merged, ready-to-query content registries — the base game
## plus every mod pack ModLoader found, already merged. Everything else in the
## game (Rules, Run, the UI) reads content through this singleton and never
## touches ModLoader or raw JSON directly.
extends Node

## Set to false to skip loading res://mods_example/ (useful for a "vanilla"
## smoke test). Player-provided mods in user://mods/ and Workshop items always load.
const LOAD_EXAMPLE_MODS := true

var registries: Dictionary = {}
var load_errors: Array[String] = []

var elements: Dictionary
var ring: Array
var next_el: Dictionary
var opp_el: Dictionary
var neighbors: Dictionary
var fx: Dictionary
var denial_shield: Dictionary
var card_effects: Array
var signs: Array
var jobs: Dictionary
var readers: Array
var cards_basics: Array
var cards_chroma: Array
var cards_minor: Array
var cards_arcana: Array
var relics: Array
var marks: Array
var elite_twists: Array
var sitters: Array
var boss: Dictionary
var events: Array
var shop: Dictionary

# name -> card dict, across every pool, built once after load for O(1) lookup
# (readers reference their 2 starting cards by name, rewards resolve by name, etc).
var _cards_by_name: Dictionary = {}
var _card_effects_by_key: Dictionary = {}
var _signs_by_key: Dictionary = {}
var _readers_by_key: Dictionary = {}
var _sitters_by_name: Dictionary = {}


func _ready() -> void:
	reload()


func reload() -> void:
	var loader := ModLoader.new()
	registries = loader.build_registries()
	load_errors = loader.errors
	for e in load_errors:
		push_warning("[Content] " + e)

	elements = registries.get("elements", {})
	ring = registries.get("ring", [])
	next_el = registries.get("next", {})
	opp_el = registries.get("opp", {})
	neighbors = registries.get("neighbors", {})
	fx = registries.get("fx", {})
	denial_shield = registries.get("denial_shield", {})
	card_effects = registries.get("card_effects", [])
	signs = registries.get("signs", [])
	jobs = registries.get("jobs", {})
	readers = registries.get("readers", [])
	cards_basics = registries.get("cards_basics", [])
	cards_chroma = registries.get("cards_chroma", [])
	cards_minor = registries.get("cards_minor", [])
	cards_arcana = registries.get("cards_arcana", [])
	relics = registries.get("relics", [])
	marks = registries.get("marks", [])
	elite_twists = registries.get("elite_twists", [])
	sitters = registries.get("sitters", [])
	boss = registries.get("boss", {})
	events = registries.get("events", [])
	shop = registries.get("shop", {})

	_index()


func _index() -> void:
	_cards_by_name.clear()
	for pool in [cards_basics, cards_chroma, cards_minor, cards_arcana]:
		for c in pool:
			_cards_by_name[c["n"]] = c
	_card_effects_by_key.clear()
	for e in card_effects:
		_card_effects_by_key[e["k"]] = e
	_signs_by_key.clear()
	for s in signs:
		_signs_by_key[s["k"]] = s
	_readers_by_key.clear()
	for r in readers:
		_readers_by_key[r["k"]] = r
	_sitters_by_name.clear()
	for s in sitters:
		_sitters_by_name[s["name"]] = s


func get_card(card_name: String) -> Dictionary:
	return _cards_by_name.get(card_name, {})


func has_card(card_name: String) -> bool:
	return _cards_by_name.has(card_name)


func get_card_effect(key: String) -> Dictionary:
	return _card_effects_by_key.get(key, {})


func get_sign(key: String) -> Dictionary:
	return _signs_by_key.get(key, {})


func get_reader(key: String) -> Dictionary:
	return _readers_by_key.get(key, {})


func get_sitter(sitter_name: String) -> Dictionary:
	return _sitters_by_name.get(sitter_name, {})


func get_job(role: String) -> Dictionary:
	return jobs.get(role, {"t": "", "fx": ""})


func get_fx(key: String) -> Dictionary:
	return fx.get(key, {})
