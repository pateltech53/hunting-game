class_name TrackManager
extends Node3D
## Footprints and field sign.
##
## Animals drop prints as they walk. The prints age, and a fresh trail is the
## single most useful thing in the game: it tells you what passed, which way it
## was going, and how long ago.

const MAX_PER_SHAPE := 130
const TRACK_LIFETIME_HOURS := 9.0
const SIGN_LIMIT := 60

var sky: SkySystem
var world: VoxelWorld

var _tracks: Array = []                  ## newest last
var _shape_nodes: Dictionary = {}        ## shape -> MultiMeshInstance3D
var _shape_cursor: Dictionary = {}
var _signs: Array = []
var _sign_root: Node3D
var _material: StandardMaterial3D
var _highlight_until := 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	_material = StandardMaterial3D.new()
	_material.vertex_color_use_as_albedo = true
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	_material.roughness = 1.0
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_sign_root = Node3D.new()
	_sign_root.name = "Sign"
	add_child(_sign_root)


func setup(sky_system: SkySystem, voxel_world: VoxelWorld) -> void:
	sky = sky_system
	world = voxel_world


func _shape_node(shape: String) -> MultiMeshInstance3D:
	if _shape_nodes.has(shape):
		return _shape_nodes[shape]
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = _build_track_mesh(shape)
	mm.instance_count = MAX_PER_SHAPE
	for i in MAX_PER_SHAPE:
		mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ZERO), Vector3.ZERO))
		mm.set_instance_color(i, Color(0, 0, 0, 0))
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Tracks_%s" % shape
	mmi.multimesh = mm
	mmi.material_override = _material
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)
	_shape_nodes[shape] = mmi
	_shape_cursor[shape] = 0
	return mmi


## Track shapes are drawn as flat cells so each species leaves a recognisable
## print - the Discovery Book teaches you to read them.
func _build_track_mesh(shape: String) -> ArrayMesh:
	var cells: Array = []
	match shape:
		"cloven":
			cells = [Vector2(-0.28, -0.5), Vector2(-0.28, -0.15), Vector2(-0.24, 0.2),
				Vector2(0.28, -0.5), Vector2(0.28, -0.15), Vector2(0.24, 0.2)]
		"pad":
			cells = [Vector2(0.0, 0.28), Vector2(-0.05, 0.30), Vector2(0.05, 0.30),
				Vector2(-0.34, -0.06), Vector2(-0.13, -0.30), Vector2(0.13, -0.30),
				Vector2(0.34, -0.06)]
		"claw":
			cells = [Vector2(-0.3, 0.2), Vector2(-0.1, 0.28), Vector2(0.1, 0.28),
				Vector2(0.3, 0.2), Vector2(0.0, 0.05), Vector2(-0.16, 0.0),
				Vector2(0.16, 0.0), Vector2(0.0, -0.22), Vector2(-0.36, -0.36),
				Vector2(0.36, -0.36)]
		"bird":
			cells = [Vector2(0.0, 0.0), Vector2(0.0, -0.34), Vector2(-0.16, 0.26),
				Vector2(-0.28, 0.42), Vector2(0.16, 0.26), Vector2(0.28, 0.42),
				Vector2(0.0, 0.30), Vector2(0.0, 0.46)]
		_:
			cells = [Vector2(0.0, -0.2), Vector2(-0.26, 0.06), Vector2(-0.1, 0.28),
				Vector2(0.1, 0.28), Vector2(0.26, 0.06)]

	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var half := 0.13
	for c: Vector2 in cells:
		var p := [
			Vector3(c.x - half, 0.0, c.y - half), Vector3(c.x + half, 0.0, c.y - half),
			Vector3(c.x + half, 0.0, c.y + half), Vector3(c.x - half, 0.0, c.y + half),
		]
		for tri: Array in [[0, 1, 2], [0, 2, 3]]:
			for k: int in tri:
				verts.push_back(p[k])
				normals.push_back(Vector3.UP)
				colors.push_back(Color(1, 1, 1, 1))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func register_track(species: Species, position: Vector3, yaw: float) -> void:
	if world == null:
		return
	var ground := float(world.surface_height(position.x, position.z))
	if ground < TerrainGenerator.SEA_LEVEL:
		return                                        # no prints on open water
	var shape := species.track_shape
	var node := _shape_node(shape)
	var cursor: int = _shape_cursor[shape]
	var mm: MultiMesh = node.multimesh

	var basis := Basis(Vector3.UP, yaw).scaled(Vector3.ONE * species.track_size * 2.6)
	var pos := Vector3(position.x, ground + 0.035, position.z)
	mm.set_instance_transform(cursor, Transform3D(basis, pos - node.global_position))
	_shape_cursor[shape] = (cursor + 1) % MAX_PER_SHAPE

	_tracks.append({
		"species": species.id,
		"shape": shape,
		"position": pos,
		"yaw": yaw,
		"hour": sky.time_of_day if sky != null else 12.0,
		"stamp": Time.get_ticks_msec(),
		"slot": cursor,
	})
	if _tracks.size() > MAX_PER_SHAPE * 4:
		_tracks.remove_at(0)
	_refresh_instance(_tracks[_tracks.size() - 1])


func _refresh_instance(track: Dictionary) -> void:
	var node: MultiMeshInstance3D = _shape_nodes.get(track["shape"], null)
	if node == null:
		return
	var age := _age_hours(track)
	var freshness := clampf(1.0 - age / TRACK_LIFETIME_HOURS, 0.0, 1.0)
	var alpha := clampf(freshness * 0.75, 0.0, 0.8)
	if Time.get_ticks_msec() * 0.001 < _highlight_until:
		alpha = clampf(alpha + 0.35, 0.0, 1.0)
	# Fresh prints are dark and sharp, old ones grey out and vanish.
	var col := Color(0.10, 0.08, 0.06).lerp(Color(0.42, 0.40, 0.36), 1.0 - freshness)
	if Time.get_ticks_msec() * 0.001 < _highlight_until:
		col = col.lerp(Color(0.95, 0.80, 0.35), 0.55)
	col.a = alpha
	node.multimesh.set_instance_color(track["slot"], col)


func _age_hours(track: Dictionary) -> float:
	var elapsed_ms := float(Time.get_ticks_msec() - int(track["stamp"]))
	var real_seconds := elapsed_ms * 0.001
	var day_minutes: float = sky.day_length_minutes if sky != null else 24.0
	if day_minutes <= 0.0:
		return 0.0
	return real_seconds * (24.0 / (day_minutes * 60.0))


func _process(_delta: float) -> void:
	# Age a slice of the buffer each frame rather than all of it.
	if _tracks.is_empty():
		return
	var count := mini(24, _tracks.size())
	for i in count:
		var idx := _rng.randi_range(0, _tracks.size() - 1)
		_refresh_instance(_tracks[idx])


## Everything the player could find by looking around from [param from].
func tracks_near(from: Vector3, radius: float) -> Array:
	var out: Array = []
	for t: Dictionary in _tracks:
		if from.distance_to(t["position"]) <= radius:
			out.append(t)
	return out


func freshest_near(from: Vector3, radius: float) -> Dictionary:
	var best := {}
	var best_age := INF
	for t: Dictionary in tracks_near(from, radius):
		var age := _age_hours(t)
		if age < best_age:
			best_age = age
			best = t
	return best


func age_label(track: Dictionary) -> String:
	var age := _age_hours(track)
	if age < 0.25:
		return "minutes old"
	if age < 1.0:
		return "under an hour old"
	if age < 3.0:
		return "a few hours old"
	if age < 6.0:
		return "half a day old"
	return "cold"


func freshness(track: Dictionary) -> float:
	return clampf(1.0 - _age_hours(track) / TRACK_LIFETIME_HOURS, 0.0, 1.0)


func highlight(seconds: float) -> void:
	_highlight_until = Time.get_ticks_msec() * 0.001 + seconds
	for t: Dictionary in _tracks:
		_refresh_instance(t)


# ----------------------------------------------------------------------- sign

## Scat, rubs, feathers and beds. Placed by the wildlife director so a species
## leaves evidence in its territory before you ever see it.
func add_sign(species: Species, position: Vector3, kind: String) -> void:
	if world == null or _signs.size() >= SIGN_LIMIT:
		if _signs.size() >= SIGN_LIMIT:
			var oldest: Dictionary = _signs.pop_front()
			if is_instance_valid(oldest["node"]):
				oldest["node"].queue_free()
		if world == null:
			return
	var ground := float(world.surface_height(position.x, position.z))
	if ground < TerrainGenerator.SEA_LEVEL:
		return
	var voxels := {}
	var col := Color(0.22, 0.16, 0.11)
	match kind:
		"scat":
			for i in 4:
				voxels[Vector3i(_rng.randi_range(-1, 1), 0, _rng.randi_range(-1, 1))] = col
		"rub":
			col = Color(0.72, 0.62, 0.46)
			for y in 5:
				voxels[Vector3i(0, y, 0)] = col
		"feather":
			col = species.palette.get("secondary", Color(0.6, 0.5, 0.4))
			for z in 3:
				voxels[Vector3i(0, 0, z)] = col
		"bed":
			col = Color(0.36, 0.34, 0.22)
			for x in range(-2, 3):
				for z in range(-2, 3):
					if absi(x) + absi(z) <= 2:
						voxels[Vector3i(x, 0, z)] = col
		_:
			voxels[Vector3i(0, 0, 0)] = col

	var mesh := VoxelMesher.build_mesh(voxels, Vector3.ZERO, false, 0.09)
	if mesh == null:
		return
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = PropMeshes.material()
	mi.position = Vector3(position.x, ground + 0.02, position.z)
	mi.rotation.y = _rng.randf_range(-PI, PI)
	_sign_root.add_child(mi)
	_signs.append({
		"species": species.id, "kind": kind, "node": mi,
		"position": mi.position, "found": false,
	})


func sign_near(from: Vector3, radius: float) -> Array:
	var out: Array = []
	for s: Dictionary in _signs:
		if from.distance_to(s["position"]) <= radius:
			out.append(s)
	return out


func clear() -> void:
	_tracks.clear()
	for shape: String in _shape_nodes:
		var mm: MultiMesh = _shape_nodes[shape].multimesh
		for i in mm.instance_count:
			mm.set_instance_color(i, Color(0, 0, 0, 0))
	for s: Dictionary in _signs:
		if is_instance_valid(s["node"]):
			s["node"].queue_free()
	_signs.clear()
