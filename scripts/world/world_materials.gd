class_name WorldMaterials
extends RefCounted
## The shaders the world is drawn with.
##
## Vegetation and water move: both read a global wind vector that the weather
## system writes every frame, so a gale visibly bends the grass and chops up
## the lake instead of just changing a number in the HUD.

const WIND_PARAM := "wildlight_wind"
const WETNESS_PARAM := "wildlight_wetness"

static var _terrain: StandardMaterial3D = null
static var _creature: StandardMaterial3D = null
static var _foliage: ShaderMaterial = null
static var _grass: ShaderMaterial = null
static var _water: ShaderMaterial = null
static var _globals_ready := false


## Registers the global shader parameters every material below reads.
static func ensure_globals() -> void:
	if _globals_ready:
		return
	_globals_ready = true
	if not RenderingServer.global_shader_parameter_get_list().has(WIND_PARAM):
		RenderingServer.global_shader_parameter_add(WIND_PARAM,
			RenderingServer.GLOBAL_VAR_TYPE_VEC3, Vector3(0.3, 0.0, 0.1))
	if not RenderingServer.global_shader_parameter_get_list().has(WETNESS_PARAM):
		RenderingServer.global_shader_parameter_add(WETNESS_PARAM,
			RenderingServer.GLOBAL_VAR_TYPE_FLOAT, 0.0)


static func set_wind(direction: Vector3, strength: float) -> void:
	ensure_globals()
	RenderingServer.global_shader_parameter_set(WIND_PARAM,
		Vector3(direction.x, 0.0, direction.z).normalized() * strength)


static func set_wetness(value: float) -> void:
	ensure_globals()
	RenderingServer.global_shader_parameter_set(WETNESS_PARAM, clampf(value, 0.0, 1.0))


# ------------------------------------------------------------------- terrain

static func terrain() -> StandardMaterial3D:
	if _terrain != null:
		return _terrain
	_terrain = StandardMaterial3D.new()
	_terrain.vertex_color_use_as_albedo = true
	_terrain.roughness = 0.95
	_terrain.metallic = 0.0
	_terrain.specular_mode = BaseMaterial3D.SPECULAR_SCHLICK_GGX
	_terrain.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	_terrain.cull_mode = BaseMaterial3D.CULL_BACK
	return _terrain


## Animals and people. No wind: they move under their own power.
static func creature() -> StandardMaterial3D:
	if _creature != null:
		return _creature
	_creature = StandardMaterial3D.new()
	_creature.vertex_color_use_as_albedo = true
	_creature.roughness = 0.88
	_creature.metallic = 0.0
	_creature.specular_mode = BaseMaterial3D.SPECULAR_SCHLICK_GGX
	_creature.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	return _creature


# ------------------------------------------------------------------ foliage

static func foliage() -> ShaderMaterial:
	if _foliage != null:
		return _foliage
	ensure_globals()
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_disabled;

global uniform vec3 wildlight_wind;
global uniform float wildlight_wetness;

void vertex() {
	// Sway grows with height up the tree, so the crown moves and the base does
	// not. Two frequencies keep it from looking like a metronome.
	vec3 origin = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float phase = TIME * 1.15 + origin.x * 0.24 + origin.z * 0.19;
	float gust = sin(phase) * 0.65 + sin(phase * 2.3 + 1.7) * 0.35;
	float amount = pow(max(VERTEX.y, 0.0), 1.25) * 0.020;
	VERTEX.xz += wildlight_wind.xz * gust * amount;
	VERTEX.y -= abs(gust) * amount * 0.25;
}

void fragment() {
	ALBEDO = COLOR.rgb;
	ROUGHNESS = mix(0.94, 0.62, wildlight_wetness);
	SPECULAR = mix(0.1, 0.35, wildlight_wetness);
	// Leaves pass a little light when the sun is behind them. Keep this low:
	// backlight adds energy, and too much turns autumn foliage into neon.
	BACKLIGHT = COLOR.rgb * 0.10 + vec3(0.015, 0.022, 0.010);
}
"""
	_foliage = ShaderMaterial.new()
	_foliage.shader = shader
	return _foliage


# -------------------------------------------------------------------- grass

static func grass() -> ShaderMaterial:
	if _grass != null:
		return _grass
	ensure_globals()
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_disabled;

global uniform vec3 wildlight_wind;

void vertex() {
	// Grass is the most responsive thing in the scene - it should ripple.
	vec3 origin = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float phase = TIME * 2.1 + origin.x * 0.55 + origin.z * 0.47;
	float gust = sin(phase) * 0.6 + sin(phase * 3.1 + 0.8) * 0.4;
	float amount = pow(max(VERTEX.y, 0.0), 1.1) * 0.55;
	VERTEX.xz += wildlight_wind.xz * gust * amount;
}

void fragment() {
	ALBEDO = COLOR.rgb;
	ROUGHNESS = 0.95;
	BACKLIGHT = COLOR.rgb * 0.16;
}
"""
	_grass = ShaderMaterial.new()
	_grass.shader = shader
	return _grass


# -------------------------------------------------------------------- water

static func water(tint: Color) -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

global uniform vec3 wildlight_wind;
uniform vec4 tint : source_color = vec4(0.14, 0.31, 0.34, 0.78);

// Cheap wave normal: two crossing sine sets, no texture lookups.
vec3 wave_normal(vec2 p, float t, float choppiness) {
	float a = sin(p.x * 0.55 + t * 1.10) * cos(p.y * 0.42 - t * 0.80);
	float b = sin(p.x * 0.21 - t * 0.55) * cos(p.y * 0.33 + t * 0.45);
	float dx = cos(p.x * 0.55 + t * 1.10) * 0.55 * cos(p.y * 0.42 - t * 0.80)
		+ cos(p.x * 0.21 - t * 0.55) * 0.21 * cos(p.y * 0.33 + t * 0.45);
	float dz = -sin(p.x * 0.55 + t * 1.10) * sin(p.y * 0.42 - t * 0.80) * 0.42
		+ -sin(p.x * 0.21 - t * 0.55) * sin(p.y * 0.33 + t * 0.45) * 0.33;
	return normalize(vec3(-dx * choppiness, 4.0, -dz * choppiness));
}

void fragment() {
	float choppiness = 0.35 + length(wildlight_wind.xz) * 1.6;
	vec3 n = wave_normal(VERTEX.xz + NODE_POSITION_WORLD.xz, TIME, choppiness);
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);

	float fresnel = pow(1.0 - clamp(dot(normalize(VIEW), NORMAL), 0.0, 1.0), 3.0);
	ALBEDO = mix(tint.rgb, tint.rgb * 1.8 + vec3(0.10, 0.14, 0.16), fresnel);
	ALPHA = clamp(tint.a + fresnel * 0.35, 0.0, 1.0);
	ROUGHNESS = 0.06;
	METALLIC = 0.0;
	SPECULAR = 0.85;
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("tint", tint)
	mat.render_priority = 1
	return mat
