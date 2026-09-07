## Headless test for the audio layer.
##   godot --headless --path godot -s tests/test_audio.gd
##
## Runs under the dummy audio driver, so nothing is heard — what is under test
## is the wiring, which is the part that breaks silently:
##   - Audio.EVENTS and data/base/sounds.json cover exactly the same keys. A
##     renamed event would otherwise just stop making a sound, and a registry
##     entry for an event nobody fires would sit there looking like it worked;
##   - every registered sound resolves to a file that actually loads;
##   - an unknown event, and a registered sound whose file is missing, are both
##     silence rather than an error — the same contract Art.gd has for missing
##     art, and the reason the game is playable with no audio at all;
##   - the sounds registry rides the mod pipeline like every other category;
##   - each moment plays on the bus its volume slider drives. Three sliders are
##     only worth having if the sounds are actually split between them, and a
##     sound on the wrong bus is exactly the kind of thing nobody notices until
##     someone turns a slider down and the wrong things go quiet.
extends SceneTree

const TESTS := [
	"_test_events_and_registry_agree",
	"_test_every_sound_resolves",
	"_test_missing_and_unknown_are_silent",
	"_test_registry_is_moddable",
	"_test_events_reach_the_right_bus",
	"_test_every_cue_resolves",
	"_test_a_cue_is_idempotent_and_crossfades",
	"_test_every_screen_asks_for_music_that_exists",
	"_test_every_entry_states_a_known_status",
	"_test_delivered_audio_and_the_registries_agree",
	"_test_the_guide_states_the_same_vocabulary",
	"_test_the_credits_count_the_audio_rather_than_claiming",
]

var failures: Array[String] = []
var finished: Dictionary = {}
var content: Node
var audio: Node


func _initialize() -> void:
	content = root.get_node("Content")
	audio = root.get_node("Audio")
	await process_frame
	content.reload()

	for t in TESTS:
		call(t)
		if not finished.has(t):
			failures.append("%s aborted before finishing — see the SCRIPT ERROR above" % t)

	if failures.is_empty():
		print("ALL PASS — %d sounds registered" % content.sounds.size())
		quit(0)
	else:
		for f in failures:
			printerr("FAIL: ", f)
		quit(1)


func check(cond: bool, label: String) -> void:
	if not cond:
		failures.append(label)


func done(name: String) -> void:
	finished[name] = true


## The drift guard. Audio.EVENTS is the authority on what the game announces;
## sounds.json is what it plays. Either list growing without the other is a
## bug that makes no noise — literally.
func _test_events_and_registry_agree() -> void:
	for event in audio.EVENTS:
		check(content.sounds.has(event),
			"Audio.EVENTS has '%s' but sounds.json does not — that moment is silent" % event)
	for key in content.sounds:
		check(audio.EVENTS.has(key),
			"sounds.json has '%s' but nothing fires it — dead registry entry" % key)
	done("_test_events_and_registry_agree")


func _test_every_sound_resolves() -> void:
	for event in content.sounds:
		var stream = audio._stream_for(event, content.sounds[event])
		check(stream != null, "'%s' resolves to nothing — check its file" % event)
	done("_test_every_sound_resolves")


## The whole point of the fallback: no audio present must be a quiet game, not
## a broken one.
func _test_missing_and_unknown_are_silent() -> void:
	audio.play("no_such_event_at_all")
	audio.reload()
	# A registered sound whose file has gone (a mod uninstalled, an asset not
	# yet delivered) takes the same path.
	var stream = audio._stream_for("ghost", {"file": "res://assets/audio/does-not-exist.wav"})
	check(stream == null, "a missing file should resolve to null, got %s" % stream)
	audio.play("ghost")
	check(true, "reaching here at all means neither call errored")
	done("_test_missing_and_unknown_are_silent")


## `sounds` rides the ordinary content pipeline, so a mod repoints one the same
## way it overrides a card — including pointing at its own folder.
##
## Deliberately checks this through Content rather than by instantiating
## ModLoader: a `-s` script is compiled before autoload globals are registered,
## and ModLoader names Workshop directly, so `ModLoader.new()` here fails to
## compile the whole test file. That is the same trap Nav.gd's header
## describes, and it is easy to walk into twice.
func _test_registry_is_moddable() -> void:
	check(not content.sounds.is_empty(), "sounds should have come through the registry pipeline")
	check(content.registries.has("sounds"), "'sounds' should be a registry like any other")

	# A res:// or user:// path is taken as-is; a bare filename resolves under
	# assets/audio/. Both matter: the first is how a mod ships its own audio.
	var own: AudioStream = audio._stream_for("x", {"file": "res://assets/audio/card_lay.wav"})
	check(own != null, "an explicit res:// path should load")
	audio.reload()
	var bare: AudioStream = audio._stream_for("x", {"file": "card_lay.wav"})
	check(bare != null, "a bare filename should resolve under assets/audio/")
	audio.reload()
	done("_test_registry_is_moddable")


## Interface moments on the UI bus, everything else on SFX. Played for real
## (under the dummy driver) and the voice inspected, rather than reading
## UI_EVENTS back at itself — the question is what play() does, not what the
## table says.
func _test_events_reach_the_right_bus() -> void:
	for event in audio.EVENTS:
		audio.play(event)
		# play() advances _next after using a voice, so the one it just used is
		# the previous index.
		var voice: AudioStreamPlayer = audio._players[(audio._next - 1 + audio.VOICES) % audio.VOICES]
		var want := "UI" if audio.UI_EVENTS.has(event) else "SFX"
		check(voice.bus == want, "'%s' should play on %s, played on %s" % [event, want, voice.bus])
		check(AudioServer.get_bus_index(voice.bus) >= 0, "bus '%s' should exist" % voice.bus)
	done("_test_events_reach_the_right_bus")


## THE LOOPING HALF. Same promise as the one-shots: every cue the registry lists
## has to resolve to a real stream, or it is a track in a manifest that plays
## silence and nobody would ever know.
func _test_every_cue_resolves() -> void:
	check(not content.music.is_empty(), "there should be music and room tone registered")
	for cue in content.music:
		var rec: Dictionary = content.music[cue]
		check(str(rec.get("kind", "")) in ["music", "ambience"],
			"%s should say whether it is music or ambience, got '%s'" % [cue, rec.get("kind", "")])
		check(audio._loop_stream(cue, rec) != null,
			"%s is in the registry and resolves to nothing — it would play silence" % cue)
	done("_test_every_cue_resolves")


## ASKING FOR WHAT IS ALREADY PLAYING MUST COST NOTHING. Nav cues on every
## screen change, so "the same music as the last screen" is the common case; if
## that restarted the track, walking between two menus would stutter the score.
##
## And a real change has to be a CROSSFADE, which means the outgoing player is
## still audible while the incoming one comes up — checked as "two players, both
## carrying something" rather than by listening, which a headless test cannot do.
func _test_a_cue_is_idempotent_and_crossfades() -> void:
	audio.hush()
	audio.music("parlour")
	var pair: Array = audio._loops["music"]
	var up: AudioStreamPlayer = pair[0] if pair[0].playing else pair[1]
	check(up.playing, "asking for a track should start one playing")
	var stream := up.stream

	audio.music("parlour")
	check(up.stream == stream and up.playing,
		"asking again for what is playing must not restart it")

	audio.music("the_table")
	var other: AudioStreamPlayer = pair[1] if up == pair[0] else pair[0]
	check(other.playing, "a change should bring the other player up")
	check(up.playing, "and leave the old one running while it fades — that is the crossfade")
	check(str(audio.playing["music"]) == "the_table",
		"the channel should know what it is on, says '%s'" % audio.playing["music"])

	# A cue nothing is written for leaves what is playing alone, rather than
	# dropping the score to silence for a screen somebody forgot to fill in.
	audio.music("no_such_track")
	check(str(audio.playing["music"]) == "the_table",
		"an unwritten cue should change nothing, went to '%s'" % audio.playing["music"])
	audio.hush()
	done("_test_a_cue_is_idempotent_and_crossfades")


## EVERY SCREEN'S CUE NAMES A REAL TRACK. Nav's table is written by hand and a
## typo in it is silence on one screen — the exact failure this whole file
## exists to make impossible for the one-shots.
func _test_every_screen_asks_for_music_that_exists() -> void:
	var nav: Node = root.get_node("Nav")
	for path in nav.MUSIC_FOR:
		var cue: String = str(nav.MUSIC_FOR[path])
		check(content.music.has(cue),
			"%s asks for music '%s', which is not in the registry" % [path, cue])
	check(content.music.has(nav.AMBIENCE_DEFAULT),
		"the default room tone '%s' is not in the registry" % nav.AMBIENCE_DEFAULT)
	# The mayor's track is asked for by who is at the door rather than by a
	# screen, so it is in neither table and still has to exist.
	check(content.music.has("the_mayor"), "the mayor's own track should be registered")
	done("_test_every_screen_asks_for_music_that_exists")


## EVERY ENTRY SAYS WHETHER IT IS REAL YET, in a word the game knows.
##
## `status` is written into all seventeen entries and documented in Audio.gd's
## header as the reason the field exists — and nothing read it, so a typo
## ("finaal"), a missing field, or a fourth word somebody invented were all the
## same as saying "placeholder" and all silent. The credits now count against
## this field, which is the first thing that would have shown the mistake, and
## only after it had shipped.
func _test_every_entry_states_a_known_status() -> void:
	for where in [["sounds.json", content.sounds], ["music.json", content.music]]:
		for key in where[1]:
			var rec: Dictionary = where[1][key]
			var st := str(rec.get("status", ""))
			check(st != "", "%s: '%s' does not say whether it is a placeholder or the real thing" % [where[0], key])
			check(st == "" or audio.STATUSES.has(st),
				"%s: '%s' is marked '%s', which is not one of %s" % [where[0], key, st, audio.STATUSES.keys()])
	done("_test_every_entry_states_a_known_status")


## WHAT A COMPOSER DELIVERS AND WHAT THE GAME PLAYS ARE THE SAME FILE.
##
## The exact counterpart of test_art.gd's manifest reconciliation, and it exists
## for the same reason: seventeen cues will be recorded over weeks by somebody
## who will not run this suite, and EVERY WAY OF GETTING IT WRONG IS SILENT. A
## file named the_evening.ogg when the registry expects a name it has to look up,
## a track dropped into assets/audio/music/ because that seemed tidier, a `file`
## key pointing at a path that no longer exists — the loader returns null, the
## contract at the top of Audio.gd turns that into silence, and the game sounds
## exactly as it did before the file arrived.
##
## Two directions, and the first is the one nothing covered:
##
##   - a file under assets/audio/ that no cue names is a delivery nobody will
##     ever hear. Every other test here starts from the registry and can only
##     ever find cues with no file, never files with no cue;
##   - an entry the registry calls delivered with no file behind it is the same
##     mistake from the other end.
##
## The paths come from Audio.sound_path()/loop_path() — the game's own rule, not
## a second copy of it in here that would agree with the wrong answer.
##
## PASSES ON AN EMPTY assets/audio, which is a state this is meant to survive.
func _test_delivered_audio_and_the_registries_agree() -> void:
	var wanted := {}          # path -> [cue name, entry, which registry]
	for event in content.sounds:
		wanted[audio.sound_path(event, content.sounds[event])] = [event, content.sounds[event], "sounds.json"]
	for cue in content.music:
		wanted[audio.loop_path(cue, content.music[cue])] = [cue, content.music[cue], "music.json"]

	var delivered := {}
	for path in _audio_files(audio.AUDIO_ROOT):
		if not wanted.has(path):
			check(false, ("%s is in assets/audio/ and no cue names it — the game will never play it. "
				+ "A cue with no \"file\" is looked for at assets/audio/<cue>.wav (or .ogg for a loop), "
				+ "so check the name against data/base/sounds.json and data/base/music.json.") % path)
			continue
		delivered[path] = true

	for path in wanted:
		var cue: String = str(wanted[path][0])
		var status := str(wanted[path][1].get("status", audio.UNDELIVERED))
		if status != audio.UNDELIVERED and not delivered.has(path):
			check(false, "%s calls '%s' '%s' and there is no file at %s"
				% [wanted[path][2], cue, status, path])
	done("_test_delivered_audio_and_the_registries_agree")


## THE GUIDE AND THE CODE OFFER THE SAME WORDS.
##
## docs/SOUND_GUIDE.md is what a composer reads and Audio.STATUSES is what the
## game accepts, and they had already drifted: the guide said `status` was
## "placeholder or final" while music.json's own comment offered a third,
## `wip`. Somebody with a take recorded but not mixed had no word for it in the
## document they were working from, and the word that does work was written down
## somewhere they would never look.
func _test_the_guide_states_the_same_vocabulary() -> void:
	var guide := FileAccess.get_file_as_string("res://docs/SOUND_GUIDE.md")
	check(guide != "", "docs/SOUND_GUIDE.md should be readable")
	for st in audio.STATUSES:
		check(guide.contains("`%s`" % st),
			"docs/SOUND_GUIDE.md never offers `%s`, which is a status the game accepts" % st)
	done("_test_the_guide_states_the_same_vocabulary")


## The credits screen reports the audio it can SEE.
##
## Its "Music and sound" line was a sentence typed once, saying everything was a
## placeholder — which is the sort of claim that is true when written and false
## for the rest of the project. See Version._art_and_sound().
func _test_the_credits_count_the_audio_rather_than_claiming() -> void:
	# Autoload names do not resolve in a `-s` script — see CLAUDE.md. Both of
	# these have to come through root.get_node().
	var version: Node = root.get_node("Version")
	var i18n: Node = root.get_node("I18n")
	var summary: Dictionary = audio.status_summary()
	var counted := 0
	for st in summary:
		counted += int(summary[st])
	check(counted == content.sounds.size() + content.music.size(),
		"the summary should count every cue in both registries: %d counted, %d registered"
		% [counted, content.sounds.size() + content.music.size()])

	var said := ""
	for block in version.credits():
		if str(block[0]) == i18n.t("ART AND SOUND"):
			said = "\n".join(PackedStringArray(block[1]))
	check(said != "", "the credits should still have an art-and-sound block")
	check(said.contains(str(counted)),
		"the credits should say how many cues there are (%d); they say:\n%s" % [counted, said])
	done("_test_the_credits_count_the_audio_rather_than_claiming")


## Everything under assets/audio/ that could be a delivery — recursive, because a
## file dropped in a subfolder is a real way to get this wrong and is exactly the
## case a flat listing would report as nothing at all. `.import` files are
## Godot's, not the composer's.
func _audio_files(dir_path: String) -> Array[String]:
	var out: Array[String] = []
	var d := DirAccess.open(dir_path)
	if d == null:
		return out
	d.list_dir_begin()
	var entry := d.get_next()
	while entry != "":
		var full := dir_path.path_join(entry)
		if d.current_is_dir():
			if not entry.begins_with("."):
				out.append_array(_audio_files(full))
		elif not entry.ends_with(".import") and not entry.ends_with(".md") and not entry.begins_with("."):
			out.append(full)
		entry = d.get_next()
	d.list_dir_end()
	return out
