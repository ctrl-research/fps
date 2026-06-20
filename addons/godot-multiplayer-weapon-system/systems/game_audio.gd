extends Node
# No `class_name`: registered as the `GameAudio` autoload. A matching global class
# would shadow the singleton and break clean compiles.
"""
Central game audio: procedurally-synthesised sound effects + music, played
spatially (proximity falloff) or as 2D UI feedback.

No binary audio assets are shipped — every sound is generated as an
AudioStreamWAV on first use and cached (matching the project's procedural
gunshot approach). Swap in real assets later by pointing _build() at loaded
streams.

Proximity: 3D one-shots use AudioStreamPlayer3D, which attenuates with distance
from the local listener (the active camera) and cuts off past max_distance. Each
CATEGORY sets that radius — weapons carry far, footsteps stay local, walking is
simply never played.

API:
  GameAudio.play_at(global_pos, id, category)  # spatial one-shot
  GameAudio.play_ui(id, volume_db)             # non-spatial feedback/stinger
  GameAudio.play_music(id) / stop_music()      # looping buy-phase track
  GameAudio.start_heartbeat() / stop_heartbeat()
"""

const RATE: int = 22050

## Proximity profiles. max_distance = hard cutoff (m); unit_size = distance kept
## near full volume; bigger = carries further.
const CATEGORIES: Dictionary = {
	"weapon": {"max_distance": 75.0, "unit_size": 14.0, "volume_db": 0.0},
	"grenade": {"max_distance": 65.0, "unit_size": 12.0, "volume_db": 0.0},
	"footstep": {"max_distance": 18.0, "unit_size": 4.0, "volume_db": -4.0},
	"movement": {"max_distance": 14.0, "unit_size": 4.0, "volume_db": -6.0},
}

var _streams: Dictionary = {}   # id -> AudioStreamWAV
var _music: AudioStreamPlayer = null
var _heartbeat: AudioStreamPlayer = null

func _ready() -> void:
	GameState.round_state_changed.connect(_on_round_state)
	GameState.round_ended.connect(_on_round_ended)

# === Public API ===

## Spatial one-shot at a world position (parented to the scene so it survives a
## freed source, e.g. a detonating grenade).
func play_at(global_pos: Vector3, id: String, category: String) -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	var cfg: Dictionary = CATEGORIES.get(category, CATEGORIES["weapon"])
	var p := AudioStreamPlayer3D.new()
	p.stream = _stream(id)
	p.unit_size = cfg["unit_size"]
	p.max_distance = cfg["max_distance"]
	p.volume_db = cfg["volume_db"]
	p.pitch_scale = randf_range(0.94, 1.06)
	scene.add_child(p)
	p.global_position = global_pos
	p.finished.connect(p.queue_free)
	p.play()

## Non-spatial one-shot (hitmarkers, round stingers).
func play_ui(id: String, volume_db: float = 0.0) -> void:
	var p := AudioStreamPlayer.new()
	p.stream = _stream(id)
	p.volume_db = volume_db
	add_child(p)
	p.finished.connect(p.queue_free)
	p.play()

func play_music(id: String) -> void:
	stop_music()
	_music = AudioStreamPlayer.new()
	_music.stream = _stream(id)
	_music.volume_db = -8.0
	add_child(_music)
	_music.play()

func stop_music() -> void:
	if is_instance_valid(_music):
		_music.queue_free()
	_music = null

func start_heartbeat() -> void:
	if is_instance_valid(_heartbeat):
		return
	_heartbeat = AudioStreamPlayer.new()
	_heartbeat.stream = _stream("heartbeat")
	_heartbeat.volume_db = -3.0
	add_child(_heartbeat)
	_heartbeat.play()

func stop_heartbeat() -> void:
	if is_instance_valid(_heartbeat):
		_heartbeat.queue_free()
	_heartbeat = null

# === GameState hooks ===

func _on_round_state(state: int) -> void:
	if state == GameState.RoundState.BUY_PHASE:
		play_music("buy_music")
	else:
		stop_music()

func _on_round_ended(winning_team: int) -> void:
	var local_team := GameState._get_player_team(GameState._local_peer_id())
	play_ui("round_win" if winning_team == local_team else "round_lose", -2.0)

# === Stream cache / synthesis ===

func _stream(id: String) -> AudioStreamWAV:
	if not _streams.has(id):
		_streams[id] = _build(id)
	return _streams[id]

func _build(id: String) -> AudioStreamWAV:
	match id:
		"gunshot_pistol": return _gunshot(34.0, 110.0, 22.0, 0.9, 0.14)
		"gunshot_smg": return _gunshot(40.0, 130.0, 24.0, 0.85, 0.10)
		"gunshot_assault_rifle": return _gunshot(28.0, 95.0, 20.0, 1.0, 0.16)
		"gunshot_shotgun": return _gunshot(16.0, 70.0, 12.0, 1.0, 0.30)
		"gunshot_sniper": return _gunshot(14.0, 60.0, 10.0, 1.0, 0.36)
		"swing": return _whoosh(0.18)
		"reload": return _reload()
		"grenade_pull": return _blip(660.0, 0.06)
		"grenade_throw": return _whoosh(0.22)
		"grenade_explode": return _boom(0.5)
		"footstep": return _thud(0.09)
		"hit_enemy": return _blip(1320.0, 0.06)
		"hit_teammate": return _blip(440.0, 0.10)
		"round_win": return _arp([523.25, 659.25, 783.99, 1046.5], 0.12)
		"round_lose": return _arp([523.25, 415.30, 311.13], 0.16)
		"heartbeat": return _heartbeat_loop()
		"buy_music": return _music_loop()
		_: return _gunshot(28.0, 95.0, 20.0, 1.0, 0.16)

## Noise burst + low thump — the family of weapon reports, parameterised.
func _gunshot(noise_decay: float, thump_freq: float, thump_decay: float, noise_amt: float, dur: float) -> AudioStreamWAV:
	var n := int(RATE * dur)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		var t := float(i) / RATE
		var noise := randf_range(-1.0, 1.0) * exp(-t * noise_decay) * noise_amt
		var thump := sin(t * TAU * thump_freq) * exp(-t * thump_decay) * 0.7
		s[i] = clampf(noise + thump, -1.0, 1.0)
	return _to_wav(s)

## Two mechanical clicks spaced out — a reload.
func _reload() -> AudioStreamWAV:
	var dur := 0.5
	var n := int(RATE * dur)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		var t := float(i) / RATE
		var click := 0.0
		for onset in [0.0, 0.28]:
			var lt := t - onset
			if lt >= 0.0:
				click += randf_range(-1.0, 1.0) * exp(-lt * 90.0) * 0.8
		s[i] = clampf(click, -1.0, 1.0)
	return _to_wav(s)

## Filtered-ish noise swell — throws and swings.
func _whoosh(dur: float) -> AudioStreamWAV:
	var n := int(RATE * dur)
	var s := PackedFloat32Array()
	s.resize(n)
	var prev := 0.0
	for i in n:
		var t := float(i) / RATE
		var env := sin(PI * clampf(t / dur, 0.0, 1.0))  # swell in and out
		var raw := randf_range(-1.0, 1.0)
		prev = lerpf(prev, raw, 0.15)  # low-pass for an airy hiss
		s[i] = clampf(prev * env * 0.7, -1.0, 1.0)
	return _to_wav(s)

## Low sine boom + noise crack — explosions.
func _boom(dur: float) -> AudioStreamWAV:
	var n := int(RATE * dur)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		var t := float(i) / RATE
		var low := sin(t * TAU * 55.0) * exp(-t * 6.0)
		var crack := randf_range(-1.0, 1.0) * exp(-t * 22.0) * 0.6
		s[i] = clampf(low + crack, -1.0, 1.0)
	return _to_wav(s)

## Short low thud — a footstep.
func _thud(dur: float) -> AudioStreamWAV:
	var n := int(RATE * dur)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		var t := float(i) / RATE
		var body := sin(t * TAU * 150.0) * exp(-t * 40.0)
		var grit := randf_range(-1.0, 1.0) * exp(-t * 80.0) * 0.4
		s[i] = clampf(body + grit, -1.0, 1.0)
	return _to_wav(s)

## A clean tone blip — hitmarkers, ticks.
func _blip(freq: float, dur: float) -> AudioStreamWAV:
	var n := int(RATE * dur)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		var t := float(i) / RATE
		s[i] = sin(t * TAU * freq) * exp(-t * 18.0) * 0.7
	return _to_wav(s)

## A short ascending/descending tone sequence — round stingers.
func _arp(freqs: Array, note_dur: float) -> AudioStreamWAV:
	var n := int(RATE * note_dur * freqs.size())
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		var t := float(i) / RATE
		var note := int(t / note_dur)
		var lt := t - note * note_dur
		var freq: float = freqs[clampi(note, 0, freqs.size() - 1)]
		s[i] = sin(lt * TAU * freq) * exp(-lt * 6.0) * 0.6
	return _to_wav(s)

## Two soft low pulses (lub-dub), looped.
func _heartbeat_loop() -> AudioStreamWAV:
	var dur := 1.0
	var n := int(RATE * dur)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		var t := float(i) / RATE
		var beat := 0.0
		for onset in [0.0, 0.22]:
			var lt := t - onset
			if lt >= 0.0:
				beat += sin(lt * TAU * 50.0) * exp(-lt * 24.0)
		s[i] = clampf(beat * 0.8, -1.0, 1.0)
	return _to_wav(s, true)

## A calm looping arpeggio — buy-phase background.
func _music_loop() -> AudioStreamWAV:
	var notes := [261.63, 329.63, 392.0, 329.63]  # C E G E
	var note_dur := 0.5
	var dur := note_dur * notes.size()
	var n := int(RATE * dur)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		var t := float(i) / RATE
		var idx := int(t / note_dur) % notes.size()
		var lt := t - int(t / note_dur) * note_dur
		var freq: float = notes[idx]
		var tone := sin(t * TAU * freq) * 0.4
		var bass := sin(t * TAU * 130.81) * 0.15  # low C drone
		var env := 0.6 + 0.4 * sin(lt / note_dur * PI)
		s[i] = clampf((tone * env + bass), -1.0, 1.0)
	return _to_wav(s, true)

func _to_wav(samples: PackedFloat32Array, loop: bool = false) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		bytes.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	wav.data = bytes
	if loop:
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = samples.size()
	return wav
