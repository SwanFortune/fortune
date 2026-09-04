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
