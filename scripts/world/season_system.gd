class_name SeasonSystem
extends Node
## The turning year.
##
## A season is not a filter over the world - it changes what the forest looks
## like, how much of it is buried, and which animals are up and about. Autumn
## is the photographer's season and winter is the tracker's, which is the whole
## reason for having them.

signal season_changed(id: String, display: String)

enum Season { SPRING, SUMMER, AUTUMN, WINTER }

const NAMES := {
	Season.SPRING: "Spring",
	Season.SUMMER: "Summer",
	Season.AUTUMN: "Autumn",
	Season.WINTER: "Winter",
}

const BLURBS := {
	Season.SPRING: "New growth, swollen rivers, and everything with young at heel.",
	Season.SUMMER: "Heavy green and long light. The animals keep to the shade at noon.",
	Season.AUTUMN: "The colour is worth the walk. Stags are in rut and moving.",
	Season.WINTER: "Bare ground, hard light, and every track written in the snow.",
}

## Multiplied into foliage albedo. Spring is fresh and slightly yellow, summer
## is true green, autumn swings to amber, winter is drab and grey-brown.
const FOLIAGE_TINT := {
	Season.SPRING: Color(1.06, 1.12, 0.82),
	Season.SUMMER: Color(1.00, 1.00, 1.00),
	Season.AUTUMN: Color(1.55, 0.92, 0.42),
	Season.WINTER: Color(0.82, 0.78, 0.72),
}

## How much snow lies on the ground, before biome and altitude.
const SNOW := {
	Season.SPRING: 0.05,
	Season.SUMMER: 0.0,
	Season.AUTUMN: 0.0,
	Season.WINTER: 0.85,
}

## Wildlife is scarcer in winter and busiest in spring and autumn.
const ACTIVITY := {
	Season.SPRING: 1.15,
	Season.SUMMER: 1.0,
	Season.AUTUMN: 1.10,
	Season.WINTER: 0.65,
}

const TINT_PARAM := "wildlight_season_tint"
const SNOW_PARAM := "wildlight_snow"

## Real minutes for a full year. Long enough that a season is a stretch of
## play rather than a strobe, short enough that a long session sees two.
var year_minutes := 48.0
var season: Season = Season.AUTUMN
## 0..4, fractional part is progress through the current season.
var year_position := 2.0

var sky: SkySystem
var _last_season: Season = Season.AUTUMN
var _tint := Color(1, 1, 1)
var _snow := 0.0


func _ready() -> void:
	_ensure_globals()


func _ensure_globals() -> void:
	var existing := RenderingServer.global_shader_parameter_get_list()
	if not existing.has(TINT_PARAM):
		RenderingServer.global_shader_parameter_add(TINT_PARAM,
			RenderingServer.GLOBAL_VAR_TYPE_VEC3, Vector3.ONE)
	if not existing.has(SNOW_PARAM):
		RenderingServer.global_shader_parameter_add(SNOW_PARAM,
			RenderingServer.GLOBAL_VAR_TYPE_FLOAT, 0.0)


func setup(sky_system: SkySystem, starting: Season = Season.AUTUMN) -> void:
	sky = sky_system
	season = starting
	_last_season = starting
	year_position = float(int(starting))
	_apply(true)
	season_changed.emit(id(), display_name())


func _process(delta: float) -> void:
	if Game.is_paused:
		return
	year_position = fposmod(year_position + delta * (4.0 / (year_minutes * 60.0)), 4.0)
	season = int(floorf(year_position)) as Season
	if season != _last_season:
		_last_season = season
		season_changed.emit(id(), display_name())
		Game.notify("%s. %s" % [display_name(), BLURBS[season]], "info")
	_apply(false)


## Blends across the boundary so the forest turns rather than snapping. The
## last fifth of a season is already reaching for the next one.
func _apply(immediate: bool) -> void:
	var f: float = year_position - floorf(year_position)
	var blend: float = smoothstep(0.80, 1.0, f)
	var next: Season = ((int(season) + 1) % 4) as Season

	var want_tint: Color = (FOLIAGE_TINT[season] as Color).lerp(
		FOLIAGE_TINT[next] as Color, blend)
	var want_snow: float = lerpf(SNOW[season], SNOW[next], blend)

	if immediate:
		_tint = want_tint
		_snow = want_snow
	else:
		# Slow enough that you notice it having happened rather than happening.
		var rate := 0.25
		_tint = _tint.lerp(want_tint, rate * get_process_delta_time())
		_snow = lerpf(_snow, want_snow, rate * get_process_delta_time())

	RenderingServer.global_shader_parameter_set(TINT_PARAM,
		Vector3(_tint.r, _tint.g, _tint.b))
	RenderingServer.global_shader_parameter_set(SNOW_PARAM, _snow)
	WorldMaterials.apply_season(_tint, _snow)


func id() -> String:
	return NAMES[season].to_lower()


func display_name() -> String:
	return NAMES[season]


func blurb() -> String:
	return BLURBS[season]


func snow_depth() -> float:
	return _snow


func activity_modifier() -> float:
	return float(ACTIVITY[season])


## Days are shorter in winter and longer in summer, which the sky system uses
## to move sunrise and sunset around.
func daylight_bias() -> float:
	match season:
		Season.WINTER:
			return -1.4
		Season.SUMMER:
			return 1.4
		_:
			return 0.0


func set_season(value: Season) -> void:
	year_position = float(int(value))
	season = value
	_last_season = value
	_apply(true)
	season_changed.emit(id(), display_name())
