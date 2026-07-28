class_name WildlifeDirector
extends Node3D
## Keeps a believable population of animals and villagers around the player:
## spawns herds out of sight in habitat that suits them, seeds their territory
## with field sign, and cleans up behind you.

signal animal_spawned(animal: Animal)
signal animal_died(animal: Animal)

const SPAWN_INTERVAL := 0.45
const SPAWN_MIN := 42.0
const SPAWN_MAX := 165.0
const DESPAWN := 340.0
## A forest with a dozen animals in 300 metres reads as empty. This is the
## headcount the world aims to hold around the player; the weather modifier
## still thins it out in bad conditions.
const BASE_POPULATION := 52
## Until the world is stocked, spawn far more eagerly so the first minute has
## something in it rather than a long empty walk.
const WARMUP_POPULATION := 22
const WARMUP_INTERVAL := 0.12
const VILLAGE_RANGE := 190.0
const VILLAGERS_PER_VILLAGE := 7

var world: VoxelWorld
var sky: SkySystem
var weather: WeatherSystem
var player: Player
var track_manager: TrackManager

var animals: Array[Animal] = []
var villagers: Array[Villager] = []

var _spawn_timer := 0.0
var _village_timer := 0.0
var _rng := RandomNumberGenerator.new()
var _village_populations: Dictionary = {}


func setup(voxel_world: VoxelWorld, sky_system: SkySystem, weather_system: WeatherSystem,
		hunter: Player, tracks: TrackManager) -> void:
	world = voxel_world
	sky = sky_system
	weather = weather_system
	player = hunter
	track_manager = tracks
	_rng.seed = Game.world_seed + 5150


func _process(delta: float) -> void:
	if player == null or world == null or Game.is_paused:
		return
	_spawn_timer -= delta
	_village_timer -= delta
	_cull()
	if _spawn_timer <= 0.0:
		_spawn_timer = WARMUP_INTERVAL if animals.size() < WARMUP_POPULATION \
			else SPAWN_INTERVAL
		_try_spawn()
	if _village_timer <= 0.0:
		_village_timer = 3.0
		_manage_villages()


func target_population() -> int:
	var modifier: float = weather.activity_modifier() if weather != null else 1.0
	return int(round(float(BASE_POPULATION) * modifier))


func _cull() -> void:
	var origin := player.global_position
	for i in range(animals.size() - 1, -1, -1):
		var a := animals[i]
		if not is_instance_valid(a):
			animals.remove_at(i)
			continue
		var d := origin.distance_to(a.global_position)
		if d > DESPAWN or (a.is_dead and d > 140.0):
			animals.remove_at(i)
			a.queue_free()
	for i in range(villagers.size() - 1, -1, -1):
		var v := villagers[i]
		if not is_instance_valid(v):
			villagers.remove_at(i)
			continue
		if origin.distance_to(v.global_position) > VILLAGE_RANGE + 90.0:
			villagers.remove_at(i)
			v.queue_free()


func _try_spawn() -> void:
	if animals.size() >= target_population():
		return
	var point := _pick_spawn_point()
	if point == Vector3.ZERO:
		return
	var biome_id := world.biome_at(point.x, point.z)
	var species := _pick_species(biome_id, point)
	if species == null:
		return
	spawn_herd(species, point)


func _pick_spawn_point() -> Vector3:
	var cam := player.camera()
	for attempt in 8:
		var angle := _rng.randf_range(-PI, PI)
		var distance := _rng.randf_range(SPAWN_MIN, SPAWN_MAX)
		var p := player.global_position + Vector3(cos(angle) * distance, 0.0,
			sin(angle) * distance)
		var h := float(world.surface_height(p.x, p.z))
		p.y = h
		# Do not pop an animal into existence in front of the player.
		if cam.is_position_in_frustum(p + Vector3.UP) and distance < 120.0:
			continue
		return p
	return Vector3.ZERO


func _pick_species(biome_id: String, point: Vector3) -> Species:
	var options := SpeciesLibrary.for_biome(biome_id)
	if options.is_empty():
		return null
	var hour: float = sky.time_of_day if sky != null else 12.0
	var height := float(world.surface_height(point.x, point.z))
	var near_water := _water_within(point, 26.0)

	var total := 0.0
	var weighted: Array = []
	for entry: Dictionary in options:
		var s: Species = entry["species"]
		var w := float(entry["weight"])
		w *= s.activity_at(hour)
		# Rarer animals turn up less often.
		w *= lerpf(1.0, 0.18, s.rarity)
		if s.near_water > 0.05:
			w *= lerpf(1.0, 2.4, s.near_water) if near_water else lerpf(1.0, 0.06, s.near_water)
		if s.altitude_pref.x > -900.0:
			if height < s.altitude_pref.x or height > s.altitude_pref.y:
				w *= 0.12
		# Do not stack the world with animals the player already has plenty of.
		var present := 0
		for a: Animal in animals:
			if is_instance_valid(a) and a.species.id == s.id:
				present += 1
		w *= clampf(1.0 - float(present) * 0.22, 0.05, 1.0)
		if w <= 0.0:
			continue
		total += w
		weighted.append({"species": s, "acc": total})
	if weighted.is_empty():
		return null
	var roll := _rng.randf() * total
	for entry: Dictionary in weighted:
		if roll <= float(entry["acc"]):
			return entry["species"]
	return weighted[weighted.size() - 1]["species"]


func _water_within(point: Vector3, radius: float) -> bool:
	for i in 6:
		var a := TAU * float(i) / 6.0
		var p := point + Vector3(cos(a) * radius, 0.0, sin(a) * radius)
		if world.is_water_at(p.x, p.z):
			return true
	return world.is_water_at(point.x, point.z)


func spawn_herd(species: Species, centre: Vector3) -> Array:
	var count := species.herd_size(_rng)
	var spawned: Array = []
	var leader: Animal = null
	for i in count:
		if animals.size() >= target_population() + 6:
			break
		var offset := Vector3(_rng.randf_range(-8.0, 8.0), 0.0, _rng.randf_range(-8.0, 8.0)) \
			if i > 0 else Vector3.ZERO
		var pos := centre + offset
		pos.y = float(world.surface_height(pos.x, pos.z))
		if pos.y < TerrainGenerator.SEA_LEVEL and not species.swims:
			continue
		var animal := Animal.new()
		animal.name = "%s_%d" % [species.id, animals.size()]
		add_child(animal)
		animal.setup(species, pos, world, sky, weather, player, track_manager)
		animal.died.connect(_on_animal_died)
		if leader == null:
			leader = animal
		animal.herd_leader = leader
		animals.append(animal)
		spawned.append(animal)
		animal_spawned.emit(animal)

	if not spawned.is_empty():
		_seed_sign(species, centre)
		# Credit the seeded prints to the leader so following them actually
		# arrives at an animal rather than at an empty clearing.
		_seed_trail(species, centre, leader.get_instance_id())
	return spawned


## Leaves a short trail of prints running into the area, so a scan finds
## something even if the animal has already moved on.
func _seed_trail(species: Species, centre: Vector3, walker: int = 0) -> void:
	if track_manager == null:
		return
	var heading := _rng.randf_range(-PI, PI)
	var pos := centre - Vector3(sin(heading), 0.0, cos(heading)) * _rng.randf_range(18.0, 40.0)
	var stride: float = maxf(species.body_length * 0.6, 0.7)
	var steps := int(_rng.randf_range(10.0, 22.0))
	for i in steps:
		pos += Vector3(sin(heading), 0.0, cos(heading)) * stride
		heading += _rng.randf_range(-0.12, 0.12)
		pos.y = float(world.surface_height(pos.x, pos.z))
		track_manager.register_track(species, pos, heading, walker)


func _seed_sign(species: Species, centre: Vector3) -> void:
	if track_manager == null:
		return
	var kinds := ["scat", "bed"]
	if species.has_antlers:
		kinds.append("rub")
	if species.can_fly:
		kinds = ["feather", "scat"]
	for i in _rng.randi_range(1, 2):
		var kind: String = kinds[_rng.randi_range(0, kinds.size() - 1)]
		var p := centre + Vector3(_rng.randf_range(-22.0, 22.0), 0.0,
			_rng.randf_range(-22.0, 22.0))
		track_manager.add_sign(species, p, kind)


func _on_animal_died(animal: Animal) -> void:
	animal_died.emit(animal)


# ------------------------------------------------------------------- villages

func _manage_villages() -> void:
	var origin := player.global_position
	# Recount from the live villagers rather than trusting a running total:
	# culling people when you walk away has to let the village repopulate when
	# you come back.
	_village_populations.clear()
	for v in villagers:
		if not is_instance_valid(v):
			continue
		_village_populations[v.village_key] = int(
			_village_populations.get(v.village_key, 0)) + 1
	for name_key: String in world.villages:
		var site: Dictionary = world.villages[name_key]
		var centre: Vector3 = site["position"]
		if origin.distance_to(centre) > VILLAGE_RANGE:
			continue
		var have: int = _village_populations.get(name_key, 0)
		if have >= VILLAGERS_PER_VILLAGE:
			continue
		_populate_village(name_key, site)


func _populate_village(name_key: String, site: Dictionary) -> void:
	var centre: Vector3 = site["position"]
	var is_wedding: bool = site.get("kind", "") == "wedding"
	var roles: Array = []
	if is_wedding:
		roles = ["bride", "groom", "officiant", "guest", "guest", "guest", "guest"]
	else:
		roles = ["villager", "villager", "villager", "villager", "villager", "villager",
			"villager"]
	var wedding_marker := world.nearest_marker("wedding", centre)
	var existing: int = _village_populations.get(name_key, 0)
	for i in range(existing, VILLAGERS_PER_VILLAGE):
		var role: String = roles[i % roles.size()]
		var anchor := centre
		if is_wedding and not wedding_marker.is_empty():
			anchor = wedding_marker["position"]
			var spread: float = 2.0 if role in ["bride", "groom", "officiant"] else 7.0
			anchor += Vector3(_rng.randf_range(-spread, spread), 0.0,
				_rng.randf_range(0.0, spread + 3.0))
		else:
			anchor += Vector3(_rng.randf_range(-14.0, 14.0), 0.0, _rng.randf_range(-14.0, 14.0))
		anchor.y = float(world.surface_height(anchor.x, anchor.z))
		var v := Villager.new()
		v.name = "%s_villager_%d" % [name_key, i]
		add_child(v)
		v.setup(anchor, world, player, role, Game.world_seed + hash(name_key) + i)
		v.village_key = name_key
		if role in ["bride", "groom", "officiant"]:
			v.wander_radius = 1.5
		villagers.append(v)
	_village_populations[name_key] = VILLAGERS_PER_VILLAGE


# ------------------------------------------------------------------ interface

func active_animals() -> Array:
	var out: Array = []
	for a in animals:
		if is_instance_valid(a):
			out.append(a)
	return out


## Everything the photo scorer should consider as a possible subject.
func subjects() -> Array:
	var out: Array = []
	for a in animals:
		if is_instance_valid(a):
			out.append(a)
	for v in villagers:
		if is_instance_valid(v):
			out.append(v)
	return out


func nearest_animal(from: Vector3, max_distance: float = 500.0) -> Animal:
	var best: Animal = null
	var best_d := max_distance
	for a in animals:
		if not is_instance_valid(a) or a.is_dead:
			continue
		var d := from.distance_to(a.global_position)
		if d < best_d:
			best_d = d
			best = a
	return best


## Sandbox: drop a specific species right in front of the player.
func sandbox_spawn(species_id: String, at: Vector3) -> void:
	var s := SpeciesLibrary.get_species(species_id)
	if s == null:
		return
	var p := at
	p.y = float(world.surface_height(p.x, p.z))
	spawn_herd(s, p)
	Game.notify("Spawned %s" % s.name, "info")


func clear_all() -> void:
	for a in animals:
		if is_instance_valid(a):
			a.queue_free()
	animals.clear()
	for v in villagers:
		if is_instance_valid(v):
			v.queue_free()
	villagers.clear()
	_village_populations.clear()


func population_summary() -> String:
	return "%d animals, %d people" % [animals.size(), villagers.size()]
