class_name SkySystem
extends Node3D
## Sun, moon, sky, fog and the photographic light level of the scene.
##
## The single most important number this produces is [method scene_ev]: the
## exposure value of the current light. The camera compares its own aperture,
## shutter and ISO against it, which is what makes shooting at dusk feel
## different from shooting at noon rather than just looking different.

signal hour_passed(hour: int)
signal light_phase_changed(phase: String)

const DEFAULT_DAY_MINUTES := 24.0

## Sun elevation in degrees -> EV100 of the scene. Interpolated between.
const EV_CURVE := [
	[-18.0, -3.0], [-12.0, 2.0], [-6.0, 6.0], [-3.0, 8.2], [0.0, 10.4],
	[3.0, 11.6], [6.0, 12.6], [12.0, 13.6], [25.0, 14.5], [50.0, 15.2], [90.0, 15.6],
]

var time_of_day := 6.6            ## hours, 0..24
var day_length_minutes := DEFAULT_DAY_MINUTES
var time_frozen := false
var latitude_tilt := 22.0         ## keeps the sun off the exact zenith
var sun_azimuth := 118.0

var sun: DirectionalLight3D
var moon: DirectionalLight3D
var environment: Environment
var world_env: WorldEnvironment

# Set by the weather system.
var cloud_cover := 0.15
var fog_multiplier := 1.0
var light_multiplier := 1.0
var precipitation := 0.0
var wind_strength := 0.35

# Set by the camera when it is raised.
var exposure_compensation := 1.0

var _biome_ref: Biome = null
var _last_hour := -1
var _phase := ""
var _sky_material: ShaderMaterial
var _flash := 0.0
var _cloud_drift := 0.0


func _ready() -> void:
	_build_lights()
	_build_environment()
	_apply(0.0)


func _build_lights() -> void:
	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = Settings.shadow_distance()
	sun.directional_shadow_split_1 = 0.06
	sun.directional_shadow_split_2 = 0.16
	sun.directional_shadow_split_3 = 0.42
	sun.directional_shadow_blend_splits = true
	sun.shadow_bias = 0.045
	sun.shadow_normal_bias = 1.4
	sun.light_angular_distance = 0.55
	sun.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_AND_SKY
	# Drives the shafts of light through volumetric fog and tree canopies.
	sun.light_volumetric_fog_energy = 1.4
	add_child(sun)

	moon = DirectionalLight3D.new()
	moon.name = "Moon"
	moon.shadow_enabled = false
	moon.light_color = Color(0.62, 0.72, 0.95)
	moon.light_energy = 0.0
	moon.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	add_child(moon)


func _build_environment() -> void:
	_sky_material = SkyShader.build()

	var sky := Sky.new()
	sky.sky_material = _sky_material
	sky.radiance_size = Sky.RADIANCE_SIZE_128
	# The sky changes slowly, so spread the radiance update over frames rather
	# than recomputing the whole cubemap every time the sun moves a fraction.
	sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL

	environment = Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.ambient_light_sky_contribution = 1.0
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	environment.tonemap_mode = Environment.TONE_MAPPER_ACES
	# White reference. Pushing this high crushes the midtones and turns shade
	# under a canopy to mud; 1.5 keeps highlights rolling off without that.
	environment.tonemap_white = 1.5
	environment.tonemap_exposure = 1.0

	environment.fog_enabled = true
	environment.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	# Scatter puts a glow around the sun when you shoot into it through haze.
	environment.fog_sun_scatter = 0.55
	# Aerial perspective is what makes a far ridge read as far away.
	environment.fog_aerial_perspective = 0.55
	environment.fog_sky_affect = 0.55
	# Height fog pools in the valleys and burns off as you climb.
	environment.fog_height = float(TerrainGenerator.SEA_LEVEL) + 3.0
	environment.fog_height_density = 0.03

	environment.glow_enabled = Settings.quality >= Settings.Quality.MEDIUM
	environment.glow_intensity = 0.35
	environment.glow_bloom = 0.05
	environment.glow_hdr_threshold = 1.1
	environment.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT

	environment.ssao_enabled = Settings.quality >= Settings.Quality.HIGH
	environment.ssao_radius = 1.6
	environment.ssao_intensity = 1.4

	if Settings.wants_volumetric_fog():
		environment.volumetric_fog_enabled = true
		environment.volumetric_fog_density = 0.012
		environment.volumetric_fog_gi_inject = 0.6
		environment.volumetric_fog_length = 96.0
		environment.volumetric_fog_anisotropy = 0.35

	world_env = WorldEnvironment.new()
	world_env.name = "WorldEnvironment"
	world_env.environment = environment
	add_child(world_env)


func _process(delta: float) -> void:
	if not time_frozen and day_length_minutes > 0.0:
		time_of_day += delta * (24.0 / (day_length_minutes * 60.0))
		while time_of_day >= 24.0:
			time_of_day -= 24.0
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - delta * 3.5)
	_cloud_drift += delta * (0.0016 + wind_strength * 0.0075)
	_apply(delta)

	var hour := int(floor(time_of_day))
	if hour != _last_hour:
		_last_hour = hour
		hour_passed.emit(hour)


func set_biome(biome: Biome) -> void:
	_biome_ref = biome


func sun_elevation_degrees() -> float:
	# 06:00 puts the sun on the horizon, 12:00 at its highest.
	var t := (time_of_day / 24.0) * TAU - PI * 0.5
	var raw := sin(t) * (90.0 - latitude_tilt)
	return raw


func sun_direction() -> Vector3:
	var elev := deg_to_rad(sun_elevation_degrees())
	var azim := deg_to_rad(sun_azimuth + (time_of_day / 24.0) * 40.0)
	# Direction the light travels, i.e. from the sun toward the ground.
	return -Vector3(cos(elev) * cos(azim), sin(elev), cos(elev) * sin(azim)).normalized()


func is_night() -> bool:
	return sun_elevation_degrees() < -4.5


## Photographic light level of the scene, EV at ISO 100.
func scene_ev() -> float:
	var elev := sun_elevation_degrees()
	var ev := _sample_ev_curve(elev)
	# Cloud and rain take light away; snow and open water give some back.
	ev -= cloud_cover * 2.4
	ev -= precipitation * 1.4
	if is_night():
		ev += 0.0
	return ev


func _sample_ev_curve(elev: float) -> float:
	if elev <= float(EV_CURVE[0][0]):
		return float(EV_CURVE[0][1])
	for i in range(1, EV_CURVE.size()):
		var a: Array = EV_CURVE[i - 1]
		var b: Array = EV_CURVE[i]
		var a_elev := float(a[0])
		var b_elev := float(b[0])
		if elev <= b_elev:
			var t := (elev - a_elev) / maxf(b_elev - a_elev, 0.001)
			return lerpf(float(a[1]), float(b[1]), t)
	return float(EV_CURVE[EV_CURVE.size() - 1][1])


## Roughly how bright the engine renders this scene before any exposure is
## applied. The camera divides by it so that "correct settings" always land on
## a usable image, whether that is noon or the blue hour.
func natural_light_scale() -> float:
	var elev := sun_elevation_degrees()
	var day := clampf((elev + 6.0) / 12.0, 0.0, 1.0)
	var s: float = lerpf(0.085, 1.0, day) * lerpf(1.0, 0.72, cloud_cover)
	return clampf(s, 0.05, 1.4)


## Human-readable name for the current light, used by the HUD and the scorer.
func light_phase() -> String:
	var e := sun_elevation_degrees()
	if e < -12.0:
		return "night"
	if e < -4.0:
		return "astronomical twilight" if e < -8.0 else "blue hour"
	if e < 1.0:
		return "twilight"
	if e < 8.0:
		return "golden hour"
	if e < 20.0:
		return "soft light"
	if cloud_cover > 0.6:
		return "overcast"
	return "hard light"


## 0..1 quality of the light for photography. Golden and blue hour reward you;
## flat noon under cloud does not.
func light_quality() -> float:
	var e := sun_elevation_degrees()
	var q := 0.0
	if e < -12.0:
		q = 0.30
	elif e < -4.0:
		q = 0.72                                   # blue hour
	elif e < 1.0:
		q = 0.88
	elif e < 8.0:
		q = 1.0                                    # golden hour
	elif e < 16.0:
		q = 0.82
	elif e < 30.0:
		q = 0.62
	else:
		q = 0.45                                   # flat overhead sun
	# A little cloud softens light nicely; a lot of it kills the modelling.
	if cloud_cover < 0.4:
		q *= 1.0 + cloud_cover * 0.25
	else:
		q *= lerpf(1.1, 0.66, (cloud_cover - 0.4) / 0.6)
	if precipitation > 0.3:
		q *= 0.9
	return clampf(q, 0.0, 1.0)


func sun_color() -> Color:
	var e := sun_elevation_degrees()
	if e < -6.0:
		return Color(0.30, 0.42, 0.72)
	if e < 0.0:
		return Color(0.86, 0.52, 0.42).lerp(Color(0.45, 0.48, 0.72),
			clampf(-e / 6.0, 0.0, 1.0))
	if e < 6.0:
		return Color(1.0, 0.62, 0.32).lerp(Color(1.0, 0.82, 0.60), e / 6.0)
	if e < 18.0:
		return Color(1.0, 0.82, 0.60).lerp(Color(1.0, 0.95, 0.88), (e - 6.0) / 12.0)
	return Color(1.0, 0.97, 0.92)


func _apply(_delta: float) -> void:
	var elev := sun_elevation_degrees()
	var dir := sun_direction()
	sun.look_at_from_position(Vector3.ZERO, dir, Vector3.UP)
	moon.look_at_from_position(Vector3.ZERO, -dir, Vector3.UP)

	var day := clampf((elev + 6.0) / 12.0, 0.0, 1.0)
	var col := sun_color()
	sun.light_color = col
	var base_energy: float = lerpf(0.0, 1.35, clampf((elev + 4.0) / 22.0, 0.0, 1.0))
	base_energy *= lerpf(1.0, 0.42, cloud_cover)
	base_energy *= light_multiplier
	sun.light_energy = base_energy + _flash * 3.0
	sun.visible = elev > -6.0 or _flash > 0.0

	var night := clampf(-elev / 10.0, 0.0, 1.0)
	moon.light_energy = night * 0.10
	moon.visible = night > 0.01

	# --- sky --------------------------------------------------------------
	var biome := _biome_ref if _biome_ref != null else BiomeLibrary.get_biome("emerald_vale")
	var night_top := Color(0.017, 0.024, 0.052)
	var night_horizon := Color(0.05, 0.07, 0.13)
	var top := biome.sky_top
	var horizon := biome.sky_horizon
	# Warm the horizon through sunrise and sunset.
	var warm := clampf(1.0 - absf(elev) / 10.0, 0.0, 1.0)
	horizon = horizon.lerp(Color(1.0, 0.55, 0.30), warm * 0.75)
	top = top.lerp(Color(0.30, 0.36, 0.62), warm * 0.35)
	# Overcast flattens the gradient toward grey.
	var grey := Color(0.62, 0.64, 0.66)
	top = top.lerp(grey, cloud_cover * 0.7)
	horizon = horizon.lerp(grey.lightened(0.1), cloud_cover * 0.7)

	_sky_material.set_shader_parameter("top_color", night_top.lerp(top, day))
	_sky_material.set_shader_parameter("horizon_color", night_horizon.lerp(horizon, day))
	_sky_material.set_shader_parameter("ground_color",
		night_top.lerp(biome.ground_horizon, day))
	_sky_material.set_shader_parameter("sun_tint", col)
	_sky_material.set_shader_parameter("exposure", lerpf(0.14, 1.0, day))
	_sky_material.set_shader_parameter("cloud_cover", cloud_cover)
	_sky_material.set_shader_parameter("cloud_sharpness",
		lerpf(2.6, 1.1, cloud_cover))
	_sky_material.set_shader_parameter("haze", clampf(0.25 + precipitation * 0.5
		+ cloud_cover * 0.25, 0.0, 1.0))
	_sky_material.set_shader_parameter("star_amount", clampf(night * 1.3 - cloud_cover,
		0.0, 1.0))
	_sky_material.set_shader_parameter("sun_disc", clampf(1.0 - cloud_cover * 1.1,
		0.0, 1.0))
	_sky_material.set_shader_parameter("wind_offset", _cloud_drift)
	# Cloud bellies pick up the colour of the sun, which is most of what makes
	# a sunrise read as a sunrise.
	_sky_material.set_shader_parameter("cloud_lit",
		Color(1.0, 0.97, 0.94).lerp(col, 0.55) * lerpf(0.25, 1.0, day))
	_sky_material.set_shader_parameter("cloud_shadow",
		Color(0.42, 0.45, 0.52).lerp(col.darkened(0.4), 0.35) * lerpf(0.18, 1.0, day))

	# --- ambient and exposure ---------------------------------------------
	# Sky ambient is the only light reaching anything the sun cannot see, so it
	# carries the whole forest floor. Under-tune it and shade goes to mud.
	environment.ambient_light_energy = lerpf(0.08, 1.35, day) * lerpf(1.0, 1.25, cloud_cover)
	environment.tonemap_exposure = clampf(exposure_compensation, 0.02, 24.0)

	# --- fog ---------------------------------------------------------------
	var fog_col := biome.fog_color.lerp(col, 0.25 * clampf(day, 0.0, 1.0))
	fog_col = fog_col.lerp(night_horizon, night * 0.85)
	environment.fog_light_color = fog_col
	# Dawn fog: the still hour after sunrise gets noticeably thicker air.
	var dawn_boost := 1.0 + clampf(1.0 - absf(elev - 2.0) / 8.0, 0.0, 1.0) * 0.9
	environment.fog_density = biome.fog_density * fog_multiplier * dawn_boost \
		* lerpf(1.0, 1.8, precipitation)
	environment.fog_light_energy = lerpf(0.1, 1.0, day)
	# Mist gathers in the low ground overnight and lifts through the morning.
	var still_air := clampf(1.0 - absf(elev - 3.0) / 14.0, 0.0, 1.0)
	environment.fog_height_density = clampf(
		0.008 + still_air * 0.045 + precipitation * 0.03, 0.0, 0.12) * fog_multiplier
	if environment.volumetric_fog_enabled:
		environment.volumetric_fog_density = clampf(
			0.006 + biome.fog_density * 3.0 * fog_multiplier, 0.0, 0.09)
		environment.volumetric_fog_albedo = fog_col

	var phase := light_phase()
	if phase != _phase:
		_phase = phase
		light_phase_changed.emit(phase)


func lightning_flash() -> void:
	_flash = 1.0


func set_time(hour: float) -> void:
	time_of_day = fposmod(hour, 24.0)
	_apply(0.0)


func advance_time(hours: float) -> void:
	set_time(time_of_day + hours)


func clock_string() -> String:
	var h := int(floor(time_of_day))
	var m := int((time_of_day - float(h)) * 60.0)
	return "%02d:%02d" % [h, m]
