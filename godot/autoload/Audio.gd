## Autoload. Plays a named game moment. Built on the same principle as
## autoload/Art.gd: the game is fully playable with zero audio files present,
## a missing sound is silence rather than an error, and it improves piece by
## piece as real audio lands.
##
## THE SOUNDS THAT SHIP ARE PLACEHOLDERS. They are synthesized (see
## tests/gen_sounds.py) and are meant to be replaced, exactly the way the
## procedural card faces are meant to be replaced by the artist's work. Every
## entry in data/base/sounds.json carries a `status` for that reason, and
## docs/SOUND_GUIDE.md is the composer-facing half of this.
##
## The registry rides the ordinary mod pipeline (a "sounds" dict category), so
## a mod repoints a sound the same way it overrides a card, and a mod adding
## its own event just adds a key.
extends Node

const AUDIO_ROOT := "res://assets/audio/"

## The moments the game can announce, and what each one is FOR. This is the
## authority: data/base/sounds.json must cover exactly these keys and no
## others, which tests/test_audio.gd asserts — otherwise a renamed event would
## silently stop playing, and a registry entry for an event nobody fires would
## sit there looking like it worked.
const EVENTS := {
	"card_draw": "a card arriving in hand — fires once per card dealt",
	"card_lay": "a card leaving the hand for the table",
	"card_discard": "the hand being swept at the end of a reading",
	"reading_resolve": "a reading being read — the one moment that should feel like an event",
	"sitter_win": "they go home whole",
	"sitter_lose": "they leave as they came",
	"coin": "centimes changing hands",
	"knock": "somebody at the front door — the sound the whole run is counted in",
	"ui_move": "keyboard/gamepad focus moving between things",
	"ui_press": "a button or row being activated",
}

## How many sounds may overlap. A hand of five cards deals five draws in a
## row, so one player would cut off four of them.
const VOICES := 8

## Which moments play on the "UI" bus; everything else plays on "SFX". The
## split is what makes the two volume sliders worth having — a keyboard player
## hears ui_move on every single focus change, and being able to turn that down
## without losing the game's sounds is the point. An event missing from here
## goes to SFX, the right default for a sound a mod added.
const UI_EVENTS := ["ui_move", "ui_press"]

## THE LOOPING HALF. `play()` above is for moments; these two channels are for
## the things that carry on — the score, and the room you are sitting in.
##
## ONE AT A TIME PER CHANNEL, and a change is a crossfade rather than a cut: the
## old track fades down while the new one comes up, both over the incoming
## track's `fade` seconds. Asking for what is already playing does nothing at
## all, which is what makes it safe to call from a screen's _ready() — every
## screen announces what it wants and only a real change costs anything.
##
## THE SAME CONTRACT AS play(): an unknown cue, a missing file and an empty
## registry are silence. The game is playable with no music at all, which is
## exactly the state it ships in today.
const CHANNELS := {"music": "MUSIC", "ambience": "AMBIENCE"}

## What each channel is playing, by cue name. Read by tests and by the cue
## logic; "" means nothing.
var playing: Dictionary = {"music": "", "ambience": ""}

var _loops: Dictionary = {}
var _fades: Dictionary = {}

## Which of a channel's two players is the audible one. Tracked explicitly
## rather than worked out from their volumes: a fade is a tween, so between the
## call and the next frame both players still read -60 dB and "whichever is
## louder" picks the same one twice — which restarts the track it was supposed
## to be fading out of and never brings the other one up.
var _at: Dictionary = {}


## Every event this has actually played, and how many times. Kept because a
## headless test has no ears: "the door knocks even with animation turned off"
## is a real promise (turning motion off should not make the game go quiet) and
## there was no way to assert it. Costs one dictionary entry per event.
var played: Dictionary = {}


var _players: Array[AudioStreamPlayer] = []
var _next := 0
var _cache: Dictionary = {}


func _ready() -> void:
	# Re-sync whenever content is rebuilt; see Content.reloaded.
	Content.reloaded.connect(reload)
	for i in VOICES:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)
	# Two players per looping channel, so a crossfade has something to fade out
	# of and something to fade into. Named, so a test can find them.
	for channel in CHANNELS:
		var pair: Array[AudioStreamPlayer] = []
		for i in 2:
			var p := AudioStreamPlayer.new()
			p.name = "%s_%d" % [channel, i]
			p.bus = CHANNELS[channel]
			p.volume_db = -60.0
			add_child(p)
			pair.append(p)
		_loops[channel] = pair
		_at[channel] = 0


## Drops every cached stream, so a mod repointing a sound takes effect on the
## next play rather than at the next launch. Wired to Content.reloaded in
## _ready(), so no caller has to remember it.
func reload() -> void:
	_cache.clear()


## Plays `event`. Unknown events, missing files and an empty registry are all
## silence — never an error, never a crash. `pitch_jitter` in the registry
## varies the pitch a little per play so a run of the same sound (five cards
## dealt) does not machine-gun.
func play(event: String) -> void:
	played[event] = int(played.get(event, 0)) + 1
	var rec: Dictionary = Content.sounds.get(event, {})
	if rec.is_empty():
		return
	var stream: AudioStream = _stream_for(event, rec)
	if stream == null:
		return
	var p := _players[_next]
	_next = (_next + 1) % _players.size()
	# Set per play, not once per player: voices are reused round-robin, so a
	# voice has to carry the bus of whatever it is playing right now.
	p.bus = "UI" if UI_EVENTS.has(event) else "SFX"
	p.stream = stream
	p.volume_db = float(rec.get("gain_db", 0.0))
	var jitter := float(rec.get("pitch_jitter", 0.0))
	p.pitch_scale = 1.0 if jitter <= 0.0 else randf_range(1.0 - jitter, 1.0 + jitter)
	p.play()


func _stream_for(event: String, rec: Dictionary) -> AudioStream:
	if _cache.has(event):
		return _cache[event]
	var path: String = str(rec.get("file", ""))
	if path == "":
		path = AUDIO_ROOT + event + ".wav"
	elif not path.begins_with("res://") and not path.begins_with("user://"):
		path = AUDIO_ROOT + path
	var stream: AudioStream = _load_stream(path)
	_cache[event] = stream
	return stream


## Decodes an audio file from BYTES rather than going through load().
##
## load() only works for assets the editor has imported — it needs the .import
## file and the pre-converted resource in .godot/imported/. That is fine for
## something baked into an export and useless for everything else: a sound a
## mod ships in user://mods/ has never been near the editor and never will be,
## and neither has a file a composer has just dropped into assets/audio/. Going
## through the bytes makes both work, and makes "drop a file in and it plays"
## true rather than nearly true.
func _load_stream(path: String) -> AudioStream:
	if not FileAccess.file_exists(path):
		return null
	match path.get_extension().to_lower():
		"wav":
			return _load_wav(path)
		"ogg":
			return AudioStreamOggVorbis.load_from_file(path)
		"mp3":
			var mp3 := AudioStreamMP3.new()
			mp3.data = FileAccess.get_file_as_bytes(path)
			return mp3 if not mp3.data.is_empty() else null
	push_warning("[Audio] %s is not a format this loads (wav, ogg, mp3)." % path)
	return null


## Minimal RIFF/WAVE reader — enough for uncompressed PCM, which is what every
## tool exports by default and what AudioStreamWAV wants anyway. Anything it
## does not understand returns null and is therefore silent, per the contract
## at the top of this file.
func _load_wav(path: String) -> AudioStreamWAV:
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.size() < 44 or bytes.slice(0, 4).get_string_from_ascii() != "RIFF" \
			or bytes.slice(8, 12).get_string_from_ascii() != "WAVE":
		push_warning("[Audio] %s is not a RIFF/WAVE file." % path)
		return null

	var channels := 0
	var rate := 0
	var bits := 0
	var pcm := PackedByteArray()
	var at := 12
	while at + 8 <= bytes.size():
		var id := bytes.slice(at, at + 4).get_string_from_ascii()
		var size := bytes.decode_u32(at + 4)
		var body := at + 8
		if id == "fmt ":
			if bytes.decode_u16(body) != 1:
				push_warning("[Audio] %s is compressed WAV; only PCM is read." % path)
				return null
			channels = bytes.decode_u16(body + 2)
			rate = bytes.decode_u32(body + 4)
			bits = bytes.decode_u16(body + 14)
		elif id == "data":
			pcm = bytes.slice(body, min(body + size, bytes.size()))
		# Chunks are word-aligned: an odd size carries a pad byte.
		at = body + size + (size & 1)

	if pcm.is_empty() or channels < 1 or channels > 2 or rate <= 0:
		push_warning("[Audio] %s has no usable PCM data." % path)
		return null
	var stream := AudioStreamWAV.new()
	match bits:
		8:
			stream.format = AudioStreamWAV.FORMAT_8_BITS
		16:
			stream.format = AudioStreamWAV.FORMAT_16_BITS
		_:
			push_warning("[Audio] %s is %d-bit; only 8- and 16-bit PCM are read." % [path, bits])
			return null
	stream.mix_rate = rate
	stream.stereo = channels == 2
	stream.data = pcm
	return stream


## Puts `cue` on `channel` ("music" or "ambience"), crossfading from whatever is
## there. An empty cue fades the channel out and leaves it empty.
##
## Idempotent on purpose — see the CHANNELS comment. Called from Nav for every
## screen change, so the common case is "already playing this" and has to cost
## nothing.
func play_loop(channel: String, cue: String) -> void:
	if not CHANNELS.has(channel):
		push_warning("[Audio] no such channel '%s'" % channel)
		return
	if str(playing.get(channel, "")) == cue:
		return
	var rec: Dictionary = Content.music.get(cue, {}) if cue != "" else {}
	if cue != "" and rec.is_empty():
		# A cue nobody has written a track for yet: leave what is playing alone
		# rather than dropping to silence, which is the wrong half of "a missing
		# file changes nothing".
		return
	playing[channel] = cue
	var pair: Array = _loops.get(channel, [])
	if pair.size() < 2:
		return

	var stream: AudioStream = null
	if cue != "":
		stream = _loop_stream(cue, rec)
		if stream == null:
			playing[channel] = ""
	var seconds := float(rec.get("fade", 2.0))
	var gain := float(rec.get("gain_db", -14.0))

	# The one that is up goes down; the other one takes the new track.
	var at: int = int(_at.get(channel, 0))
	var out: AudioStreamPlayer = pair[at]
	var into: AudioStreamPlayer = pair[1 - at]
	_at[channel] = 1 - at
	_fade(channel + "_out", out, -60.0, seconds, true)
	if stream != null:
		into.stream = stream
		into.volume_db = -60.0
		into.play()
		_fade(channel + "_in", into, gain, seconds, false)


func music(cue: String) -> void:
	play_loop("music", cue)


func ambience(cue: String) -> void:
	play_loop("ambience", cue)


## Silences both channels — the one thing a hard cut is right for, since it is
## used when the game is going away.
func hush() -> void:
	for channel in CHANNELS:
		play_loop(channel, "")


func _fade(key: String, player: AudioStreamPlayer, to_db: float, seconds: float, stop_after: bool) -> void:
	var old: Tween = _fades.get(key, null)
	if old != null and old.is_valid():
		old.kill()
	# INSTANT when the player has asked for no motion, the same rule every other
	# animation in the game follows — somebody who turned animation off did not
	# ask for three seconds of fade either.
	# The setting read directly, not through UIKit.motion_off(): an autoload
	# cannot preload a scene script (see Content.gd's header), and this is the
	# same one line that function is.
	if seconds <= 0.0 or Settings.animation_scale() <= 0.01:
		player.volume_db = to_db
		if stop_after:
			player.stop()
		return
	var tween := create_tween()
	tween.tween_property(player, "volume_db", to_db, seconds)
	if stop_after:
		tween.tween_callback(player.stop)
	_fades[key] = tween


## A looping stream. Same loader as the one-shots, plus the loop itself: a WAV
## has to be TOLD to loop (Godot defaults it off), and an .ogg carries its own
## loop flag which this sets for the same reason.
func _loop_stream(cue: String, rec: Dictionary) -> AudioStream:
	var key := "loop:" + cue
	if _cache.has(key):
		return _cache[key]
	var path: String = str(rec.get("file", ""))
	if path == "":
		path = AUDIO_ROOT + cue + ".wav"
		if not FileAccess.file_exists(path):
			path = AUDIO_ROOT + cue + ".ogg"
	elif not path.begins_with("res://") and not path.begins_with("user://"):
		path = AUDIO_ROOT + path
	var stream := _load_stream(path)
	if stream != null and bool(rec.get("loop", true)):
		if stream is AudioStreamWAV:
			var wav: AudioStreamWAV = stream
			wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
			wav.loop_begin = 0
			wav.loop_end = 0
		elif stream is AudioStreamOggVorbis:
			(stream as AudioStreamOggVorbis).loop = true
		elif stream is AudioStreamMP3:
			(stream as AudioStreamMP3).loop = true
	_cache[key] = stream
	return stream
