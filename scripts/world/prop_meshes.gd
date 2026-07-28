class_name PropMeshes
extends RefCounted
## Cache of instanced prop meshes. A forest is millions of voxels, so trees are
## built once per (biome, kind, variant) and drawn with MultiMesh rather than
## merged into the chunk mesh.

const VARIANTS := 3

## Voxel models are authored around column (0, y, 0). Shifting by half a block
## puts that column's centre on the instance origin, so a trunk stands where
## the game says it stands - and so its collider lines up with it.
const MODEL_ORIGIN := Vector3(0.5, 0.0, 0.5)

static var _mesh_cache: Dictionary = {}
static var _bounds_cache: Dictionary = {}
static var _material: StandardMaterial3D = null
static var _foliage_material: StandardMaterial3D = null


static func material() -> StandardMaterial3D:
	if _material == null:
		_material = VoxelMesher.make_material()
	return _material


static func foliage_material() -> StandardMaterial3D:
	if _foliage_material == null:
		_foliage_material = VoxelMesher.make_foliage_material()
	return _foliage_material


static func key(biome_id: String, kind: String, variant: int) -> String:
	return "%s|%s|%d" % [biome_id, kind, variant]


static func get_mesh(biome_id: String, kind: String, variant: int) -> ArrayMesh:
	var k := key(biome_id, kind, variant)
	if _mesh_cache.has(k):
		return _mesh_cache[k]
	var biome := BiomeLibrary.get_biome(biome_id)
	var voxels := Structures.build_prop_voxels(kind, biome, variant)
	# Centre horizontally, keep the base of the model at y = 0.
	var mesh := VoxelMesher.build_mesh(voxels, MODEL_ORIGIN, true, 1.0)
	_mesh_cache[k] = mesh
	_bounds_cache[k] = Structures.prop_bounds(voxels, kind)
	return mesh


static func get_bounds(biome_id: String, kind: String, variant: int) -> Dictionary:
	var k := key(biome_id, kind, variant)
	if not _bounds_cache.has(k):
		get_mesh(biome_id, kind, variant)
	return _bounds_cache.get(k, {"solid": AABB(), "canopy": AABB(),
		"has_canopy": false, "has_solid": false})


static func is_foliage(kind: String) -> bool:
	return kind in ["broadleaf", "pine", "birch", "willow", "bush", "cactus"]


## A tuft of grass: two crossed quads, coloured per instance.
static func grass_mesh() -> ArrayMesh:
	if _mesh_cache.has("__grass"):
		return _mesh_cache["__grass"]
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var h := 0.55
	var w := 0.30
	for angle: float in [0.0, PI * 0.5]:
		var dir := Vector3(cos(angle), 0.0, sin(angle)) * w
		var n := Vector3(-sin(angle), 0.35, cos(angle)).normalized()
		var quad := [
			-dir, dir, dir + Vector3(0, h, 0), -dir + Vector3(0, h, 0),
		]
		for tri: Array in [[0, 1, 2], [0, 2, 3], [2, 1, 0], [3, 2, 0]]:
			for k: int in tri:
				verts.push_back(quad[k])
				normals.push_back(n)
				# Darker at the root, brighter at the tip.
				var shade: float = 0.65 if k < 2 else 1.0
				colors.push_back(Color(shade, shade, shade, 1.0))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_mesh_cache["__grass"] = mesh
	return mesh


static var _grass_material: StandardMaterial3D = null


static func grass_material() -> StandardMaterial3D:
	if _grass_material == null:
		_grass_material = VoxelMesher.make_material()
		_grass_material.cull_mode = BaseMaterial3D.CULL_DISABLED
		_grass_material.backlight_enabled = true
		_grass_material.backlight = Color(0.22, 0.26, 0.14)
	return _grass_material


## Builds every mesh a world can ask for, on the main thread, before chunk
## workers start. The cache is read from several threads afterwards, so it must
## never be written to again while generation is running.
static func warm_cache() -> void:
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
