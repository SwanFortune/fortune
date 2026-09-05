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
