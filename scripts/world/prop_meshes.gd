class_name PropMeshes
extends RefCounted
## Cache of instanced prop meshes. A forest is far too many triangles to merge
## into chunk geometry, so trees are built once per (biome, kind, variant) and
## drawn with MultiMesh.

const VARIANTS := 4

## Voxel models (buildings, animals) are authored around column (0, y, 0).
## Shifting by half a block puts that column's centre on the instance origin.
const MODEL_ORIGIN := Vector3(0.5, 0.0, 0.5)

static var _mesh_cache: Dictionary = {}
static var _bounds_cache: Dictionary = {}
static var _grass_mesh: ArrayMesh = null


static func material() -> StandardMaterial3D:
	return WorldMaterials.terrain()


static func foliage_material() -> ShaderMaterial:
	return WorldMaterials.foliage()


static func grass_material() -> ShaderMaterial:
	return WorldMaterials.grass()


static func key(biome_id: String, kind: String, variant: int) -> String:
	return "%s|%s|%d" % [biome_id, kind, variant]


static func get_mesh(biome_id: String, kind: String, variant: int) -> ArrayMesh:
	var k := key(biome_id, kind, variant)
	if _mesh_cache.has(k):
		return _mesh_cache[k]
	var built := FloraFactory.build(kind, BiomeLibrary.get_biome(biome_id), variant)
	_mesh_cache[k] = built["mesh"]
	_bounds_cache[k] = built
	return built["mesh"]


static func get_bounds(biome_id: String, kind: String, variant: int) -> Dictionary:
	var k := key(biome_id, kind, variant)
	if not _bounds_cache.has(k):
		get_mesh(biome_id, kind, variant)
	return _bounds_cache.get(k, {"solid": AABB(), "canopy": AABB(),
		"has_canopy": false, "has_solid": false})


## Whether this prop should be drawn with the swaying vegetation shader.
static func is_foliage(kind: String) -> bool:
	return kind in ["broadleaf", "pine", "birch", "willow", "bush", "cactus", "dead"]


## A tuft of grass: a few tapered blades leaning in different directions, so it
## reads as grass rather than a pair of crossed cards.
static func grass_mesh() -> ArrayMesh:
	if _grass_mesh != null:
		return _grass_mesh
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var rng := RandomNumberGenerator.new()
	rng.seed = 7781

	for blade in 4:
		var angle := TAU * float(blade) / 4.0 + rng.randf_range(-0.4, 0.4)
		var lean := rng.randf_range(0.12, 0.34)
		var height := rng.randf_range(0.34, 0.62)
		var width := rng.randf_range(0.045, 0.075)
		var dir := Vector3(cos(angle), 0.0, sin(angle))
		var side := Vector3(-dir.z, 0.0, dir.x)
		var tip := dir * lean + Vector3(0.0, height, 0.0)
		var mid := dir * lean * 0.35 + Vector3(0.0, height * 0.55, 0.0)
		var normal := side.cross(tip.normalized()).normalized()
		if normal.length_squared() < 0.001:
			normal = Vector3.UP

		# Two segments, tapering to a point.
		var quads := [
			[-side * width, side * width, mid + side * width * 0.6,
				mid - side * width * 0.6, 0.55, 0.8],
			[mid - side * width * 0.6, mid + side * width * 0.6, tip, tip, 0.8, 1.0],
		]
		for q: Array in quads:
			var shade_lo: float = q[4]
			var shade_hi: float = q[5]
			var a: Vector3 = q[0]
			var b: Vector3 = q[1]
			var c: Vector3 = q[2]
			var d: Vector3 = q[3]
			for tri: Array in [[a, b, c, shade_lo, shade_lo, shade_hi],
					[a, c, d, shade_lo, shade_hi, shade_hi]]:
				for k in 3:
					verts.push_back(tri[k])
					normals.push_back(normal)
					var s: float = tri[3 + k]
					colors.push_back(Color(s, s, s, 1.0))
	var mesh := ArrayMesh.new()
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_grass_mesh = mesh
	return mesh


## Builds every mesh a world can ask for, on the main thread, before the chunk
## workers start. The cache is read from several threads afterwards, so it must
## never be written to again while generation is running.
static func warm_cache() -> void:
	WorldMaterials.ensure_globals()
	grass_mesh()
	grass_material()
	material()
	foliage_material()
	for biome: Biome in BiomeLibrary.all():
		var kinds: Array = biome.tree_kinds.duplicate()
		kinds.append("rock")
		kinds.append("bush")
		for kind: String in kinds:
			for v in VARIANTS:
				get_mesh(biome.id, kind, v)


static func clear_cache() -> void:
	_mesh_cache.clear()
	_bounds_cache.clear()
	_grass_mesh = null
