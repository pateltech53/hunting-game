class_name Structures
extends RefCounted
## Everything that is stamped on top of the terrain as loose voxels: trees,
## rocks, and the timber villages that make the street / interior / wedding
## photo genres possible.
##
## Every function is deterministic and clips its own writes to the chunk being
## built, so a structure that straddles four chunks still comes out whole.

const VILLAGE_CELL := 352      ## world units between candidate village sites
const VILLAGE_RADIUS := 46.0

# Shared building palette. Biomes tint the roofs.
const WOOD := Color(0.47, 0.33, 0.20)
const WOOD_DARK := Color(0.31, 0.21, 0.13)
const BEAM := Color(0.24, 0.17, 0.11)
const PLASTER := Color(0.80, 0.76, 0.66)
const STONE := Color(0.46, 0.45, 0.44)
const STONE_DARK := Color(0.33, 0.33, 0.33)
const GLASS := Color(0.62, 0.74, 0.80)
const LANTERN := Color(1.0, 0.86, 0.55)
const CLOTH := Color(0.72, 0.30, 0.28)
const CLOTH_WHITE := Color(0.94, 0.93, 0.90)


static func put(out: Dictionary, bmin: Vector2i, bmax: Vector2i, x: int, y: int, z: int,
		color: Color) -> void:
	if x < bmin.x or x >= bmax.x or z < bmin.y or z >= bmax.y:
		return
	if y < 0 or y > TerrainGenerator.MAX_HEIGHT + 40:
		return
	out[Vector3i(x, y, z)] = color


static func fill_box(out: Dictionary, bmin: Vector2i, bmax: Vector2i, from: Vector3i,
		to: Vector3i, color: Color) -> void:
	for x in range(mini(from.x, to.x), maxi(from.x, to.x) + 1):
		for y in range(mini(from.y, to.y), maxi(from.y, to.y) + 1):
			for z in range(mini(from.z, to.z), maxi(from.z, to.z) + 1):
				put(out, bmin, bmax, x, y, z, color)


# ----------------------------------------------------------------------- trees

static func stamp_tree(kind: String, base: Vector3i, biome: Biome, gen: TerrainGenerator,
		out: Dictionary, bmin: Vector2i, bmax: Vector2i) -> void:
	var r := gen.hash01(base.x, base.z, 13)
	var r2 := gen.hash01(base.x, base.z, 14)
	var leaf: Color = biome.foliage[int(r2 * float(biome.foliage.size())) % biome.foliage.size()]
	match kind:
		"pine":
			_pine(base, biome, leaf, r, out, bmin, bmax)
		"birch":
			_birch(base, biome, leaf, r, out, bmin, bmax)
		"willow":
			_willow(base, biome, leaf, r, out, bmin, bmax)
		"dead":
			_dead(base, biome, r, out, bmin, bmax)
		"cactus":
			_cactus(base, r, out, bmin, bmax)
		_:
			_broadleaf(base, biome, leaf, r, out, bmin, bmax)


static func _pine(base: Vector3i, biome: Biome, leaf: Color, r: float, out: Dictionary,
		bmin: Vector2i, bmax: Vector2i) -> void:
	var h := 8 + int(r * 9.0)
	for y in h:
		put(out, bmin, bmax, base.x, base.y + y, base.z, biome.trunk)
	# Conical skirt: radius shrinks toward the tip, with a ragged edge.
	var start := 2 + int(r * 2.0)
	var layers := h - start + 3
	for i in layers:
		var y := base.y + start + i
		var t := float(i) / float(maxi(layers - 1, 1))
		var rad := int(round(lerpf(3.4, 0.0, pow(t, 0.75))))
		if rad <= 0:
			put(out, bmin, bmax, base.x, y, base.z, leaf)
			continue
		for dx in range(-rad, rad + 1):
			for dz in range(-rad, rad + 1):
				var d := absi(dx) + absi(dz)
				if d > rad + 1:
					continue
				if d == rad + 1 and ((dx + dz + i) % 3) != 0:
					continue
				var shade: float = 1.0 - float(d) * 0.03
				put(out, bmin, bmax, base.x + dx, y, base.z + dz, leaf * shade)


static func _broadleaf(base: Vector3i, biome: Biome, leaf: Color, r: float, out: Dictionary,
		bmin: Vector2i, bmax: Vector2i) -> void:
	var trunk_h := 4 + int(r * 4.0)
	for y in trunk_h:
		put(out, bmin, bmax, base.x, base.y + y, base.z, biome.trunk)
	var rad := 3 + int(r * 1.6)
	var cy := base.y + trunk_h + rad - 2
	for dx in range(-rad, rad + 1):
		for dy in range(-rad, rad + 1):
			for dz in range(-rad, rad + 1):
				var d := Vector3(float(dx), float(dy) * 1.25, float(dz)).length()
				if d > float(rad) + 0.4:
					continue
				# Nibble the surface so the canopy is not a perfect ball.
				if d > float(rad) - 0.7 and ((dx * 7 + dy * 13 + dz * 3) % 5) == 0:
					continue
				var shade: float = 1.0 - clampf(d / float(rad), 0.0, 1.0) * 0.16
				put(out, bmin, bmax, base.x + dx, cy + dy, base.z + dz, leaf * shade)
	# A couple of branches reaching into the canopy.
	for y in range(trunk_h, trunk_h + 2):
		put(out, bmin, bmax, base.x, base.y + y, base.z, biome.trunk)


static func _birch(base: Vector3i, biome: Biome, leaf: Color, r: float, out: Dictionary,
		bmin: Vector2i, bmax: Vector2i) -> void:
	var trunk_h := 6 + int(r * 5.0)
	var bark := Color(0.86, 0.86, 0.82)
	for y in trunk_h:
		var c := bark if (y % 4) != 0 else Color(0.30, 0.29, 0.27)
		put(out, bmin, bmax, base.x, base.y + y, base.z, c)
	var rad := 2 + int(r * 1.4)
	var cy := base.y + trunk_h + 1
	for dx in range(-rad, rad + 1):
		for dy in range(-rad, rad + 1):
			for dz in range(-rad, rad + 1):
				var d := Vector3(float(dx), float(dy) * 1.5, float(dz)).length()
				if d > float(rad) + 0.3:
					continue
				put(out, bmin, bmax, base.x + dx, cy + dy, base.z + dz,
					leaf * (1.0 - d * 0.05))


static func _willow(base: Vector3i, biome: Biome, leaf: Color, r: float, out: Dictionary,
		bmin: Vector2i, bmax: Vector2i) -> void:
	var trunk_h := 3 + int(r * 3.0)
	for y in trunk_h:
		put(out, bmin, bmax, base.x, base.y + y, base.z, biome.trunk)
	var rad := 4
	var cy := base.y + trunk_h + 1
	for dx in range(-rad, rad + 1):
		for dz in range(-rad, rad + 1):
			var d := sqrt(float(dx * dx + dz * dz))
			if d > float(rad):
				continue
			put(out, bmin, bmax, base.x + dx, cy, base.z + dz, leaf)
			put(out, bmin, bmax, base.x + dx, cy + 1, base.z + dz, leaf * 1.05)
			# Trailing curtains of leaves at the rim.
			if d > float(rad) - 1.6:
				var drop := 2 + int(gen_hash(dx, dz) * 3.0)
				for k in drop:
					put(out, bmin, bmax, base.x + dx, cy - 1 - k, base.z + dz, leaf * 0.9)


static func _dead(base: Vector3i, biome: Biome, r: float, out: Dictionary,
		bmin: Vector2i, bmax: Vector2i) -> void:
	var h := 5 + int(r * 6.0)
	var bark := biome.trunk.lerp(Color(0.45, 0.42, 0.38), 0.55)
	for y in h:
		put(out, bmin, bmax, base.x, base.y + y, base.z, bark)
	put(out, bmin, bmax, base.x + 1, base.y + h - 2, base.z, bark)
	put(out, bmin, bmax, base.x + 2, base.y + h - 1, base.z, bark)
	put(out, bmin, bmax, base.x - 1, base.y + h - 3, base.z, bark)
	put(out, bmin, bmax, base.x - 1, base.y + h - 3, base.z + 1, bark)


static func _cactus(base: Vector3i, r: float, out: Dictionary, bmin: Vector2i,
		bmax: Vector2i) -> void:
	var green := Color(0.26, 0.42, 0.26)
	var h := 3 + int(r * 4.0)
	for y in h:
		put(out, bmin, bmax, base.x, base.y + y, base.z, green)
	if r > 0.4:
		var arm_y := base.y + h - 2
		put(out, bmin, bmax, base.x + 1, arm_y, base.z, green)
		put(out, bmin, bmax, base.x + 1, arm_y + 1, base.z, green)
		put(out, bmin, bmax, base.x + 1, arm_y + 2, base.z, green)
	if r < 0.6:
		var arm_y2 := base.y + h - 3
		put(out, bmin, bmax, base.x - 1, arm_y2, base.z, green)
		put(out, bmin, bmax, base.x - 1, arm_y2 + 1, base.z, green)


## Builds a standalone prop as voxels around the origin, for the instanced
## prop meshes. Deterministic in [param variant] so a chunk only has to store
## which variant it picked.
static func build_prop_voxels(kind: String, biome: Biome, variant: int) -> Dictionary:
	var out := {}
	var bmin := Vector2i(-64, -64)
	var bmax := Vector2i(64, 64)
	var r := fposmod(0.17 + float(variant) * 0.29, 1.0)
	var leaf: Color = biome.foliage[variant % maxi(biome.foliage.size(), 1)]
	var base := Vector3i.ZERO
	match kind:
		"pine":
			_pine(base, biome, leaf, r, out, bmin, bmax)
		"birch":
			_birch(base, biome, leaf, r, out, bmin, bmax)
		"willow":
			_willow(base, biome, leaf, r, out, bmin, bmax)
		"dead":
			_dead(base, biome, r, out, bmin, bmax)
		"cactus":
			_cactus(base, r, out, bmin, bmax)
		"rock":
			stamp_rock(base, biome, r, out, bmin, bmax)
		"bush":
			stamp_bush(base, biome, r, out, bmin, bmax)
		_:
			_broadleaf(base, biome, leaf, r, out, bmin, bmax)
	return out


## Splits a prop into the part that stops you and bullets (a trunk, a boulder)
## and the part that only veils the view (the canopy).
##
## The trunk is deliberately the single centre column: a tree has to be
## something you can see an animal through, not a three metre pillar of stone.
static func prop_bounds(voxels: Dictionary, kind: String) -> Dictionary:
	var result := {
		"solid": AABB(), "canopy": AABB(), "has_canopy": false, "has_solid": false,
	}
	if voxels.is_empty():
		return result

	# Same half-block shift the mesh uses, so colliders sit on the model.
	var origin := PropMeshes.MODEL_ORIGIN
	var all_min := Vector3(9999, 9999, 9999)
	var all_max := Vector3(-9999, -9999, -9999)
	var trunk_min := Vector3(9999, 9999, 9999)
	var trunk_max := Vector3(-9999, -9999, -9999)
	var has_trunk := false
	for pos: Vector3i in voxels:
		var p := Vector3(pos) - origin
		all_min = all_min.min(p)
		all_max = all_max.max(p + Vector3.ONE)
		if pos.x == 0 and pos.z == 0:
			has_trunk = true
			trunk_min = trunk_min.min(p)
			trunk_max = trunk_max.max(p + Vector3.ONE)

	var whole := AABB(all_min, all_max - all_min)
	match kind:
		"rock":
			# A boulder is solid all the way through and hides nothing extra.
			result["solid"] = whole
			result["has_solid"] = true
		"bush", "cactus":
			# Walk through a bush; it just gets in the way of the picture.
			result["canopy"] = whole
			result["has_canopy"] = true
		_:
			if has_trunk:
				result["solid"] = AABB(trunk_min, trunk_max - trunk_min)
				result["has_solid"] = true
			result["canopy"] = whole
			result["has_canopy"] = true
	return result


static func gen_hash(a: int, b: int) -> float:
	var n: int = a * 92837111 + b * 689287499
	n = (n ^ (n >> 13)) * 1274126177
	return float(absi(n ^ (n >> 16)) % 10000) / 10000.0


static func stamp_rock(base: Vector3i, biome: Biome, r: float, out: Dictionary,
		bmin: Vector2i, bmax: Vector2i) -> void:
	var rad := 1 + int(r * 2.4)
	for dx in range(-rad, rad + 1):
		for dy in range(0, rad + 1):
			for dz in range(-rad, rad + 1):
				var d := Vector3(float(dx), float(dy) * 1.4, float(dz)).length()
				if d > float(rad) + 0.3:
					continue
				if d > float(rad) - 0.5 and ((dx * 5 + dz * 11 + dy) % 4) == 0:
					continue
				var shade: float = 0.86 + gen_hash(base.x + dx, base.z + dz) * 0.24
				put(out, bmin, bmax, base.x + dx, base.y + dy - 1, base.z + dz,
					biome.rock * shade)


static func stamp_bush(base: Vector3i, biome: Biome, r: float, out: Dictionary,
		bmin: Vector2i, bmax: Vector2i) -> void:
	var leaf: Color = biome.foliage[int(r * float(biome.foliage.size())) % biome.foliage.size()]
	leaf = leaf.lerp(biome.grass_a, 0.25)
	var rad := 1 + int(r * 1.5)
	for dx in range(-rad, rad + 1):
		for dz in range(-rad, rad + 1):
			for dy in range(0, rad + 1):
				if absi(dx) + absi(dz) + dy > rad + 1:
					continue
				put(out, bmin, bmax, base.x + dx, base.y + dy, base.z + dz, leaf)


static func stamp_flower(base: Vector3i, color: Color, out: Dictionary, bmin: Vector2i,
		bmax: Vector2i) -> void:
	put(out, bmin, bmax, base.x, base.y, base.z, Color(0.30, 0.44, 0.22))
	put(out, bmin, bmax, base.x, base.y + 1, base.z, color)


# -------------------------------------------------------------------- villages

## Village sites are anchored to a coarse grid so that any chunk can work out,
## on its own, which settlements might reach into it.
static func village_sites_near(gen: TerrainGenerator, world_x: float, world_z: float,
		search_radius: float) -> Array:
	var sites: Array = []
	var cell_min_x := int(floor((world_x - search_radius) / float(VILLAGE_CELL)))
	var cell_max_x := int(floor((world_x + search_radius) / float(VILLAGE_CELL)))
	var cell_min_z := int(floor((world_z - search_radius) / float(VILLAGE_CELL)))
	var cell_max_z := int(floor((world_z + search_radius) / float(VILLAGE_CELL)))
	for cx in range(cell_min_x, cell_max_x + 1):
		for cz in range(cell_min_z, cell_max_z + 1):
			var site := village_site(gen, cx, cz)
			if site.is_empty():
				continue
			var d := Vector2(site["position"].x - world_x, site["position"].z - world_z).length()
			if d <= search_radius + VILLAGE_RADIUS:
				sites.append(site)
	return sites


static func village_site(gen: TerrainGenerator, cell_x: int, cell_z: int) -> Dictionary:
	var jitter_x := gen.hash01(cell_x, cell_z, 71)
	var jitter_z := gen.hash01(cell_x, cell_z, 72)
	var cx := float(cell_x) * float(VILLAGE_CELL) + jitter_x * float(VILLAGE_CELL) * 0.7 \
		+ float(VILLAGE_CELL) * 0.15
	var cz := float(cell_z) * float(VILLAGE_CELL) + jitter_z * float(VILLAGE_CELL) * 0.7 \
		+ float(VILLAGE_CELL) * 0.15
	var h := gen.height_i(int(cx), int(cz))
	if h <= TerrainGenerator.SEA_LEVEL + 1:
		return {}
	var biome_id := gen.biome_from_height(cx, cz, float(h))
	var biome := BiomeLibrary.get_biome(biome_id)
	if gen.hash01(cell_x, cell_z, 73) > biome.village_chance:
		return {}
	if gen.gradient_slope(cx, cz) > 0.45:
		return {}
	var kind := "hamlet"
	var roll := gen.hash01(cell_x, cell_z, 74)
	if roll > 0.82:
		kind = "wedding"
	elif roll > 0.55:
		kind = "market"
	return {
		"position": Vector3(cx, float(h), cz),
		"cell": Vector2i(cell_x, cell_z),
		"biome": biome_id,
		"kind": kind,
		"seed": int(gen.hash01(cell_x, cell_z, 75) * 100000.0),
		"name": village_name(gen, cell_x, cell_z),
	}


const NAME_A := ["Bram", "Cold", "Elder", "Fern", "Grey", "Hollow", "Larch", "Mill",
	"North", "Oat", "Pine", "Quill", "Raven", "Stone", "Thistle", "Wren"]
const NAME_B := ["bridge", "ford", "gate", "hearth", "row", "cross", "field", "watch",
	"stead", "barrow", "landing", "rest"]


static func village_name(gen: TerrainGenerator, cell_x: int, cell_z: int) -> String:
	var a: String = NAME_A[int(gen.hash01(cell_x, cell_z, 81) * float(NAME_A.size())) % NAME_A.size()]
	var b: String = NAME_B[int(gen.hash01(cell_x, cell_z, 82) * float(NAME_B.size())) % NAME_B.size()]
	return a + b


## Lays out one village and writes the part of it that falls inside this chunk.
## [param lights] collects world positions for lanterns so the world can add
## real light nodes; [param markers] collects points of photographic interest.
static func stamp_village(site: Dictionary, gen: TerrainGenerator, out: Dictionary,
		bmin: Vector2i, bmax: Vector2i, lights: Array, markers: Array) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = site["seed"]
	var centre: Vector3 = site["position"]
	var biome := BiomeLibrary.get_biome(site["biome"])
	var roof := _roof_color(biome, rng)
	var cx := int(centre.x)
	var cz := int(centre.z)

	# A packed-earth plaza, and paths running out of it along both axes.
	_stamp_plaza(gen, out, bmin, bmax, cx, cz, 7, biome)
	for dir in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		_stamp_path(gen, out, bmin, bmax, cx, cz, dir, 34, biome)

	_stamp_well(gen, out, bmin, bmax, cx, cz)
	markers.append({"kind": "landmark", "position": Vector3(float(cx), centre.y, float(cz)),
		"label": "%s village square" % site["name"]})

	# Ring of dwellings around the plaza.
	var count := 5 + int(rng.randf() * 4.0)
	for i in count:
		var angle := TAU * float(i) / float(count) + rng.randf_range(-0.2, 0.2)
		var dist := 13.0 + rng.randf_range(0.0, 16.0)
		var bx := cx + int(cos(angle) * dist)
		var bz := cz + int(sin(angle) * dist)
		var w := 5 + int(rng.randf() * 4.0)
		var d := 5 + int(rng.randf() * 3.0)
		var facing := _facing_towards(bx, bz, cx, cz)
		_stamp_cabin(gen, out, bmin, bmax, bx, bz, w, d, facing, roof, rng, lights, markers)

	if site["kind"] == "market":
		for i in 4:
			var angle := TAU * float(i) / 4.0 + 0.4
			var sx := cx + int(cos(angle) * 8.0)
			var sz := cz + int(sin(angle) * 8.0)
			_stamp_stall(gen, out, bmin, bmax, sx, sz, rng)
		markers.append({"kind": "street", "position": Vector3(float(cx), centre.y, float(cz)),
			"label": "%s market" % site["name"]})
	elif site["kind"] == "wedding":
		var wx := cx + 14
		var wz := cz + 14
		_stamp_arch(gen, out, bmin, bmax, wx, wz, rng)
		markers.append({"kind": "wedding", "position": Vector3(float(wx),
			float(gen.height_i(wx, wz)) + 1.0, float(wz)),
			"label": "Wedding at %s" % site["name"]})

	# Lantern posts down the main path.
	for i in range(-3, 4):
		if i == 0:
			continue
		var lx := cx + i * 7
		var lz := cz + 5
		_stamp_lantern(gen, out, bmin, bmax, lx, lz, lights)


static func _roof_color(biome: Biome, rng: RandomNumberGenerator) -> Color:
	var options := [
		Color(0.36, 0.28, 0.26), Color(0.30, 0.32, 0.34),
		Color(0.44, 0.30, 0.22), Color(0.26, 0.30, 0.28),
	]
	var base: Color = options[rng.randi_range(0, options.size() - 1)]
	return base.lerp(biome.rock, 0.15)


static func _facing_towards(x: int, z: int, tx: int, tz: int) -> Vector2i:
	var dx := tx - x
	var dz := tz - z
	if absi(dx) > absi(dz):
		return Vector2i(signi(dx), 0)
	return Vector2i(0, signi(dz))


static func _stamp_plaza(gen: TerrainGenerator, out: Dictionary, bmin: Vector2i,
		bmax: Vector2i, cx: int, cz: int, radius: int, biome: Biome) -> void:
	var floor_y := gen.height_i(cx, cz)
	for dx in range(-radius, radius + 1):
		for dz in range(-radius, radius + 1):
			if dx * dx + dz * dz > radius * radius:
				continue
			var x := cx + dx
			var z := cz + dz
			var ground := gen.height_i(x, z)
			var shade: float = 0.9 + gen_hash(x, z) * 0.2
			var col := STONE_DARK.lerp(biome.dirt, 0.35) * shade
			# Level the square by decking over whatever the ground does.
			for y in range(mini(ground, floor_y), floor_y + 1):
				put(out, bmin, bmax, x, y, z, col)


static func _stamp_path(gen: TerrainGenerator, out: Dictionary, bmin: Vector2i,
		bmax: Vector2i, cx: int, cz: int, dir: Vector2i, length: int, biome: Biome) -> void:
	for i in range(6, length):
		var x := cx + dir.x * i
		var z := cz + dir.y * i
		var wobble := int(round(sin(float(i) * 0.28) * 1.4))
		if dir.x != 0:
			z += wobble
		else:
			x += wobble
		for w in range(-1, 2):
			var px := x + (0 if dir.x != 0 else w)
			var pz := z + (w if dir.x != 0 else 0)
			var ground := gen.height_i(px, pz)
			if ground <= TerrainGenerator.SEA_LEVEL:
				continue
			var col := biome.dirt.lerp(STONE_DARK, 0.3) * (0.9 + gen_hash(px, pz) * 0.2)
			put(out, bmin, bmax, px, ground, pz, col)


static func _stamp_well(gen: TerrainGenerator, out: Dictionary, bmin: Vector2i,
		bmax: Vector2i, cx: int, cz: int) -> void:
	var y := gen.height_i(cx, cz) + 1
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			if dx == 0 and dz == 0:
				put(out, bmin, bmax, cx, y, cz, Color(0.10, 0.16, 0.20))
				continue
			put(out, bmin, bmax, cx + dx, y, cz + dz, STONE)
			put(out, bmin, bmax, cx + dx, y + 1, cz + dz, STONE)
	for k in range(2, 5):
		put(out, bmin, bmax, cx - 1, y + k, cz, WOOD_DARK)
		put(out, bmin, bmax, cx + 1, y + k, cz, WOOD_DARK)
	for dx in range(-1, 2):
		put(out, bmin, bmax, cx + dx, y + 5, cz, WOOD)


## A cabin with a real interior: floor, door opening, windows, hearth and
## furniture, so an interiors assignment has something to photograph.
static func _stamp_cabin(gen: TerrainGenerator, out: Dictionary, bmin: Vector2i,
		bmax: Vector2i, cx: int, cz: int, w: int, d: int, facing: Vector2i,
		roof: Color, rng: RandomNumberGenerator, lights: Array, markers: Array) -> void:
	var hw := w / 2
	var hd := d / 2
	# Floor height is the highest ground under the footprint, so nothing floats.
	var floor_y := gen.height_i(cx, cz)
	for dx in range(-hw, hw + 1):
		for dz in range(-hd, hd + 1):
			floor_y = maxi(floor_y, gen.height_i(cx + dx, cz + dz))
	floor_y += 1

	var wall_h := 4
	var wall_col := WOOD if rng.randf() < 0.65 else PLASTER
	var door_x := cx + facing.x * hw
	var door_z := cz + facing.y * hd

	for dx in range(-hw, hw + 1):
		for dz in range(-hd, hd + 1):
			var x := cx + dx
			var z := cz + dz
			# Stone plinth down to the ground. The surface is continuous now, so
			# reach a little deeper than the rounded height to avoid daylight
			# under the footings on sloping ground.
			var ground := gen.height_i(x, z)
			for y in range(ground - 3, floor_y):
				put(out, bmin, bmax, x, y, z, STONE_DARK)
			put(out, bmin, bmax, x, floor_y - 1, z, WOOD_DARK)
			var edge: bool = absi(dx) == hw or absi(dz) == hd
			if not edge:
				continue
			for y in range(floor_y, floor_y + wall_h):
				var is_door: bool = x == door_x and z == door_z and y < floor_y + 3
				if is_door:
					continue
				var corner: bool = absi(dx) == hw and absi(dz) == hd
				var window: bool = (y == floor_y + 2) and not corner \
					and ((dx + dz) % 3 == 0) and not (x == door_x and z == door_z)
				if window:
					put(out, bmin, bmax, x, y, z, GLASS)
				else:
					put(out, bmin, bmax, x, y, z, BEAM if corner else wall_col)

	# Gabled roof running along the longer axis.
	var along_x: bool = w >= d
	var span: int = hd if along_x else hw
	for k in range(0, span + 2):
		var y := floor_y + wall_h + k
		var inset := k
		for dx in range(-hw - 1, hw + 2):
			for dz in range(-hd - 1, hd + 2):
				var keep: bool
				if along_x:
					keep = absi(dz) == span + 1 - inset
				else:
					keep = absi(dx) == span + 1 - inset
				if not keep:
					continue
				if along_x and absi(dz) > hd + 1:
					continue
				if not along_x and absi(dx) > hw + 1:
					continue
				put(out, bmin, bmax, cx + dx, y, cz + dz,
					roof * (0.92 + gen_hash(cx + dx, cz + dz) * 0.16))
		if (along_x and span + 1 - inset <= 0) or (not along_x and span + 1 - inset <= 0):
			break

	# Interior fittings.
	var ix := cx - hw + 1
	var iz := cz - hd + 1
	fill_box(out, bmin, bmax, Vector3i(ix, floor_y, iz), Vector3i(ix + 1, floor_y, iz + 1),
		Color(0.55, 0.40, 0.28))                                    # bed
	put(out, bmin, bmax, ix, floor_y + 1, iz, CLOTH_WHITE)
	var tx := cx + hw - 2
	var tz := cz + hd - 2
	put(out, bmin, bmax, tx, floor_y, tz, WOOD_DARK)
	put(out, bmin, bmax, tx, floor_y + 1, tz, WOOD)                 # table
	put(out, bmin, bmax, tx + 1, floor_y + 1, tz, LANTERN)          # candle
	lights.append({"position": Vector3(float(tx) + 1.5, float(floor_y) + 1.8, float(tz) + 0.5),
		"color": Color(1.0, 0.80, 0.50), "energy": 1.6, "range": 8.0, "interior": true})
	# Hearth against the back wall.
	var back_x := cx - facing.x * hw
	var back_z := cz - facing.y * hd
	put(out, bmin, bmax, back_x - facing.x, floor_y, back_z - facing.y, STONE)
	put(out, bmin, bmax, back_x - facing.x, floor_y + 1, back_z - facing.y,
		Color(0.90, 0.42, 0.16))
	lights.append({"position": Vector3(float(back_x - facing.x) + 0.5, float(floor_y) + 1.5,
		float(back_z - facing.y) + 0.5), "color": Color(1.0, 0.55, 0.22), "energy": 2.4,
		"range": 10.0, "interior": true})
	markers.append({"kind": "interior", "position": Vector3(float(cx) + 0.5,
		float(floor_y) + 1.0, float(cz) + 0.5), "label": "cabin interior"})


static func _stamp_stall(gen: TerrainGenerator, out: Dictionary, bmin: Vector2i,
		bmax: Vector2i, cx: int, cz: int, rng: RandomNumberGenerator) -> void:
	var y := gen.height_i(cx, cz) + 1
	var cloth := CLOTH if rng.randf() < 0.5 else Color(0.28, 0.44, 0.62)
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			put(out, bmin, bmax, cx + dx, y, cz + dz, WOOD)
			put(out, bmin, bmax, cx + dx, y + 3, cz + dz, cloth)
	for corner: Vector2i in [Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(1, 1)]:
		for k in range(1, 3):
			put(out, bmin, bmax, cx + corner.x, y + k, cz + corner.y, WOOD_DARK)
	# Produce on the counter.
	put(out, bmin, bmax, cx, y + 1, cz, Color(0.82, 0.44, 0.18))
	put(out, bmin, bmax, cx + 1, y + 1, cz - 1, Color(0.70, 0.24, 0.24))


static func _stamp_arch(gen: TerrainGenerator, out: Dictionary, bmin: Vector2i,
		bmax: Vector2i, cx: int, cz: int, rng: RandomNumberGenerator) -> void:
	var y := gen.height_i(cx, cz) + 1
	for k in range(0, 5):
		put(out, bmin, bmax, cx - 2, y + k, cz, WOOD)
		put(out, bmin, bmax, cx + 2, y + k, cz, WOOD)
	for dx in range(-2, 3):
		put(out, bmin, bmax, cx + dx, y + 5, cz, WOOD)
		put(out, bmin, bmax, cx + dx, y + 6, cz, CLOTH_WHITE)
	for dx in range(-2, 3):
		put(out, bmin, bmax, cx + dx, y + 4, cz, Color(0.86, 0.72, 0.80))
	# Aisle and seating.
	for i in range(1, 9):
		put(out, bmin, bmax, cx, y - 1 + 1, cz + i, CLOTH_WHITE)
	for row in range(2, 8, 2):
		for side: int in [-2, 2]:
			put(out, bmin, bmax, cx + side, y, cz + row, WOOD_DARK)
			put(out, bmin, bmax, cx + side, y + 1, cz + row, WOOD)


static func _stamp_lantern(gen: TerrainGenerator, out: Dictionary, bmin: Vector2i,
		bmax: Vector2i, cx: int, cz: int, lights: Array) -> void:
	var ground := gen.height_i(cx, cz)
	if ground <= TerrainGenerator.SEA_LEVEL:
		return
	var y := ground + 1
	for k in range(0, 4):
		put(out, bmin, bmax, cx, y + k, cz, WOOD_DARK)
	put(out, bmin, bmax, cx, y + 4, cz, LANTERN)
	lights.append({"position": Vector3(float(cx) + 0.5, float(y) + 4.5, float(cz) + 0.5),
		"color": Color(1.0, 0.78, 0.42), "energy": 3.2, "range": 16.0, "interior": false})
