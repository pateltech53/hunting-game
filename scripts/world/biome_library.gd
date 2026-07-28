class_name BiomeLibrary
extends RefCounted
## The seven regions a world can be made of.

const DATA := [
	{
		"id": "emerald_vale", "name": "Emerald Vale",
		"blurb": "Temperate broadleaf forest broken by meadows and slow streams.",
		"grass_a": Color(0.31, 0.47, 0.22), "grass_b": Color(0.24, 0.39, 0.18),
		"dirt": Color(0.35, 0.26, 0.17), "rock": Color(0.44, 0.45, 0.44),
		"sand": Color(0.75, 0.71, 0.53),
		"tree_density": 0.034, "tree_kinds": ["broadleaf", "broadleaf", "birch", "pine"],
		"trunk": Color(0.30, 0.22, 0.15),
		"foliage": [Color(0.20, 0.40, 0.16), Color(0.25, 0.46, 0.19), Color(0.16, 0.34, 0.14)],
		"rock_density": 0.005, "bush_density": 0.030,
		"grass_tuft": Color(0.34, 0.52, 0.24),
		"flower_colors": [Color(0.92, 0.90, 0.42), Color(0.88, 0.88, 0.92)],
		"flower_density": 0.012,
		"fog_color": Color(0.63, 0.72, 0.76), "fog_density": 0.0020,
		"sky_top": Color(0.22, 0.42, 0.74), "sky_horizon": Color(0.74, 0.83, 0.88),
		"ground_horizon": Color(0.36, 0.38, 0.34),
		"water_color": Color(0.14, 0.31, 0.34, 0.74),
		"wind_strength": 0.35, "bird_activity": 1.2, "footstep_surface": "grass",
		"village_chance": 0.55, "roughness": 1.0,
	},
	{
		"id": "amber_woods", "name": "Amber Woods",
		"blurb": "Late-autumn hardwoods. Low sun, long shadows, colour everywhere.",
		"grass_a": Color(0.44, 0.40, 0.21), "grass_b": Color(0.36, 0.31, 0.17),
		"dirt": Color(0.34, 0.24, 0.15), "rock": Color(0.45, 0.42, 0.38),
		"sand": Color(0.72, 0.64, 0.46),
		"tree_density": 0.040, "tree_kinds": ["broadleaf", "broadleaf", "broadleaf", "birch"],
		"trunk": Color(0.27, 0.19, 0.13),
		"foliage": [Color(0.74, 0.36, 0.12), Color(0.83, 0.55, 0.15),
			Color(0.62, 0.22, 0.12), Color(0.72, 0.62, 0.20)],
		"rock_density": 0.004, "bush_density": 0.035,
		"grass_tuft": Color(0.50, 0.42, 0.20),
		"flower_colors": [Color(0.86, 0.46, 0.18)], "flower_density": 0.008,
		"fog_color": Color(0.76, 0.68, 0.56), "fog_density": 0.0030,
		"sky_top": Color(0.26, 0.42, 0.68), "sky_horizon": Color(0.86, 0.79, 0.66),
		"ground_horizon": Color(0.40, 0.34, 0.26),
		"water_color": Color(0.18, 0.28, 0.28, 0.76),
		"wind_strength": 0.5, "bird_activity": 0.9, "footstep_surface": "grass",
		"village_chance": 0.45, "roughness": 1.05,
	},
	{
		"id": "boreal_taiga", "name": "Boreal Taiga",
		"blurb": "Dense spruce, deep cold and snow that never quite leaves the shade.",
		"grass_a": Color(0.24, 0.33, 0.22), "grass_b": Color(0.19, 0.27, 0.19),
		"dirt": Color(0.28, 0.23, 0.18), "rock": Color(0.48, 0.49, 0.52),
		"sand": Color(0.68, 0.67, 0.62), "snow": Color(0.92, 0.94, 0.98),
		"snow_line": 40.0,
		"tree_density": 0.052, "tree_kinds": ["pine", "pine", "pine", "dead"],
		"trunk": Color(0.24, 0.18, 0.14),
		"foliage": [Color(0.13, 0.28, 0.20), Color(0.10, 0.23, 0.17), Color(0.17, 0.33, 0.23)],
		"rock_density": 0.008, "bush_density": 0.020,
		"grass_tuft": Color(0.26, 0.36, 0.23),
		"flower_colors": [], "flower_density": 0.0,
		"fog_color": Color(0.66, 0.72, 0.78), "fog_density": 0.0038,
		"sky_top": Color(0.20, 0.36, 0.62), "sky_horizon": Color(0.72, 0.80, 0.87),
		"ground_horizon": Color(0.30, 0.34, 0.34),
		"water_color": Color(0.11, 0.24, 0.30, 0.78),
		"wind_strength": 0.65, "bird_activity": 0.5, "footstep_surface": "snow",
		"village_chance": 0.25, "roughness": 1.15,
	},
	{
		"id": "mistwood_marsh", "name": "Mistwood Marsh",
		"blurb": "Flooded woodland. Standing water, reeds, and fog that sits until noon.",
		"grass_a": Color(0.27, 0.38, 0.24), "grass_b": Color(0.22, 0.31, 0.20),
		"dirt": Color(0.25, 0.22, 0.16), "rock": Color(0.38, 0.40, 0.38),
		"sand": Color(0.55, 0.52, 0.40),
		"tree_density": 0.036, "tree_kinds": ["willow", "dead", "broadleaf"],
		"trunk": Color(0.25, 0.21, 0.16),
		"foliage": [Color(0.24, 0.38, 0.22), Color(0.30, 0.44, 0.24), Color(0.19, 0.31, 0.19)],
		"rock_density": 0.002, "bush_density": 0.055,
		"grass_tuft": Color(0.33, 0.44, 0.24),
		"flower_colors": [Color(0.85, 0.84, 0.90)], "flower_density": 0.006,
		"fog_color": Color(0.70, 0.74, 0.72), "fog_density": 0.0062,
		"sky_top": Color(0.28, 0.42, 0.60), "sky_horizon": Color(0.80, 0.83, 0.80),
		"ground_horizon": Color(0.32, 0.34, 0.30),
		"water_color": Color(0.14, 0.24, 0.22, 0.82),
		"wind_strength": 0.2, "bird_activity": 1.4, "footstep_surface": "water",
		"village_chance": 0.15, "height_bias": -5.0, "roughness": 0.55,
	},
	{
		"id": "golden_steppe", "name": "Golden Steppe",
		"blurb": "Open grassland running to the horizon. Nowhere to hide, for anyone.",
		"grass_a": Color(0.68, 0.60, 0.30), "grass_b": Color(0.58, 0.52, 0.26),
		"dirt": Color(0.44, 0.35, 0.22), "rock": Color(0.55, 0.51, 0.44),
		"sand": Color(0.80, 0.74, 0.54),
		"tree_density": 0.0045, "tree_kinds": ["broadleaf", "dead"],
		"trunk": Color(0.33, 0.25, 0.17),
		"foliage": [Color(0.36, 0.42, 0.20), Color(0.44, 0.46, 0.22)],
		"rock_density": 0.004, "bush_density": 0.018,
		"grass_tuft": Color(0.72, 0.64, 0.32),
		"flower_colors": [Color(0.92, 0.72, 0.22), Color(0.78, 0.42, 0.52)],
		"flower_density": 0.016,
		"fog_color": Color(0.80, 0.78, 0.66), "fog_density": 0.0016,
		"sky_top": Color(0.22, 0.44, 0.78), "sky_horizon": Color(0.86, 0.84, 0.72),
		"ground_horizon": Color(0.50, 0.45, 0.32),
		"water_color": Color(0.18, 0.34, 0.36, 0.72),
		"wind_strength": 0.8, "bird_activity": 0.7, "footstep_surface": "grass",
		"village_chance": 0.5, "roughness": 0.6, "height_bias": -2.0,
	},
	{
		"id": "ochre_badlands", "name": "Ochre Badlands",
		"blurb": "Stacked sandstone benches and dry washes. Brutal light at midday.",
		"grass_a": Color(0.72, 0.48, 0.30), "grass_b": Color(0.62, 0.40, 0.26),
		"dirt": Color(0.56, 0.34, 0.22), "rock": Color(0.66, 0.44, 0.30),
		"sand": Color(0.85, 0.71, 0.48),
		"tree_density": 0.006, "tree_kinds": ["dead", "cactus"],
		"trunk": Color(0.38, 0.27, 0.18),
		"foliage": [Color(0.32, 0.40, 0.22), Color(0.40, 0.44, 0.24)],
		"rock_density": 0.020, "bush_density": 0.012,
		"grass_tuft": Color(0.66, 0.54, 0.30),
		"flower_colors": [Color(0.88, 0.36, 0.30)], "flower_density": 0.004,
		"fog_color": Color(0.84, 0.72, 0.56), "fog_density": 0.0014,
		"sky_top": Color(0.24, 0.46, 0.80), "sky_horizon": Color(0.90, 0.80, 0.62),
		"ground_horizon": Color(0.58, 0.40, 0.26),
		"water_color": Color(0.22, 0.36, 0.34, 0.70),
		"wind_strength": 0.6, "bird_activity": 0.4, "footstep_surface": "gravel",
		"village_chance": 0.2, "roughness": 1.6, "height_bias": 3.0,
	},
	{
		"id": "alpine_ridge", "name": "Alpine Ridge",
		"blurb": "Above the treeline. Rock, lichen and weather that changes its mind.",
		"grass_a": Color(0.40, 0.44, 0.32), "grass_b": Color(0.46, 0.46, 0.42),
		"dirt": Color(0.38, 0.36, 0.32), "rock": Color(0.52, 0.53, 0.56),
		"sand": Color(0.62, 0.62, 0.60), "snow": Color(0.95, 0.96, 0.99),
		"snow_line": 52.0,
		"tree_density": 0.012, "tree_kinds": ["pine", "dead"],
		"trunk": Color(0.26, 0.20, 0.16),
		"foliage": [Color(0.14, 0.26, 0.19), Color(0.18, 0.30, 0.21)],
		"rock_density": 0.030, "bush_density": 0.010,
		"grass_tuft": Color(0.42, 0.46, 0.32),
		"flower_colors": [Color(0.72, 0.74, 0.92)], "flower_density": 0.006,
		"fog_color": Color(0.74, 0.80, 0.88), "fog_density": 0.0026,
		"sky_top": Color(0.14, 0.32, 0.68), "sky_horizon": Color(0.70, 0.80, 0.90),
		"ground_horizon": Color(0.42, 0.44, 0.46),
		"water_color": Color(0.20, 0.42, 0.48, 0.66),
		"wind_strength": 1.0, "bird_activity": 0.3, "footstep_surface": "gravel",
		"village_chance": 0.1, "roughness": 1.9, "height_bias": 14.0,
	},
]

static var _cache: Dictionary = {}
static var _order: Array = []


static func _ensure() -> void:
	if not _cache.is_empty():
		return
	for entry: Dictionary in DATA:
		var b := Biome.from_dict(entry)
		_cache[b.id] = b
		_order.append(b.id)


static func get_biome(id: String) -> Biome:
	_ensure()
	return _cache.get(id, _cache.get("emerald_vale"))


static func all() -> Array:
	_ensure()
	return _cache.values()


static func ids() -> Array:
	_ensure()
	return _order.duplicate()


static func display_name(id: String) -> String:
	var b := get_biome(id)
	return b.name if b != null else "Unknown"


## Chooses a biome from climate values. Altitude wins at the extremes.
static func classify(temperature: float, moisture: float, altitude: float,
		sea_level: float) -> String:
	if altitude > sea_level + 26.0:
		return "alpine_ridge"
	if altitude < sea_level + 2.0 and moisture > 0.05:
		return "mistwood_marsh"
	if temperature < -0.22:
		return "boreal_taiga"
	if temperature > 0.30 and moisture < -0.08:
		return "ochre_badlands"
	if moisture > 0.28:
		return "mistwood_marsh"
	if moisture < -0.20:
		return "golden_steppe"
	if temperature > 0.06:
		return "amber_woods"
	return "emerald_vale"
