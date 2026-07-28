class_name VoxelWorld
extends Node3D
## Streams chunks around the player on worker threads and answers the terrain
## queries every other system needs.

signal initial_load_progress(done: int, total: int)
signal initial_load_finished
signal chunk_ready(chunk: VoxelChunk)

const APPLY_PER_FRAME := 2
const MAX_PENDING := 6
const COLLISION_RADIUS := 3

var gen: TerrainGenerator
var view_distance := 6
var grass_density := 1.0

var chunks: Dictionary = {}          ## Vector2i -> VoxelChunk
var markers: Array = []              ## points of photographic interest
var villages: Dictionary = {}        ## name -> site dictionary

var _pending: Dictionary = {}        ## Vector2i -> task id
var _results: Dictionary = {}        ## Vector2i -> built data
var _mutex := Mutex.new()
var _centre := Vector2i(9999, 9999)
var _initial_targets: Array = []
var _initial_done := false
var _lights_on := false


func setup(seed_value: int) -> void:
	gen = TerrainGenerator.new(seed_value)
	view_distance = Settings.effective_view_distance()
	grass_density = Settings.grass_density()
	# Everything the worker threads read must exist before they start.
	BiomeLibrary.ids()
	PropMeshes.warm_cache()


func begin_initial_load(around: Vector3) -> void:
	_centre = _chunk_of(around)
	_initial_targets.clear()
	# Web waits on a slower build, so it opens with a tighter ring and streams
	# the rest in behind the player.
	var r := mini(view_distance, 3 if Settings.is_web() else 4)
	for dz in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var c := _centre + Vector2i(dx, dz)
			if Vector2(dx, dz).length() <= float(r) + 0.5:
				_initial_targets.append(c)
	_initial_targets.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return (a - _centre).length_squared() < (b - _centre).length_squared())
	_initial_done = false


var _village_scan_timer := 0.0


func _process(delta: float) -> void:
	_collect_results()
	_apply_results()
	_dispatch()
	_scan_villages(delta)


## Village sites are a pure function of the seed, so we can know about them
## before their chunks are built. That is what lets the map show a settlement
## you have not walked to yet, and lets the wildlife director populate one the
## moment you come within range.
func _scan_villages(delta: float) -> void:
	_village_scan_timer -= delta
	if _village_scan_timer > 0.0 or gen == null:
		return
	_village_scan_timer = 2.0
	var centre_world := Vector3(float(_centre.x * ChunkBuilder.SIZE), 0.0,
		float(_centre.y * ChunkBuilder.SIZE))
	for site: Dictionary in Structures.village_sites_near(gen, centre_world.x,
			centre_world.z, 800.0):
		villages[site["name"]] = site


func update_centre(world_pos: Vector3) -> void:
	var c := _chunk_of(world_pos)
	if c != _centre:
		_centre = c
		_unload_far()


func _chunk_of(pos: Vector3) -> Vector2i:
	return Vector2i(int(floor(pos.x / float(ChunkBuilder.SIZE))),
		int(floor(pos.z / float(ChunkBuilder.SIZE))))


func _dispatch() -> void:
	if _pending.size() >= MAX_PENDING:
		return
	var wanted := _initial_targets if not _initial_done else _ring_targets()
	for coord: Vector2i in wanted:
		if chunks.has(coord) or _pending.has(coord) or _results.has(coord):
			continue
		var want_collision := (coord - _centre).length() <= float(COLLISION_RADIUS)
		var task := WorkerThreadPool.add_task(_build_task.bind(coord, want_collision),
			false, "wildlight_chunk")
		_pending[coord] = task
		if _pending.size() >= MAX_PENDING:
			return


func _ring_targets() -> Array:
	var out: Array = []
	for dz in range(-view_distance, view_distance + 1):
		for dx in range(-view_distance, view_distance + 1):
			if Vector2(dx, dz).length() > float(view_distance) + 0.5:
				continue
			out.append(_centre + Vector2i(dx, dz))
	out.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return (a - _centre).length_squared() < (b - _centre).length_squared())
	return out


func _build_task(coord: Vector2i, want_collision: bool) -> void:
	var data := ChunkBuilder.build(gen, coord, grass_density, want_collision)
	_mutex.lock()
	_results[coord] = data
	_mutex.unlock()


func _collect_results() -> void:
	if _pending.is_empty():
		return
	var finished: Array = []
	for coord: Vector2i in _pending:
		if WorkerThreadPool.is_task_completed(_pending[coord]):
			finished.append(coord)
	for coord: Vector2i in finished:
		WorkerThreadPool.wait_for_task_completion(_pending[coord])
		_pending.erase(coord)


func _apply_results() -> void:
	var applied := 0
	while applied < APPLY_PER_FRAME:
		_mutex.lock()
		var keys: Array = _results.keys()
		if keys.is_empty():
			_mutex.unlock()
			break
		var coord: Vector2i = keys[0]
		var data: Dictionary = _results[coord]
		_results.erase(coord)
		_mutex.unlock()

		if chunks.has(coord):
			continue
		var chunk := VoxelChunk.new()
		chunk.name = "Chunk_%d_%d" % [coord.x, coord.y]
		add_child(chunk)
		chunk.apply(data, true)
		chunk.set_lights_active(_lights_on)
		chunks[coord] = chunk
		_register_markers(chunk)
		chunk_ready.emit(chunk)
		applied += 1

	if not _initial_done and _pending.is_empty() and _results.is_empty():
		var ready_count := 0
		for coord: Vector2i in _initial_targets:
			if chunks.has(coord):
				ready_count += 1
		initial_load_progress.emit(ready_count, _initial_targets.size())
		if ready_count >= _initial_targets.size():
			_initial_done = true
			initial_load_finished.emit()
	elif not _initial_done:
		var ready_count := 0
		for coord: Vector2i in _initial_targets:
			if chunks.has(coord):
				ready_count += 1
		initial_load_progress.emit(ready_count, _initial_targets.size())


func _register_markers(chunk: VoxelChunk) -> void:
	for m: Dictionary in chunk.markers:
		markers.append(m)
	for site: Dictionary in chunk.village_sites:
		villages[site["name"]] = site


func _unload_far() -> void:
	var limit := float(view_distance) + 1.5
	var doomed: Array = []
	for coord: Vector2i in chunks:
		if (coord - _centre).length() > limit:
			doomed.append(coord)
	for coord: Vector2i in doomed:
		var chunk: VoxelChunk = chunks[coord]
		chunks.erase(coord)
		# Markers belonging to unloaded chunks stay in the list: they are
		# knowledge about the world, not scene state.
		chunk.queue_free()


func set_night_lights(on: bool) -> void:
	if _lights_on == on:
		return
	_lights_on = on
	for coord: Vector2i in chunks:
		chunks[coord].set_lights_active(on)


# ------------------------------------------------------------------- queries

func surface_height(x: float, z: float) -> int:
	return gen.height_i(int(floor(x)), int(floor(z)))


func ground_point(x: float, z: float) -> Vector3:
	return Vector3(x, float(surface_height(x, z)), z)


func biome_at(x: float, z: float) -> String:
	return gen.biome_at(x, z)


func biome_ref_at(x: float, z: float) -> Biome:
	return BiomeLibrary.get_biome(biome_at(x, z))


func is_water_at(x: float, z: float) -> bool:
	return surface_height(x, z) < TerrainGenerator.SEA_LEVEL


func water_level() -> float:
	return float(TerrainGenerator.SEA_LEVEL)


func is_loaded_at(pos: Vector3) -> bool:
	return chunks.has(_chunk_of(pos))


func markers_of_kind(kind: String) -> Array:
	var out: Array = []
	for m: Dictionary in markers:
		if m.get("kind", "") == kind:
			out.append(m)
	return out


func nearest_marker(kind: String, from: Vector3) -> Dictionary:
	var best := {}
	var best_d := INF
	for m: Dictionary in markers:
		if m.get("kind", "") != kind:
			continue
		var d: float = from.distance_to(m["position"])
		if d < best_d:
			best_d = d
			best = m
	return best


## A dry, reasonably flat spot to start the player on. If there is a village
## within a comfortable walk it becomes the anchor, so the photo genres that
## need people are actually reachable on foot.
func find_spawn() -> Vector3:
	var anchor := Vector2.ZERO
	var sites := Structures.village_sites_near(gen, 0.0, 0.0, 1200.0)
	if not sites.is_empty():
		var best: Dictionary = sites[0]
		var best_d := INF
		for site: Dictionary in sites:
			var pos: Vector3 = site["position"]
			var d := Vector2(pos.x, pos.z).length()
			if d < best_d:
				best_d = d
				best = site
		var chosen: Vector3 = best["position"]
		# Start a few hundred metres out - near enough to walk in, far enough
		# that the first thing you see is forest.
		var away := Vector2(chosen.x, chosen.z).normalized()
		if away.length() < 0.01:
			away = Vector2(1.0, 0.0)
		anchor = Vector2(chosen.x, chosen.z) - away * 240.0
	var p := gen.find_flat_ground(anchor, 130.0, 160)
	return p + Vector3(0.0, 1.2, 0.0)


func loaded_chunk_count() -> int:
	return chunks.size()


func _exit_tree() -> void:
	for coord: Vector2i in _pending:
		WorkerThreadPool.wait_for_task_completion(_pending[coord])
	_pending.clear()
	_results.clear()
