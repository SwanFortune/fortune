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

## WHAT A CUE'S `status` MAY SAY. The authority: both registries are checked
## against this and so is docs/SOUND_GUIDE.md, because the vocabulary was
## written down in three places and two of them already disagreed — the guide
## offered "placeholder or final" while music.json's own comment offered
## "placeholder | wip | final". A composer reading the guide would have had no
## word for the take that exists but is not the one that ships.
const STATUSES := {
	"placeholder": "a synthesised stand-in from tests/gen_sounds.py, meant to be replaced",
	"wip": "a real recording, but not the one that ships",
	"final": "delivered",
}

## The status that means NOBODY HAS MADE THIS YET, and the answer assumed for an
## entry that does not say. Conservative on purpose, the same way Art.UNDELIVERED
## is "missing": a cue that forgets to declare itself is counted as outstanding
## work rather than quietly credited as finished.
const UNDELIVERED := "placeholder"

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

	# EXPLICITLY, not through the signal above. Content is earlier in the
	# autoload order, so it has already loaded and already emitted `reloaded` by
	# the time this runs — connecting to a signal that has finished firing means
	# reload() does not happen at boot at all. That was harmless while it only
	# cleared an empty cache, and is not harmless now that it is also the check.
	_say_what_does_not_resolve()


## Drops every cached stream, so a mod repointing a sound takes effect on the
## next play rather than at the next launch. Wired to Content.reloaded in
## _ready(), so no caller has to remember it.
func reload() -> void:
	_cache.clear()
	_say_what_does_not_resolve()


## A CUE THE REGISTRY LISTS AND NOTHING CAN PLAY IS WORTH ONE LINE.
##
## The missing-file contract at the top of this file is deliberate and stays:
## the game must run with no audio at all. But "a missing file is silence"
## quietly covers a second case it was never meant to — a cue that IS supposed
## to have a file, whose file the build did not carry — and that case is
## indistinguishable from working, by design, in the one place it matters most.
##
## So the contract keeps its promise at PLAY time and this says so once at LOAD
## time. tests/run_all.sh and tests/smoke_export.sh both fail on an unexpected
## warning, which means the exported artefact is now checked for this too.
func _say_what_does_not_resolve() -> void:
	var quiet: Array[String] = []
	for event in Content.sounds:
		if _load_stream(sound_path(event, Content.sounds[event])) == null:
			quiet.append(event)
	for cue in Content.music:
		if _load_stream(loop_path(cue, Content.music[cue])) == null:
			quiet.append(cue)
	if not quiet.is_empty():
		push_warning("[Audio] %d registered cue(s) resolve to no file and will be silent: %s"
			% [quiet.size(), ", ".join(quiet)])


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
	var stream: AudioStream = _load_stream(sound_path(event, rec))
	_cache[event] = stream
	return stream


## WHERE A CUE'S AUDIO LIVES, as a path, whether or not anything is there.
##
## Split out of the two loaders so that tests/test_audio.gd can reconcile the
## files on disk against the registries by ASKING THE GAME WHERE IT LOOKS rather
## than keeping its own copy of the naming rule. A second copy of a convention is
## exactly how a delivered file ends up in a folder nothing ever reads: the copy
## in the test would agree with the file and the game would still be silent.
func sound_path(event: String, rec: Dictionary) -> String:
	return _resolve(str(rec.get("file", "")), event, [".wav"])


## The same for a looping cue, which may also arrive as an .ogg — a three-minute
## track is worth compressing and a half-second door knock is not.
func loop_path(cue: String, rec: Dictionary) -> String:
	return _resolve(str(rec.get("file", "")), cue, [".wav", ".ogg"])


## `file` wins if the entry states one: a res:// or user:// path is taken as-is
## (that is how a mod points at its own folder), a bare filename resolves under
## assets/audio/. With no `file`, the cue's own name plus each extension in turn,
## the first that exists — and the FIRST OF THE LIST when none does, so a caller
## reporting the gap names the file somebody was supposed to deliver instead of
## an empty string.
func _resolve(file: String, cue_name: String, extensions: Array) -> String:
	if file != "":
		if file.begins_with("res://") or file.begins_with("user://"):
			return file
		return AUDIO_ROOT + file
	for ext in extensions:
		var path: String = AUDIO_ROOT + cue_name + str(ext)
		if FileAccess.file_exists(path):
			return path
	return AUDIO_ROOT + cue_name + str(extensions[0])


## COUNTS BY STATUS across both registries — the one-shots and the loops are one
## body of work to whoever is making them, and the credits screen says so in one
## line. Same shape as Art.status_summary(), and read by the same code.
func status_summary() -> Dictionary:
	var out := {}
	for registry in [Content.sounds, Content.music]:
		for key in registry:
			var rec = registry[key]
			var st := UNDELIVERED
			if rec is Dictionary:
				st = str(rec.get("status", UNDELIVERED))
			out[st] = int(out.get(st, 0)) + 1
	return out


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
		return _imported(path)
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


## THE OTHER HALF OF THE PROMISE, and the half that was missing.
##
## Reading bytes is what makes a file dropped into assets/audio/ — or shipped by
## a mod in user://mods/ — play without going near the editor. It is also why
## THE SHIPPED GAME HAD NO SOUND AT ALL. An export does not carry the .wav: the
## importer converts it, the pack holds assets/audio/coin.wav.import and a
## .sample under .godot/imported/, and assets/audio/coin.wav itself is not in
## there. So FileAccess.file_exists() was false for all seventeen cues, and the
## missing-file contract at the top of this file turned that into silence —
## exactly as designed, for a case it was never meant to cover.
##
## Nothing caught it because the suite runs from the source tree, where the .wav
## is a real file. It was found by listing what the exported binary actually
## contains and comparing that with what the game asks for at runtime.
##
## Not fixable in the build: `include_filter` does not force the raw form of a
## file the importer already handles, `.gdignore` takes it out of the export
## altogether, and the `importer="keep"` sidecar is in .gitignore as a
## regenerated file, so it would not survive a clone. It belongs here anyway —
## the imported resource IS the file, in the form that build carries.
func _imported(path: String) -> AudioStream:
	if not ResourceLoader.exists(path):
		return null
	var res = ResourceLoader.load(path)
	return res if res is AudioStream else null


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
	var stream := _load_stream(loop_path(cue, rec))
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
