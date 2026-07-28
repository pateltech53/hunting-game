class_name Biome
extends RefCounted
## Palette, flora and atmosphere for one region of a world.

var id: String = ""
var name: String = ""
var blurb: String = ""

# Ground palette. Surface colour is picked between grass_a and grass_b by a
# variation noise, then blended toward rock on steep slopes.
var grass_a: Color = Color(0.30, 0.45, 0.21)
var grass_b: Color = Color(0.24, 0.38, 0.18)
var dirt: Color = Color(0.36, 0.27, 0.18)
var rock: Color = Color(0.42, 0.42, 0.44)
var sand: Color = Color(0.76, 0.70, 0.50)
var snow: Color = Color(0.93, 0.95, 0.98)
var snow_line: float = 999.0

# Flora
var tree_density: float = 0.05
var tree_kinds: Array = ["broadleaf"]
var trunk: Color = Color(0.29, 0.21, 0.14)
var foliage: Array = [Color(0.22, 0.40, 0.18)]
var rock_density: float = 0.006
var bush_density: float = 0.02
var grass_tuft: Color = Color(0.35, 0.50, 0.24)
var flower_colors: Array = []
var flower_density: float = 0.0

# Atmosphere
var fog_color: Color = Color(0.62, 0.70, 0.78)
var fog_density: float = 0.0022
var sky_top: Color = Color(0.24, 0.42, 0.72)
var sky_horizon: Color = Color(0.72, 0.80, 0.88)
var ground_horizon: Color = Color(0.42, 0.42, 0.40)
var water_color: Color = Color(0.16, 0.32, 0.38, 0.72)
var wind_strength: float = 0.4
var bird_activity: float = 1.0
var footstep_surface: String = "grass"

# Terrain shaping
var height_bias: float = 0.0
var roughness: float = 1.0
var village_chance: float = 0.0


static func from_dict(data: Dictionary) -> Biome:
	var b := Biome.new()
	for key: String in data:
		if key in b:
			b.set(key, data[key])
	return b
