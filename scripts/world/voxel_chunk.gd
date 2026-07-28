class_name VoxelChunk
extends Node3D
## One 32x32 column of world. Owns its terrain mesh, water surface, prop
## multimeshes, grass and collision.

var coord: Vector2i
var heights := PackedInt32Array()
var biome_index := PackedByteArray()
var dominant_biome := ""
var has_water := false
var markers: Array = []
var village_sites: Array = []
var has_collision := false

var _terrain: MeshInstance3D
var _water: MeshInstance3D
var _structure: MeshInstance3D
var _body: StaticBody3D
var _foliage_body: StaticBody3D
var _lights: Array[OmniLight3D] = []


func apply(data: Dictionary, want_lights: bool) -> void:
	coord = data["coord"]
	heights = data["heights"]
	biome_index = data["biome_index"]
	dominant_biome = data["dominant_biome"]
	has_water = data["has_water"]
	markers = data["markers"]
	village_sites = data["village_sites"]
	position = Vector3(float(coord.x * ChunkBuilder.SIZE), 0.0,
		float(coord.y * ChunkBuilder.SIZE))

	var local := Vector3(-position.x, 0.0, -position.z)

	var terrain_arrays: Array = data["terrain"]
	if not terrain_arrays.is_empty():
		_terrain = _make_mesh_instance(terrain_arrays, PropMeshes.material(), local)
		_terrain.name = "Terrain"
		add_child(_terrain)

	var structure_arrays: Array = data["structure"]
	if not structure_arrays.is_empty():
		_structure = _make_mesh_instance(structure_arrays, PropMeshes.material(), local)
		_structure.name = "Structures"
		add_child(_structure)

	var water_arrays: Array = data["water"]
	if not water_arrays.is_empty():
		var biome := BiomeLibrary.get_biome(dominant_biome)
		_water = _make_mesh_instance(water_arrays,
			VoxelMesher.make_water_material(biome.water_color), local)
		_water.name = "Water"
		_water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_water)

	_build_props(data["props"], local)
	_build_grass(data["grass"], local)
	_build_collision(data["collision"], data["foliage_collision"], local)
	if want_lights:
		_build_lights(data["lights"], local)


func _make_mesh_instance(arrays: Array, material: Material, offset: Vector3) -> MeshInstance3D:
	# Arrays arrive in world space; shift them into chunk-local space so the
	# node transform stays meaningful and floating point stays well behaved.
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var shifted := PackedVector3Array()
	shifted.resize(verts.size())
	for i in verts.size():
		shifted[i] = verts[i] + offset
	var local_arrays := arrays.duplicate()
	local_arrays[Mesh.ARRAY_VERTEX] = shifted
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, local_arrays)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = material
	return mi


func _build_props(props: Array, offset: Vector3) -> void:
	if props.is_empty():
		return
	# Group by mesh so each distinct tree becomes a single MultiMesh draw.
	var groups := {}
	for prop: Dictionary in props:
		var key := PropMeshes.key(prop["biome"], prop["kind"], prop["variant"])
		if not groups.has(key):
			groups[key] = []
		groups[key].append(prop)
	for key: String in groups:
		var list: Array = groups[key]
		var first: Dictionary = list[0]
		var mesh := PropMeshes.get_mesh(first["biome"], first["kind"], first["variant"])
		if mesh == null:
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mesh
		mm.instance_count = list.size()
		for i in list.size():
			var prop: Dictionary = list[i]
			var basis := Basis(Vector3.UP, prop["yaw"]).scaled(Vector3.ONE * float(prop["scale"]))
			mm.set_instance_transform(i, Transform3D(basis, prop["pos"] + offset))
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = PropMeshes.foliage_material() \
			if PropMeshes.is_foliage(first["kind"]) else PropMeshes.material()
		mmi.name = "Props_%s" % key.replace("|", "_")
		add_child(mmi)


func _build_grass(grass: Array, offset: Vector3) -> void:
	if grass.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = PropMeshes.grass_mesh()
	mm.instance_count = grass.size()
	for i in grass.size():
		var g: Dictionary = grass[i]
		var basis := Basis(Vector3.UP, g["yaw"]).scaled(
			Vector3(1.0, float(g["scale"]), 1.0))
		mm.set_instance_transform(i, Transform3D(basis, g["pos"] + offset))
		mm.set_instance_color(i, g["color"])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = PropMeshes.grass_material()
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.name = "Grass"
	add_child(mmi)


func _build_collision(faces: PackedVector3Array, foliage: PackedVector3Array,
		offset: Vector3) -> void:
	if faces.is_empty() and foliage.is_empty():
		return
	has_collision = true
	if not faces.is_empty():
		_body = _make_body(faces, offset, 1, "TerrainBody")
	if not foliage.is_empty():
		_foliage_body = _make_body(foliage, offset, 4, "FoliageBody")


func _make_body(faces: PackedVector3Array, offset: Vector3, layer: int,
		node_name: String) -> StaticBody3D:
	var shifted := PackedVector3Array()
	shifted.resize(faces.size())
	for i in faces.size():
		shifted[i] = faces[i] + offset
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(shifted)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	var body := StaticBody3D.new()
	body.name = node_name
	body.collision_layer = 1 << (layer - 1)
	body.collision_mask = 0
	body.add_child(cs)
	add_child(body)
	return body


func _build_lights(lights: Array, offset: Vector3) -> void:
	for entry: Dictionary in lights:
		var light := OmniLight3D.new()
		light.position = entry["position"] + offset
		light.light_color = entry["color"]
		light.light_energy = entry["energy"]
		light.omni_range = entry["range"]
		light.shadow_enabled = false
		light.light_bake_mode = Light3D.BAKE_DISABLED
		# Village lights only earn their keep after dark; the sky system
		# fades them in and out.
		light.visible = false
		light.set_meta("interior", entry.get("interior", false))
		add_child(light)
		_lights.append(light)


func set_lights_active(active: bool, energy_scale: float = 1.0) -> void:
	for light in _lights:
		light.visible = active
		if active:
			light.light_energy = light.light_energy * 0.0 + energy_scale * \
				(2.4 if light.get_meta("interior", false) else 3.2)


func height_at_local(lx: int, lz: int) -> int:
	if lx < 0 or lz < 0 or lx >= ChunkBuilder.SIZE or lz >= ChunkBuilder.SIZE:
		return -1
	return heights[lz * ChunkBuilder.SIZE + lx]


func biome_at_local(lx: int, lz: int) -> String:
	if lx < 0 or lz < 0 or lx >= ChunkBuilder.SIZE or lz >= ChunkBuilder.SIZE:
		return dominant_biome
	var order := BiomeLibrary.ids()
	var idx: int = biome_index[lz * ChunkBuilder.SIZE + lx]
	return order[idx] if idx < order.size() else dominant_biome
