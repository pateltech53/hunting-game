class_name WeatherSystem
extends Node3D
## Drives the sky's atmospheric values, spawns precipitation and keeps the
## ambience mix in step with what the sky is doing.

signal weather_changed(id: String, display: String)

const PRESETS := {
	"clear": {"name": "Clear", "cloud": 0.06, "fog": 0.8, "precip": 0.0, "wind": 0.25,
		"light": 1.0, "snow": false},
	"fair": {"name": "Fair", "cloud": 0.28, "fog": 1.0, "precip": 0.0, "wind": 0.4,
		"light": 0.98, "snow": false},
	"overcast": {"name": "Overcast", "cloud": 0.85, "fog": 1.35, "precip": 0.0, "wind": 0.5,
		"light": 0.92, "snow": false},
	"mist": {"name": "Mist", "cloud": 0.45, "fog": 4.2, "precip": 0.0, "wind": 0.12,
		"light": 0.95, "snow": false},
	"rain": {"name": "Rain", "cloud": 0.9, "fog": 2.1, "precip": 0.6, "wind": 0.6,
		"light": 0.85, "snow": false},
	"storm": {"name": "Storm", "cloud": 1.0, "fog": 2.6, "precip": 1.0, "wind": 1.0,
		"light": 0.7, "snow": false},
	"snow": {"name": "Snowfall", "cloud": 0.8, "fog": 2.3, "precip": 0.55, "wind": 0.35,
		"light": 0.95, "snow": true},
}

## Rough Markov chain: weather drifts rather than jumping.
const TRANSITIONS := {
	"clear": ["clear", "clear", "fair", "fair", "mist"],
	"fair": ["fair", "clear", "overcast", "overcast", "mist"],
	"overcast": ["overcast", "fair", "rain", "rain", "mist", "snow"],
	"mist": ["mist", "fair", "overcast", "clear"],
	"rain": ["rain", "overcast", "storm", "overcast"],
	"storm": ["storm", "rain", "overcast"],
	"snow": ["snow", "overcast", "mist", "fair"],
}

var current := "fair"
var locked := false
var sky: SkySystem
var follow_target: Node3D

var _cloud := 0.28
var _fog := 1.0
var _precip := 0.0
var _wind := 0.4
var _light := 1.0
var _snowing := false
var _next_change := 0.0
var _rng := RandomNumberGenerator.new()
var _rain: GPUParticles3D
var _snow: GPUParticles3D
var _thunder_timer := 0.0
var _pending_thunder := -1.0
var _biome_id := ""


func setup(sky_system: SkySystem, seed_value: int) -> void:
	sky = sky_system
	_rng.seed = seed_value + 8080
	_next_change = _rng.randf_range(180.0, 420.0)
	_build_particles()
	set_weather(current, true)


func _build_particles() -> void:
	_rain = _make_precip(false)
	_rain.name = "Rain"
	add_child(_rain)
	_snow = _make_precip(true)
	_snow.name = "Snow"
	add_child(_snow)


func _make_precip(is_snow: bool) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = 700 if not is_snow else 420
	p.lifetime = 1.5 if not is_snow else 5.5
	p.preprocess = 1.0
	p.explosiveness = 0.0
	p.visibility_aabb = AABB(Vector3(-30, -30, -30), Vector3(60, 60, 60))
	p.local_coords = false
	p.emitting = false

	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	mat.emission_box_extents = Vector3(26.0, 1.0, 26.0)
	mat.direction = Vector3(0, -1, 0)
	mat.spread = 4.0 if not is_snow else 22.0
	mat.gravity = Vector3(0, -32.0 if not is_snow else -1.8, 0)
	mat.initial_velocity_min = 12.0 if not is_snow else 0.6
	mat.initial_velocity_max = 18.0 if not is_snow else 1.6
	mat.scale_min = 0.6
	mat.scale_max = 1.0
	if is_snow:
		mat.turbulence_enabled = true
		mat.turbulence_noise_strength = 1.6
		mat.turbulence_noise_scale = 2.0
	p.process_material = mat

	var quad := QuadMesh.new()
	quad.size = Vector2(0.035, 0.55) if not is_snow else Vector2(0.09, 0.09)
	p.draw_pass_1 = quad

	var vis := StandardMaterial3D.new()
	vis.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	vis.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	vis.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	vis.albedo_color = Color(0.72, 0.80, 0.88, 0.45) if not is_snow \
		else Color(0.96, 0.97, 1.0, 0.85)
	vis.disable_receive_shadows = true
	quad.material = vis
	return p


func _process(delta: float) -> void:
	if sky == null:
		return
	if follow_target != null and is_instance_valid(follow_target):
		global_position = follow_target.global_position + Vector3(0, 14.0, 0)

	var target: Dictionary = PRESETS[current]
	var rate := delta * 0.09
	_cloud = move_toward(_cloud, target["cloud"], rate)
	_fog = move_toward(_fog, target["fog"], rate * 4.0)
	_precip = move_toward(_precip, target["precip"], rate * 2.0)
	_wind = move_toward(_wind, target["wind"], rate * 2.0)
	_light = move_toward(_light, target["light"], rate)
	_snowing = target["snow"]

	sky.cloud_cover = _cloud
	sky.fog_multiplier = _fog
	sky.precipitation = _precip
	sky.light_multiplier = _light
	sky.wind_strength = _wind

	_rain.emitting = _precip > 0.02 and not _snowing
	_snow.emitting = _precip > 0.02 and _snowing
	var amount_scale := clampf(_precip, 0.0, 1.0)
	_rain.amount_ratio = amount_scale
	_snow.amount_ratio = amount_scale

	_update_audio()
	_update_storm(delta)

	if not locked:
		_next_change -= delta
		if _next_change <= 0.0:
			_roll_weather()


func _update_audio() -> void:
	var biome := BiomeLibrary.get_biome(_biome_id) if _biome_id != "" else null
	var biome_wind: float = biome.wind_strength if biome != null else 0.4
	var wind_level := clampf(_wind * 0.6 + biome_wind * 0.5, 0.0, 1.0)
	AudioDirector.set_ambience(wind_level, _precip * (0.35 if _snowing else 1.0), 0.0)
	var bird := 0.0
	if biome != null and sky != null:
		bird = biome.bird_activity
		# Birds go quiet at night and in bad weather.
		if sky.is_night():
			bird *= 0.15
		bird *= lerpf(1.0, 0.25, _precip)
		bird *= lerpf(1.0, 0.7, _cloud)
	AudioDirector.bird_activity = clampf(bird, 0.0, 2.0)


func _update_storm(delta: float) -> void:
	if _pending_thunder > 0.0:
		_pending_thunder -= delta
		if _pending_thunder <= 0.0:
			_pending_thunder = -1.0
			AudioDirector.play("thunder", -4.0, _rng.randf_range(0.85, 1.15))
	if current != "storm":
		return
	_thunder_timer -= delta
	if _thunder_timer <= 0.0:
		_thunder_timer = _rng.randf_range(9.0, 26.0)
		sky.lightning_flash()
		# Sound arrives after the flash, distance-appropriate.
		_pending_thunder = _rng.randf_range(0.6, 4.5)


func _roll_weather() -> void:
	var options: Array = TRANSITIONS.get(current, ["fair"])
	var pick: String = options[_rng.randi_range(0, options.size() - 1)]
	# Only let it snow where snow makes sense.
	if pick == "snow" and not _biome_supports_snow():
		pick = "rain"
	set_weather(pick, false)
	_next_change = _rng.randf_range(240.0, 620.0)


func _biome_supports_snow() -> bool:
	return _biome_id in ["boreal_taiga", "alpine_ridge"]


func set_biome(biome_id: String) -> void:
	_biome_id = biome_id


func set_weather(id: String, instant: bool) -> void:
	if not PRESETS.has(id):
		return
	current = id
	var p: Dictionary = PRESETS[id]
	if instant:
		_cloud = p["cloud"]
		_fog = p["fog"]
		_precip = p["precip"]
		_wind = p["wind"]
		_light = p["light"]
		_snowing = p["snow"]
	weather_changed.emit(id, p["name"])


func display_name() -> String:
	return PRESETS.get(current, {}).get("name", "Fair")


func precipitation() -> float:
	return _precip


func wind() -> float:
	return _wind


## Wind bearing, used by the scent model - animals downwind smell you first.
func wind_direction() -> Vector3:
	var angle := float(_rng.seed % 360) * 0.0174533
	return Vector3(cos(angle), 0.0, sin(angle))


## How much wildlife is out and about in this weather.
func activity_modifier() -> float:
	match current:
		"storm":
			return 0.35
		"rain":
			return 0.65
		"snow":
			return 0.7
		"mist":
			return 1.05
		_:
			return 1.0
