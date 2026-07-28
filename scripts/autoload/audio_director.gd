extends Node
## Owns every sound in the game: synthesises the bank on worker threads at
## boot, then hands out pooled players, an adaptive music bed and a weather /
## biome driven ambience mix.

signal bank_ready

const SpeciesLibraryScript := preload("res://scripts/animals/species_library.gd")

const POOL_2D := 10
const POOL_3D := 28

enum Mood { CALM, WONDER, TENSION }

var sfx: Dictionary = {}
var music_layers: Dictionary = {}
var ready_sfx := false
var ready_music := false

var _sfx_task := -1
var _music_task := -1
var _pool_2d: Array[AudioStreamPlayer] = []
var _pool_3d: Array[AudioStreamPlayer3D] = []
var _music_players: Dictionary = {}
var _music_targets: Dictionary = {}
var _mood: Mood = Mood.CALM
var _music_enabled := true

var _wind: AudioStreamPlayer
var _rain: AudioStreamPlayer
var _stream: AudioStreamPlayer
var _amb_targets := {"wind": 0.35, "rain": 0.0, "stream": 0.0}
var _amb_players: Dictionary = {}

var _bird_timer := 0.0
var _listener_pos := Vector3.ZERO
var _rng := RandomNumberGenerator.new()

# Filled in by the worker threads, consumed on the main thread.
var _pending_sfx: Dictionary = {}
var _pending_music: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.seed = 20240719
	_build_players()
	_sfx_task = WorkerThreadPool.add_task(_synthesise_sfx, true, "wildlight_sfx")
	_music_task = WorkerThreadPool.add_task(_synthesise_music, true, "wildlight_music")


## The synthesis tasks hold references to the Synth script. Quitting before
## they finish frees it underneath them, which surfaces as "nonexistent
## function" errors from the worker threads on the way out. Wait for them.
func _exit_tree() -> void:
	if _sfx_task != -1:
		WorkerThreadPool.wait_for_task_completion(_sfx_task)
		_sfx_task = -1
	if _music_task != -1:
		WorkerThreadPool.wait_for_task_completion(_music_task)
		_music_task = -1


# ---------------------------------------------------------------- web unlock

var _web_unlocked := false


## Browsers refuse to start an AudioContext until the page has seen a real user
## gesture, and a context created before that stays suspended - which is heard
## as the game having no sound at all. Godot's shell resumes it on its own in
## most cases, but not when the canvas is inside an iframe or the first gesture
## lands on a DOM element rather than the canvas, so we retry on our own first
## input and restart the looping beds, which are the players most likely to
## have been started while the context was dead.
func _unhandled_input(_event: InputEvent) -> void:
	if _web_unlocked:
		return
	_web_unlocked = true
	if not OS.has_feature("web"):
		return
	JavaScriptBridge.eval("""
		(function () {
			try {
				var ctx = (window.GodotAudio && window.GodotAudio.ctx) || null;
				if (ctx && ctx.state !== 'running') { ctx.resume(); }
			} catch (e) {}
		})();
	""", true)
	_restart_loops()


## Re-triggers every looping player. Safe to call at any point: a player that
## is already running simply starts its loop again from the top.
func _restart_loops() -> void:
	for key: String in _amb_players:
		var p: AudioStreamPlayer = _amb_players[key]
		if p.stream != null and not p.playing:
			p.play()
	for key: String in _music_players:
		var m: AudioStreamPlayer = _music_players[key]
		if m.stream != null and not m.playing:
			m.play()


func _build_players() -> void:
	for i in POOL_2D:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_pool_2d.append(p)
	for i in POOL_3D:
		var p3 := AudioStreamPlayer3D.new()
		p3.bus = "SFX"
		p3.max_distance = 160.0
		p3.unit_size = 8.0
		p3.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		add_child(p3)
		_pool_3d.append(p3)
	for key: String in ["wind", "rain", "stream", "insects", "leaves", "night"]:
		var a := AudioStreamPlayer.new()
		a.bus = "Ambience"
		a.volume_db = -80.0
		add_child(a)
		_amb_players[key] = a
	_wind = _amb_players["wind"]
	_rain = _amb_players["rain"]
	_stream = _amb_players["stream"]
	for key: String in ["calm", "wonder", "tension", "dawn", "rain", "night"]:
		var m := AudioStreamPlayer.new()
		m.bus = "Music"
		m.volume_db = -80.0
		add_child(m)
		_music_players[key] = m
		_music_targets[key] = 0.0


# --------------------------------------------------------------- worker tasks

func _synthesise_sfx() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 31337
	var bank := {}
	bank["shutter"] = Synth.shutter(rng, true)
	bank["shutter_light"] = Synth.shutter(rng, false)
	bank["focus"] = Synth.focus_confirm(rng)
	bank["lens"] = Synth.lens_click(rng)
	bank["camera_raise"] = Synth.camera_raise(rng)
	bank["rifle"] = Synth.rifle_shot(rng)
	bank["rifle_cycle"] = Synth.rifle_cycle(rng)
	bank["heartbeat"] = Synth.heartbeat(rng)
	bank["thunder"] = Synth.thunder(rng)
	bank["discovery"] = Synth.discovery_sting(rng)
	bank["score_good"] = Synth.score_flourish(rng, false)
	bank["score_great"] = Synth.score_flourish(rng, true)
	bank["ui_move"] = Synth.ui_tick(rng, 760.0)
	bank["ui_click"] = Synth.ui_tick(rng, 980.0, false)
	bank["ui_back"] = Synth.ui_tick(rng, 520.0)
	for surface: String in ["grass", "gravel", "wood", "water", "snow"]:
		for v in 3:
			bank["step_%s_%d" % [surface, v]] = Synth.footstep(rng, surface)
	for i in 5:
		bank["bird_%d" % i] = Synth.bird_chirp(rng, i)
	bank["wind_bed"] = Synth.wind_bed(rng, 8.0)
	bank["rain_bed"] = Synth.rain_bed(rng, 6.0, false)
	bank["stream_bed"] = Synth.stream_bed(rng, 6.0)
	bank["insects_bed"] = Synth.insect_bed(rng, 7.0, false)
	bank["leaves_bed"] = Synth.leaf_bed(rng, 6.0)
	bank["night_bed"] = Synth.night_bed(rng, 8.0)
	bank["branch"] = Synth.branch_snap(rng)
	bank["splash"] = Synth.water_splash(rng)
	bank["legendary"] = Synth.legendary_swell(rng)
	bank["flourish"] = Synth.orchestral_flourish(rng)
	for id: String in SpeciesLibraryScript.CALL_PARAMS:
		bank["call_%s" % id] = Synth.animal_call(rng, SpeciesLibraryScript.CALL_PARAMS[id])
	_pending_sfx = bank


func _synthesise_music() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 90210
	var bank := {}
	# D minor-ish bed. Calm, wonder and tension share a root so they blend.
	bank["calm"] = Synth.music_layer([0.0, 7.0, 12.0, 15.0], 146.83, 12.0, 0, rng)
	bank["wonder"] = Synth.music_layer([0.0, 5.0, 12.0, 19.0], 146.83, 12.0, 1, rng)
	bank["tension"] = Synth.music_layer([0.0, 1.0, 7.0, 13.0], 110.0, 8.0, 2, rng)
	# Time-of-day and weather beds, all rooted on D so they can overlap while
	# one fades into the next without a key clash.
	bank["dawn"] = Synth.music_acoustic(rng, 16.0, 146.83)
	bank["rain"] = Synth.music_piano(rng, 18.0, 146.83)
	bank["night"] = Synth.music_pad(rng, 16.0, 73.42)
	_pending_music = bank


func _process(delta: float) -> void:
	_poll_tasks()
	_update_music(delta)
	_update_ambience(delta)
	_update_birds(delta)


func _poll_tasks() -> void:
	if _sfx_task != -1 and WorkerThreadPool.is_task_completed(_sfx_task):
		WorkerThreadPool.wait_for_task_completion(_sfx_task)
		_sfx_task = -1
		sfx = _pending_sfx
		_pending_sfx = {}
		ready_sfx = true
		_start_ambience()
		if ready_music:
			bank_ready.emit()
	if _music_task != -1 and WorkerThreadPool.is_task_completed(_music_task):
		WorkerThreadPool.wait_for_task_completion(_music_task)
		_music_task = -1
		music_layers = _pending_music
		_pending_music = {}
		ready_music = true
		_start_music()
		if ready_sfx:
			bank_ready.emit()


# -------------------------------------------------------------------- playback

func play(name: String, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	if not sfx.has(name):
		return
	var p := _free_2d()
	if p == null:
		return
	p.stream = sfx[name]
	p.volume_db = volume_db
	p.pitch_scale = pitch
	p.play()


func play_3d(name: String, position: Vector3, volume_db: float = 0.0,
		pitch: float = 1.0, max_distance: float = 160.0) -> void:
	if not sfx.has(name):
		return
	# Skip sounds we could not possibly hear; keeps the pool free for close ones.
	if _listener_pos.distance_to(position) > max_distance:
		return
	var p := _free_3d()
	if p == null:
		return
	p.stream = sfx[name]
	p.global_position = position
	p.volume_db = volume_db
	p.pitch_scale = pitch
	p.max_distance = max_distance
	p.play()


func play_variant(prefix: String, count: int, position: Vector3, volume_db: float = 0.0,
		pitch_jitter: float = 0.08) -> void:
	var idx := _rng.randi_range(0, maxi(count - 1, 0))
	play_3d("%s_%d" % [prefix, idx], position, volume_db,
		1.0 + _rng.randf_range(-pitch_jitter, pitch_jitter))


func play_call(species_id: String, position: Vector3, volume_db: float = 0.0) -> void:
	play_3d("call_%s" % species_id, position, volume_db,
		1.0 + _rng.randf_range(-0.06, 0.06), 220.0)


func has_call(species_id: String) -> bool:
	return sfx.has("call_%s" % species_id)


func _free_2d() -> AudioStreamPlayer:
	for p in _pool_2d:
		if not p.playing:
			return p
	return _pool_2d[0] if not _pool_2d.is_empty() else null


func _free_3d() -> AudioStreamPlayer3D:
	for p in _pool_3d:
		if not p.playing:
			return p
	return null


func set_listener_position(pos: Vector3) -> void:
	_listener_pos = pos


# ----------------------------------------------------------------------- music

func _start_music() -> void:
	for key: String in _music_players:
		var p: AudioStreamPlayer = _music_players[key]
		if music_layers.has(key):
			p.stream = music_layers[key]
			p.volume_db = -80.0
			p.play()
	set_mood(_mood)


## Time of day and weather, fed in by the world so the score can follow them.
var _hour := 9.0
var _wetness := 0.0


func set_music_context(hour: float, wetness: float) -> void:
	_hour = hour
	_wetness = clampf(wetness, 0.0, 1.0)
	set_mood(_mood)


func set_mood(mood: Mood) -> void:
	_mood = mood
	for key: String in _music_targets:
		_music_targets[key] = 0.0
	if not _music_enabled:
		return

	# Tension overrides everything: when something is wrong you want the pulse,
	# not the guitar.
	if mood == Mood.TENSION:
		_music_targets["tension"] = 0.8
		_music_targets["calm"] = 0.15
		return

	# Otherwise the bed follows the clock, with rain able to take over from it.
	var dawn := 0.0
	var day := 0.0
	var night := 0.0
	if _hour < 4.5 or _hour >= 21.5:
		night = 1.0
	elif _hour < 8.5:
		dawn = 1.0                                   # first light: acoustic
	elif _hour < 18.0:
		day = 1.0
	elif _hour < 20.0:
		dawn = 0.7                                   # golden hour reprises it
		day = 0.3
	else:
		night = 0.65
		dawn = 0.35

	# Rain pulls the score toward piano, but never silences the bed entirely.
	var rain_mix: float = clampf(_wetness, 0.0, 1.0) * 0.85
	var rest := 1.0 - rain_mix
	_music_targets["rain"] = rain_mix
	_music_targets["dawn"] = dawn * rest * 0.75
	_music_targets["calm"] = day * rest * 0.7
	_music_targets["night"] = night * rest * 0.8
	if mood == Mood.WONDER:
		# Something worth looking at: lift the pentatonic layer over the top.
		_music_targets["wonder"] = 0.85


func set_music_enabled(enabled: bool) -> void:
	_music_enabled = enabled
	set_mood(_mood)


func _update_music(delta: float) -> void:
	if not ready_music:
		return
	for key: String in _music_players:
		var p: AudioStreamPlayer = _music_players[key]
		var target: float = _music_targets.get(key, 0.0)
		var target_db := linear_to_db(maxf(target, 0.0001)) if target > 0.002 else -80.0
		var current := p.volume_db
		if current <= -79.0 and target_db <= -79.0:
			continue
		p.volume_db = move_toward(current, target_db, delta * 26.0)


# ------------------------------------------------------------------- ambience

func _start_ambience() -> void:
	var map := {
		"wind": "wind_bed", "rain": "rain_bed", "stream": "stream_bed",
		"insects": "insects_bed", "leaves": "leaves_bed", "night": "night_bed",
	}
	for key: String in map:
		var p: AudioStreamPlayer = _amb_players[key]
		if sfx.has(map[key]):
			p.stream = sfx[map[key]]
			p.volume_db = -80.0
			p.play()


## Called by the weather / world systems each frame. `hour`, `tree_cover` and
## `warmth` drive the layers that make the world sound inhabited rather than
## merely windy - insects at dusk, leaves under canopy, room tone after dark.
func set_ambience(wind: float, rain: float, water: float,
		hour: float = -1.0, tree_cover: float = 0.5, warmth: float = 0.5) -> void:
	_amb_targets["wind"] = clampf(wind, 0.0, 1.0)
	_amb_targets["rain"] = clampf(rain, 0.0, 1.0)
	_amb_targets["stream"] = clampf(water, 0.0, 1.0)
	if hour < 0.0:
		return

	# Rain damps everything that lives outdoors.
	var dry := 1.0 - clampf(rain, 0.0, 1.0) * 0.8

	# Insects peak in the evening and hold through warm nights.
	var insects := 0.0
	if hour >= 18.0 or hour < 5.0:
		insects = 0.75
	elif hour >= 11.0 and hour < 18.0:
		insects = 0.45
	_amb_targets["insects"] = clampf(insects * dry * (0.4 + warmth * 0.9), 0.0, 1.0)

	# Leaves need both canopy and wind to be heard.
	_amb_targets["leaves"] = clampf(tree_cover * clampf(wind, 0.0, 1.0) * 1.25 * dry,
		0.0, 1.0)

	# Night room tone, fading in around dusk and out at first light.
	var night := 0.0
	if hour >= 20.0:
		night = clampf((hour - 20.0) / 1.5, 0.0, 1.0)
	elif hour < 6.0:
		night = clampf((6.0 - hour) / 1.5, 0.0, 1.0)
	_amb_targets["night"] = clampf(night * 0.85, 0.0, 1.0)


func _update_ambience(delta: float) -> void:
	if not ready_sfx:
		return
	for key: String in _amb_players:
		var p: AudioStreamPlayer = _amb_players[key]
		var target: float = _amb_targets.get(key, 0.0)
		var target_db := linear_to_db(maxf(target, 0.0001)) if target > 0.004 else -80.0
		p.volume_db = move_toward(p.volume_db, target_db, delta * 18.0)


var bird_activity := 0.0
var bird_position_provider: Callable = Callable()


func _update_birds(delta: float) -> void:
	if not ready_sfx or bird_activity <= 0.01:
		return
	_bird_timer -= delta * bird_activity
	if _bird_timer > 0.0:
		return
	_bird_timer = _rng.randf_range(1.4, 6.0)
	var pos := _listener_pos
	if bird_position_provider.is_valid():
		pos = bird_position_provider.call()
	else:
		pos += Vector3(_rng.randf_range(-24.0, 24.0), _rng.randf_range(3.0, 12.0),
			_rng.randf_range(-24.0, 24.0))
	play_variant("bird", 5, pos, -6.0, 0.14)


func stop_all_ambience() -> void:
	set_ambience(0.0, 0.0, 0.0)
	bird_activity = 0.0
