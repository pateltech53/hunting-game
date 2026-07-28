class_name TerrainGenerator
extends RefCounted
## Deterministic, thread-safe world sampling. Everything about a world is a
## pure function of its seed and a pair of coordinates, so chunks can be built
## on worker threads in any order and still agree with each other.

const SEA_LEVEL := 26
const MAX_HEIGHT := 110

var world_seed: int = 0

var _continent := FastNoiseLite.new()
var _hills := FastNoiseLite.new()
var _detail := FastNoiseLite.new()
var _temperature := FastNoiseLite.new()
var _moisture := FastNoiseLite.new()
var _river := FastNoiseLite.new()
var _variation := FastNoiseLite.new()
var _forest := FastNoiseLite.new()


func _init(seed_value: int) -> void:
	world_seed = seed_value
	_configure(_continent, seed_value, FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 0.0016, 4, 0.5)
	_configure(_hills, seed_value + 101, FastNoiseLite.TYPE_SIMPLEX, 0.0075, 3, 0.5)
	_configure(_detail, seed_value + 202, FastNoiseLite.TYPE_SIMPLEX, 0.045, 2, 0.5)
	_configure(_temperature, seed_value + 303, FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 0.00085, 2, 0.5)
	_configure(_moisture, seed_value + 404, FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 0.00095, 2, 0.5)
	_configure(_variation, seed_value + 505, FastNoiseLite.TYPE_SIMPLEX, 0.09, 1, 0.5)
	_configure(_forest, seed_value + 606, FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 0.006, 2, 0.5)
	_river.seed = seed_value + 707
	_river.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_river.frequency = 0.0022
	_river.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	_river.fractal_octaves = 2


func _configure(n: FastNoiseLite, s: int, type: int, freq: float, octaves: int,
		gain: float) -> void:
	n.seed = s
	n.noise_type = type
	n.frequency = freq
	n.fractal_type = FastNoiseLite.FRACTAL_FBM
	n.fractal_octaves = octaves
	n.fractal_gain = gain


# ------------------------------------------------------------------- sampling

func temperature_at(x: float, z: float) -> float:
	# Cools with altitude so ridges read as alpine even in a warm latitude.
	var base := _temperature.get_noise_2d(x, z)
	return base


func moisture_at(x: float, z: float) -> float:
	return _moisture.get_noise_2d(x, z)


## 1.0 in the middle of a river channel, falling to 0 at the banks.
func river_factor(x: float, z: float) -> float:
	var r: float = absf(_river.get_noise_2d(x, z))
	var channel := 1.0 - smoothstep(0.0, 0.055, r)
	return channel


func height_at(x: float, z: float) -> float:
	var c := _continent.get_noise_2d(x, z)
	var mountain := clampf((c - 0.10) / 0.55, 0.0, 1.0)
	var hills := _hills.get_noise_2d(x, z)
	var detail := _detail.get_noise_2d(x, z)

	var h := float(SEA_LEVEL) + c * 17.0
	h += hills * 9.0 * (0.45 + mountain * 1.5)
	h += detail * 2.2 * (0.6 + mountain)
	h += mountain * mountain * 40.0

	# Biome-specific shaping (bias and roughness) applied as a soft nudge.
	var biome := BiomeLibrary.get_biome(_climate_biome(x, z, h))
	h += biome.height_bias
	h = float(SEA_LEVEL) + (h - float(SEA_LEVEL)) * biome.roughness

	# Carve river channels, but not through the high peaks.
	var river := river_factor(x, z) * clampf(1.0 - mountain * 1.6, 0.0, 1.0)
	if river > 0.0:
		h = lerpf(h, minf(h, float(SEA_LEVEL) - 2.5), river)

	return clampf(h, 2.0, float(MAX_HEIGHT))


func height_i(x: int, z: int) -> int:
	return int(floor(height_at(float(x), float(z))))


## Biome for a column whose height is already known. Callers that have cached
## a height grid should use this - [method biome_at] has to re-derive it.
func biome_from_height(x: float, z: float, height: float) -> String:
	var t := temperature_at(x, z) - clampf((height - float(SEA_LEVEL)) / 90.0, 0.0, 1.0) * 0.5
	var m := moisture_at(x, z) + river_factor(x, z) * 0.35
	return BiomeLibrary.classify(t, m, height, float(SEA_LEVEL))


func _climate_biome(x: float, z: float, height: float) -> String:
	return biome_from_height(x, z, height)


func biome_at(x: float, z: float) -> String:
	return _climate_biome(x, z, height_at(x, z))


func biome_at_i(x: int, z: int) -> String:
	return biome_at(float(x), float(z))


## Slope in blocks per block, sampled across the four neighbours.
func slope_at(x: int, z: int, h: int) -> float:
	var dh := 0
	dh = maxi(dh, absi(height_i(x + 1, z) - h))
	dh = maxi(dh, absi(height_i(x - 1, z) - h))
	dh = maxi(dh, absi(height_i(x, z + 1) - h))
	dh = maxi(dh, absi(height_i(x, z - 1) - h))
	return float(dh)


## Stable per-column pseudo random in 0..1. Cheaper than a noise lookup and
## gives us independent streams via [param salt].
func hash01(x: int, z: int, salt: int = 0) -> float:
	var n: int = x * 374761393 + z * 668265263 + salt * 2147483647 + world_seed * 1442695041
	n = (n ^ (n >> 13)) * 1274126177
	n = n ^ (n >> 16)
	return float(absi(n) % 100000) / 100000.0


func surface_color(x: int, z: int, h: int, biome: Biome, slope: float) -> Color:
	var c: Color
	if h <= SEA_LEVEL - 1:
		c = biome.dirt.lerp(biome.sand, 0.45)
	elif h <= SEA_LEVEL + 1:
		c = biome.sand
	elif slope >= 3.0:
		c = biome.rock
	elif slope >= 2.0:
		c = biome.rock.lerp(biome.grass_a, 0.45)
	else:
		var v := _variation.get_noise_2d(float(x), float(z)) * 0.5 + 0.5
		c = biome.grass_b.lerp(biome.grass_a, v)
		if float(h) > biome.snow_line:
			var t := clampf((float(h) - biome.snow_line) / 12.0, 0.0, 1.0)
			c = c.lerp(biome.snow, t)
	# Slight per-voxel value jitter keeps large flat areas from banding.
	var jitter := (hash01(x, z, 7) - 0.5) * 0.07
	return Color(clampf(c.r + jitter, 0.0, 1.0), clampf(c.g + jitter, 0.0, 1.0),
		clampf(c.b + jitter, 0.0, 1.0))


func is_water(h: int) -> bool:
	return h < SEA_LEVEL


## Everything the mesher needs about one column, in a single call.
func column(x: int, z: int) -> Dictionary:
	var h := height_i(x, z)
	var biome_id := biome_at(float(x), float(z))
	var biome := BiomeLibrary.get_biome(biome_id)
	var slope := slope_at(x, z, h)
	return {
		"h": h,
		"biome": biome_id,
		"biome_ref": biome,
		"color": surface_color(x, z, h, biome, slope),
		"slope": slope,
		"water": is_water(h),
	}


# -------------------------------------------------------------- flora queries

## Returns the tree kind for this column, or "" for none.
func tree_at(x: int, z: int, biome: Biome, h: int, slope: float) -> String:
	if h <= SEA_LEVEL or slope >= 3.0:
		return ""
	if float(h) > biome.snow_line + 8.0:
		return ""
	# Forest noise clumps trees into stands with real clearings between them.
	var clump := _forest.get_noise_2d(float(x), float(z)) * 0.5 + 0.5
	var density: float = biome.tree_density * (0.25 + clump * 1.9)
	if hash01(x, z, 11) > density:
		return ""
	var kinds: Array = biome.tree_kinds
	if kinds.is_empty():
		return ""
	var idx := int(hash01(x, z, 12) * float(kinds.size())) % kinds.size()
	return kinds[idx]


func rock_at(x: int, z: int, biome: Biome, h: int) -> bool:
	if h <= SEA_LEVEL:
		return false
	return hash01(x, z, 21) < biome.rock_density


func bush_at(x: int, z: int, biome: Biome, h: int, slope: float) -> bool:
	if h <= SEA_LEVEL or slope >= 3.0:
		return false
	var clump := _forest.get_noise_2d(float(x) * 1.7, float(z) * 1.7) * 0.5 + 0.5
	return hash01(x, z, 31) < biome.bush_density * (0.4 + clump)


func flower_at(x: int, z: int, biome: Biome, h: int, slope: float) -> int:
	if biome.flower_colors.is_empty() or h <= SEA_LEVEL or slope >= 2.0:
		return -1
	if hash01(x, z, 41) > biome.flower_density:
		return -1
	return int(hash01(x, z, 42) * float(biome.flower_colors.size())) % biome.flower_colors.size()


## Finds a flat, dry spot near the requested position - used for spawn points,
## camps and village plazas.
func find_flat_ground(around: Vector2, radius: float, tries: int = 90) -> Vector3:
	var best := Vector3(around.x, float(SEA_LEVEL) + 4.0, around.y)
	var best_score := -1.0
	for i in tries:
		var a := TAU * hash01(int(around.x) + i, int(around.y), 55)
		var r := radius * sqrt(hash01(int(around.x), int(around.y) + i, 56))
		var px := int(around.x + cos(a) * r)
		var pz := int(around.y + sin(a) * r)
		var h := height_i(px, pz)
		if h <= SEA_LEVEL + 1:
			continue
		var slope := slope_at(px, pz, h)
		var score := 10.0 - slope * 3.0 - absf(float(h) - float(SEA_LEVEL) - 8.0) * 0.05
		if score > best_score:
			best_score = score
			best = Vector3(float(px) + 0.5, float(h) + 1.0, float(pz) + 0.5)
	return best
