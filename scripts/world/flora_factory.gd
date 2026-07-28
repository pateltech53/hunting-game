class_name FloraFactory
extends RefCounted
## Builds the trees, bushes and boulders.
##
## These are grown from tapered limbs and irregular blobs rather than stacks of
## cubes, so a forest reads as a forest. Each is still a single low-poly mesh
## drawn through MultiMesh, so the cost per tree is one instance transform.
##
## Returns both the mesh and the two collision volumes the world needs: the
## trunk, which stops you and bullets, and the crown, which only blocks sight.

const TRUNK_SIDES := 6
const BRANCH_SIDES := 4


static func build(kind: String, biome: Biome, variant: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(kind) * 7919 + hash(biome.id) * 104729 + variant * 31
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()

	var trunk_radius := 0.0
	var trunk_height := 0.0
	match kind:
		"pine":
			var r := _pine(verts, normals, colors, biome, rng)
			trunk_radius = r.x
			trunk_height = r.y
		"birch":
			var r2 := _birch(verts, normals, colors, biome, rng)
			trunk_radius = r2.x
			trunk_height = r2.y
		"willow":
			var r3 := _willow(verts, normals, colors, biome, rng)
			trunk_radius = r3.x
			trunk_height = r3.y
		"dead":
			var r4 := _dead(verts, normals, colors, biome, rng)
			trunk_radius = r4.x
			trunk_height = r4.y
		"cactus":
			var r5 := _cactus(verts, normals, colors, rng)
			trunk_radius = r5.x
			trunk_height = r5.y
		"rock":
			_rock(verts, normals, colors, biome, rng)
		"bush":
			_bush(verts, normals, colors, biome, rng)
		_:
			var r6 := _broadleaf(verts, normals, colors, biome, rng)
			trunk_radius = r6.x
			trunk_height = r6.y

	var mesh := MeshShapes.finish(verts, normals, colors)
	return _bounds(mesh, verts, kind, trunk_radius, trunk_height)


## Works out the collision volumes from the geometry that was actually built.
static func _bounds(mesh: ArrayMesh, verts: PackedVector3Array, kind: String,
		trunk_radius: float, trunk_height: float) -> Dictionary:
	var result := {
		"mesh": mesh, "solid": AABB(), "canopy": AABB(),
		"has_solid": false, "has_canopy": false,
	}
	if verts.is_empty():
		return result
	var lo := verts[0]
	var hi := verts[0]
	for v: Vector3 in verts:
		lo = lo.min(v)
		hi = hi.max(v)
	var whole := AABB(lo, hi - lo)

	match kind:
		"rock":
			result["solid"] = whole
			result["has_solid"] = true
		"bush", "cactus":
			result["canopy"] = whole
			result["has_canopy"] = true
		_:
			# Only the trunk stops anything. Keeping it honest to the drawn
			# radius is what lets you see an animal through a stand of trees.
			var r: float = maxf(trunk_radius, 0.12)
			result["solid"] = AABB(Vector3(-r, 0.0, -r),
				Vector3(r * 2.0, maxf(trunk_height, 1.0), r * 2.0))
			result["has_solid"] = true
			result["canopy"] = whole
			result["has_canopy"] = true
	return result


static func _leaf(biome: Biome, rng: RandomNumberGenerator) -> Color:
	if biome.foliage.is_empty():
		return Color(0.22, 0.40, 0.18)
	return biome.foliage[rng.randi_range(0, biome.foliage.size() - 1)]


# ------------------------------------------------------------------ the trees

## Returns (trunk radius, trunk height).
static func _broadleaf(verts: PackedVector3Array, normals: PackedVector3Array,
		colors: PackedColorArray, biome: Biome, rng: RandomNumberGenerator) -> Vector2:
	var height := rng.randf_range(4.2, 6.4)
	var radius := rng.randf_range(0.16, 0.26)
	var lean := Vector3(rng.randf_range(-0.25, 0.25), 0.0, rng.randf_range(-0.25, 0.25))
	var top := Vector3(0, height, 0) + lean

	# Trunk in two segments so it can bend a little.
	var mid := Vector3(0, height * 0.55, 0) + lean * 0.35
	MeshShapes.add_limb(verts, normals, colors, Vector3.ZERO, mid, radius,
		radius * 0.78, TRUNK_SIDES, biome.trunk)
	MeshShapes.add_limb(verts, normals, colors, mid, top, radius * 0.78,
		radius * 0.45, TRUNK_SIDES, biome.trunk)

	var leaf := _leaf(biome, rng)
	var branches := rng.randi_range(3, 5)
	for i in branches:
		var a := TAU * float(i) / float(branches) + rng.randf_range(-0.4, 0.4)
		var out_r := rng.randf_range(1.0, 1.8)
		var from := Vector3(0, height * rng.randf_range(0.55, 0.78), 0) + lean * 0.4
		var to := from + Vector3(cos(a) * out_r, rng.randf_range(0.8, 1.5), sin(a) * out_r)
		MeshShapes.add_limb(verts, normals, colors, from, to, radius * 0.42,
			radius * 0.18, BRANCH_SIDES, biome.trunk.lightened(0.05))
		# A clump of leaves at the end of each branch.
		MeshShapes.add_blob(verts, normals, colors, to + Vector3(0, 0.35, 0),
			rng.randf_range(1.1, 1.7), leaf, rng, Vector3(1.0, 0.82, 1.0), 0.26, 1)
	# Crown over the middle.
	MeshShapes.add_blob(verts, normals, colors, top + Vector3(0, 0.5, 0),
		rng.randf_range(1.5, 2.1), leaf.lightened(0.05), rng, Vector3(1.0, 0.78, 1.0), 0.24, 1)
	return Vector2(radius, height)


static func _birch(verts: PackedVector3Array, normals: PackedVector3Array,
		colors: PackedColorArray, biome: Biome, rng: RandomNumberGenerator) -> Vector2:
	var height := rng.randf_range(6.0, 8.5)
	var radius := rng.randf_range(0.10, 0.15)
	var bark := Color(0.86, 0.85, 0.80)
	var lean := Vector3(rng.randf_range(-0.4, 0.4), 0.0, rng.randf_range(-0.4, 0.4))
	var top := Vector3(0, height, 0) + lean
	# Banded trunk, built as a stack so the dark rings show.
	var segments := 5
	for i in segments:
		var t0 := float(i) / float(segments)
		var t1 := float(i + 1) / float(segments)
		var c: Color = bark if i % 2 == 0 else bark.darkened(0.45)
		MeshShapes.add_limb(verts, normals, colors,
			lean * t0 + Vector3(0, height * t0, 0),
			lean * t1 + Vector3(0, height * t1, 0),
			lerpf(radius, radius * 0.4, t0), lerpf(radius, radius * 0.4, t1),
			TRUNK_SIDES, c, 0.06)
	var leaf := _leaf(biome, rng).lightened(0.08)
	for i in 3:
		var a := TAU * float(i) / 3.0 + rng.randf_range(-0.3, 0.3)
		var centre := top + Vector3(cos(a) * rng.randf_range(0.4, 1.0),
			rng.randf_range(-0.6, 0.6), sin(a) * rng.randf_range(0.4, 1.0))
		MeshShapes.add_blob(verts, normals, colors, centre, rng.randf_range(1.0, 1.5),
			leaf, rng, Vector3(1.0, 0.9, 1.0), 0.30, 1)
	return Vector2(radius, height)


static func _pine(verts: PackedVector3Array, normals: PackedVector3Array,
		colors: PackedColorArray, biome: Biome, rng: RandomNumberGenerator) -> Vector2:
	var height := rng.randf_range(8.0, 13.0)
	var radius := rng.randf_range(0.16, 0.24)
	MeshShapes.add_limb(verts, normals, colors, Vector3.ZERO, Vector3(0, height, 0),
		radius, radius * 0.3, TRUNK_SIDES, biome.trunk)
	var leaf := _leaf(biome, rng)
	# Stacked skirts, widest low down, shrinking to the leader.
	var skirts := rng.randi_range(5, 7)
	var start := height * 0.22
	for i in skirts:
		var t := float(i) / float(skirts - 1)
		var y: float = lerpf(start, height * 0.94, t)
		var r: float = lerpf(rng.randf_range(1.9, 2.5), 0.35, pow(t, 0.85))
		var shade: float = 0.88 + 0.24 * float(i % 2)
		MeshShapes.add_cone(verts, normals, colors, Vector3(0, y, 0),
			(height - y) * 0.38 + 0.6, r, 8,
			Color(leaf.r * shade, leaf.g * shade, leaf.b * shade), 0.8)
	return Vector2(radius, height)


static func _willow(verts: PackedVector3Array, normals: PackedVector3Array,
		colors: PackedColorArray, biome: Biome, rng: RandomNumberGenerator) -> Vector2:
	var height := rng.randf_range(3.4, 4.6)
	var radius := rng.randf_range(0.24, 0.34)
	MeshShapes.add_limb(verts, normals, colors, Vector3.ZERO, Vector3(0, height, 0),
		radius, radius * 0.6, TRUNK_SIDES, biome.trunk)
	var leaf := _leaf(biome, rng)
	# Wide, flattened crown.
	for i in 4:
		var a := TAU * float(i) / 4.0
		var centre := Vector3(cos(a) * rng.randf_range(0.8, 1.6), height + 0.3,
			sin(a) * rng.randf_range(0.8, 1.6))
		MeshShapes.add_blob(verts, normals, colors, centre, rng.randf_range(1.6, 2.2),
			leaf, rng, Vector3(1.0, 0.5, 1.0), 0.22, 1)
		# Trailing fronds.
		var drop := rng.randf_range(1.4, 2.6)
		MeshShapes.add_limb(verts, normals, colors, centre,
			centre + Vector3(cos(a) * 0.4, -drop, sin(a) * 0.4), 0.30, 0.06, 4,
			leaf.darkened(0.12))
	return Vector2(radius, height)


static func _dead(verts: PackedVector3Array, normals: PackedVector3Array,
		colors: PackedColorArray, biome: Biome, rng: RandomNumberGenerator) -> Vector2:
	var height := rng.randf_range(4.0, 7.0)
	var radius := rng.randf_range(0.14, 0.22)
	var bark := biome.trunk.lerp(Color(0.52, 0.48, 0.43), 0.55)
	MeshShapes.add_limb(verts, normals, colors, Vector3.ZERO, Vector3(0, height, 0),
		radius, radius * 0.25, TRUNK_SIDES, bark)
	for i in rng.randi_range(2, 4):
		var a := rng.randf_range(0.0, TAU)
		var from := Vector3(0, height * rng.randf_range(0.45, 0.85), 0)
		var to := from + Vector3(cos(a) * rng.randf_range(0.9, 1.8),
			rng.randf_range(0.3, 1.1), sin(a) * rng.randf_range(0.9, 1.8))
		MeshShapes.add_limb(verts, normals, colors, from, to, radius * 0.35, 0.03,
			BRANCH_SIDES, bark)
	return Vector2(radius, height)


static func _cactus(verts: PackedVector3Array, normals: PackedVector3Array,
		colors: PackedColorArray, rng: RandomNumberGenerator) -> Vector2:
	var green := Color(0.24, 0.40, 0.24)
	var height := rng.randf_range(2.0, 3.6)
	var radius := rng.randf_range(0.22, 0.32)
	MeshShapes.add_limb(verts, normals, colors, Vector3.ZERO, Vector3(0, height, 0),
		radius, radius * 0.85, 7, green, 0.18)
	for side: int in [-1, 1]:
		if rng.randf() > 0.65:
			continue
		var y := height * rng.randf_range(0.35, 0.6)
		var elbow := Vector3(float(side) * rng.randf_range(0.5, 0.8), y, 0)
		MeshShapes.add_limb(verts, normals, colors, Vector3(0, y, 0), elbow,
			radius * 0.6, radius * 0.55, 6, green, 0.18)
		MeshShapes.add_limb(verts, normals, colors, elbow,
			elbow + Vector3(0, rng.randf_range(0.7, 1.3), 0), radius * 0.55,
			radius * 0.5, 6, green, 0.18)
	return Vector2(radius, height)


static func _rock(verts: PackedVector3Array, normals: PackedVector3Array,
		colors: PackedColorArray, biome: Biome, rng: RandomNumberGenerator) -> void:
	var lumps := rng.randi_range(1, 3)
	for i in lumps:
		var offset := Vector3(rng.randf_range(-0.35, 0.35), 0.0, rng.randf_range(-0.35, 0.35))
		var r := rng.randf_range(0.26, 0.62) / float(1 + i)
		var shade := 0.85 + rng.randf() * 0.3
		MeshShapes.add_blob(verts, normals, colors, offset + Vector3(0, r * 0.55, 0), r,
			Color(biome.rock.r * shade, biome.rock.g * shade, biome.rock.b * shade),
			rng, Vector3(1.0, 0.7, 1.0), 0.38, 1)


static func _bush(verts: PackedVector3Array, normals: PackedVector3Array,
		colors: PackedColorArray, biome: Biome, rng: RandomNumberGenerator) -> void:
	var leaf := _leaf(biome, rng).lerp(biome.grass_a, 0.25)
	for i in rng.randi_range(2, 3):
		var offset := Vector3(rng.randf_range(-0.4, 0.4), 0.0, rng.randf_range(-0.4, 0.4))
		var r := rng.randf_range(0.45, 0.8)
		MeshShapes.add_blob(verts, normals, colors, offset + Vector3(0, r * 0.75, 0), r,
			leaf, rng, Vector3(1.0, 0.8, 1.0), 0.34, 1)
