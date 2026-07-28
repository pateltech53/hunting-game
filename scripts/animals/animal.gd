class_name Animal
extends CharacterBody3D
## One living animal: senses, a small behaviour state machine, a procedural
## walk cycle, and everything the camera and the rifle need to know about it.
##
## Movement is done against the terrain height field rather than through the
## physics solver, so a valley full of deer costs almost nothing. The collision
## shape exists purely so bullets and autofocus have something to hit.

signal died(animal: Animal)
signal state_changed(state: String)
signal spooked(animal: Animal)

enum State { IDLE, WANDER, BUSY, ALERT, FLEE, REST, DEAD }

const TURN_SMOOTH := 4.0
const AWARENESS_DECAY := 0.28
const FLEE_MEMORY := 9.0

## Families a prey animal will run from on sight. Kept here rather than on
## Species because it is a fact about the ecosystem, not about one animal.
const PREDATOR_FAMILIES := ["Canidae", "Ursidae", "Felidae", "Accipitridae"]

var species: Species
var world: VoxelWorld
var sky: SkySystem
var weather: WeatherSystem
var player: Player
var track_manager: Node
var herd_id := -1
var herd_leader: Animal = null

var state: State = State.WANDER
var behaviour := "walking"
var awareness := 0.0
var health := 100.0
var wounded := false
var is_dead := false
var measurements: Dictionary = {}

var _model: Node3D
var _head: Node3D
var _legs: Array[Node3D] = []
var _tail: Node3D
var _wings: Array[Node3D] = []
var _target := Vector3.ZERO
var _home := Vector3.ZERO
var _home_radius := 45.0
var _speed := 0.0
var _yaw := 0.0
var _gait := 0.0
var _state_timer := 0.0
var _call_timer := 0.0
var _track_distance := 0.0
var _last_track_pos := Vector3.ZERO
var _flee_timer := 0.0
var _look_at_player := 0.0

# ------------------------------------------------------------------- drives
# Animals are not random walkers. Each carries three needs that climb with
# time and are satisfied by going somewhere specific, so what looks like
# wandering is usually an animal on its way to water, to food, or to bed.
var hunger := 0.0
var thirst := 0.0
var fatigue := 0.0
var intent := "wandering"       ## what the current target is for
var _needs_timer := 0.0
var _predator_check := 0.0
var _curious_cooldown := 0.0
var _rng := RandomNumberGenerator.new()
var _collider: CollisionShape3D
var _sighted_reported := false


func setup(s: Species, spawn: Vector3, voxel_world: VoxelWorld, sky_system: SkySystem,
		weather_system: WeatherSystem, hunter: Player, tracks: Node) -> void:
	species = s
	world = voxel_world
	sky = sky_system
	weather = weather_system
	player = hunter
	track_manager = tracks
	_rng.randomize()
	_home = spawn
	_home_radius = 30.0 + s.body_length * 14.0
	global_position = spawn
	_last_track_pos = spawn
	_yaw = _rng.randf_range(-PI, PI)
	rotation.y = _yaw
	_roll_measurements()

	collision_layer = 1 << 2
	collision_mask = 0

	var capsule := CapsuleShape3D.new()
	capsule.radius = maxf(species.body_length * 0.22, 0.16)
	capsule.height = maxf(species.shoulder_height * 1.25, capsule.radius * 2.2)
	_collider = CollisionShape3D.new()
	_collider.shape = capsule
	_collider.position = Vector3(0.0, capsule.height * 0.5, 0.0)
	add_child(_collider)

	_model = CreatureBody.build(species)
	add_child(_model)
	_cache_parts()
	_pick_new_target()
	_call_timer = _rng.randf_range(species.call_cooldown.x, species.call_cooldown.y)


func _roll_measurements() -> void:
	var weight: float = _rng.randf_range(species.weight_range.x, species.weight_range.y)
	measurements["weight"] = snappedf(weight, 0.1)
	if species.has_antlers:
		measurements["points"] = _rng.randi_range(species.antler_points.x,
			species.antler_points.y)
	measurements["age"] = _rng.randi_range(1, 12)


func _cache_parts() -> void:
	_head = _model.get_node_or_null("Head")
	_tail = _model.get_node_or_null("Tail")
	for leg_name: String in ["LegFL", "LegFR", "LegBL", "LegBR"]:
		var node: Node3D = _model.get_node_or_null(leg_name)
		if node != null:
			_legs.append(node)
	for wing_name: String in ["WingL", "WingR"]:
		var node: Node3D = _model.get_node_or_null(wing_name)
		if node != null:
			_wings.append(node)


# ------------------------------------------------------------------ behaviour

func _physics_process(delta: float) -> void:
	if is_dead:
		return
	_sense(delta)
	_think(delta)
	_move(delta)
	_animate(delta)
	_maybe_call(delta)
	_report_sighting()


## Hearing, sight and scent, in that order of range for most species.
func _sense(delta: float) -> void:
	if player == null:
		return
	var to_player := player.global_position - global_position
	var distance := to_player.length()
	var detection := 0.0

	if distance < species.hearing_range:
		var noise := player.noise_level()
		var falloff := 1.0 - distance / species.hearing_range
		detection = maxf(detection, noise * falloff * 1.4)

	if distance < species.vision_range:
		var forward := -global_transform.basis.z
		var angle := rad_to_deg(forward.angle_to(to_player.normalized()))
		if angle < species.vision_angle * 0.5:
			var falloff := 1.0 - distance / species.vision_range
			var moving := clampf(Vector2(player.velocity.x, player.velocity.z).length()
				/ 5.0, 0.15, 1.4)
			var crouch_bonus: float = 0.45 if player.crouched else 1.0
			# Standing still in cover is genuinely effective.
			detection = maxf(detection, falloff * moving * crouch_bonus * 1.1)

	if weather != null and distance < species.scent_range:
		var scent := player.scent_strength_at(global_position, weather.wind_direction(),
			weather.wind())
		detection = maxf(detection, scent * 1.3)

	detection *= species.wariness * 1.4
	if detection > 0.0:
		awareness = clampf(awareness + detection * delta * 1.6, 0.0, 1.4)
	else:
		awareness = maxf(0.0, awareness - AWARENESS_DECAY * delta)


## Needs climb slowly and are reset by acting on them. Rates are per real
## second and tuned so an animal cycles food, water and rest a few times an
## hour rather than constantly.
func _update_needs(delta: float) -> void:
	var hour: float = sky.time_of_day if sky != null else 12.0
	hunger = minf(1.0, hunger + delta * 0.012)
	thirst = minf(1.0, thirst + delta * 0.017)
	# Tiredness depends on whether this is one of the species' active hours.
	fatigue = minf(1.0, fatigue + delta * (0.006 if species.is_active_at(hour) else 0.022))
	_curious_cooldown = maxf(0.0, _curious_cooldown - delta)


## Anything bigger that eats meat is worth running from, whether or not it has
## noticed you. Checked on a timer because it walks the whole live list.
func _check_predators(delta: float) -> bool:
	_predator_check -= delta
	if _predator_check > 0.0:
		return false
	_predator_check = 0.9
	if species.family in PREDATOR_FAMILIES:
		return false                                  # predators fear nothing here
	var director := get_parent()
	if director == null or not director.has_method("active_animals"):
		return false
	for other: Animal in director.active_animals():
		if other == self or other.is_dead:
			continue
		if other.species.family not in PREDATOR_FAMILIES:
			continue
		if other.species.shoulder_height < species.shoulder_height * 0.6:
			continue                                  # too small to be a threat
		var d := global_position.distance_to(other.global_position)
		if d < species.vision_range * 0.8:
			_flee_from(other.global_position)
			return true
	return false


func _think(delta: float) -> void:
	_state_timer -= delta
	_flee_timer = maxf(0.0, _flee_timer - delta)
	_update_needs(delta)
	var distance := player.global_position.distance_to(global_position) if player != null \
		else 999.0

	if state != State.FLEE and (awareness >= 1.0 or distance < species.flee_distance * 0.45):
		_enter_flee()
		return
	if state != State.FLEE and _check_predators(delta):
		return
	if state != State.FLEE and state != State.ALERT and awareness > 0.45:
		_set_state(State.ALERT, "alert")
		_state_timer = _rng.randf_range(2.0, 5.0)
		return

	match state:
		State.ALERT:
			_look_at_player = 1.0
			if awareness < 0.25 and _state_timer <= 0.0:
				_set_state(State.WANDER, "walking")
				_pick_new_target()
			elif _state_timer <= 0.0 and distance < species.flee_distance:
				_enter_flee()
		State.FLEE:
			if _flee_timer <= 0.0:
				_set_state(State.ALERT, "alert")
				_state_timer = _rng.randf_range(1.5, 4.0)
				awareness = 0.5
		State.WANDER:
			if global_position.distance_to(_target) < 1.6 or _state_timer <= 0.0:
				# Arriving somewhere it was heading for on purpose is what
				# satisfies the need that sent it there.
				_satisfy_on_arrival()
		State.BUSY, State.IDLE, State.REST:
			if _state_timer <= 0.0:
				_pick_purposeful_target()
		_:
			pass


## Chooses where to go next and why. This is the whole behaviour model: the
## strongest need wins, and each one has a different kind of destination.
func _pick_purposeful_target() -> void:
	var hour: float = sky.time_of_day if sky != null else 12.0

	# Sleep. Outside its active hours a tired animal heads back to cover and
	# stays there, which is why the woods are quiet in the middle of the day.
	if fatigue > 0.65 and not species.is_active_at(hour):
		_target = _valid_ground(_home + Vector3(_rng.randf_range(-6.0, 6.0), 0.0,
			_rng.randf_range(-6.0, 6.0)))
		intent = "returning to cover"
		if global_position.distance_to(_home) < 12.0:
			_enter_rest()
			fatigue = maxf(0.0, fatigue - 0.55)
			return
		_set_state(State.WANDER, "walking")
		_state_timer = _rng.randf_range(8.0, 16.0)
		return

	# Thirst outranks hunger: an animal will walk past food to reach water.
	if thirst > 0.55:
		var water := _find_water()
		if water != Vector3.ZERO:
			_target = water
			intent = "heading for water"
			_set_state(State.WANDER, "walking")
			_state_timer = _rng.randf_range(10.0, 20.0)
			return

	if hunger > 0.5:
		_target = _find_forage()
		intent = "feeding"
		_set_state(State.WANDER, "walking")
		_state_timer = _rng.randf_range(8.0, 16.0)
		return

	# Herding. Drifting too far from the leader pulls it back in, which is what
	# keeps a group looking like a group rather than scattered singles.
	if herd_leader != null and herd_leader != self and is_instance_valid(herd_leader) \
			and not herd_leader.is_dead:
		var lead_gap := global_position.distance_to(herd_leader.global_position)
		if lead_gap > 16.0:
			_target = _valid_ground(herd_leader.global_position + Vector3(
				_rng.randf_range(-5.0, 5.0), 0.0, _rng.randf_range(-5.0, 5.0)))
			intent = "rejoining the herd"
			_set_state(State.WANDER, "walking")
			_state_timer = _rng.randf_range(6.0, 12.0)
			return

	# Curiosity. A bold animal with nothing pressing will come and have a look
	# at you, which is how the best portraits happen.
	if player != null and _curious_cooldown <= 0.0 and awareness < 0.3:
		var gap := global_position.distance_to(player.global_position)
		if gap < species.vision_range and gap > species.flee_distance * 1.2 \
				and _rng.randf() < species.curiosity:
			var toward := (player.global_position - global_position).normalized()
			_target = _valid_ground(global_position + toward
				* (gap - species.flee_distance * 1.1))
			intent = "curious"
			_curious_cooldown = _rng.randf_range(20.0, 60.0)
			_set_state(State.WANDER, "walking")
			_state_timer = _rng.randf_range(5.0, 9.0)
			return

	if _rng.randf() < 0.45:
		_enter_busy()
	else:
		_pick_new_target()
		intent = "wandering"


## Reaching a purposeful destination is what actually pays the need down.
func _satisfy_on_arrival() -> void:
	match intent:
		"heading for water":
			thirst = 0.0
			_enter_busy()
			behaviour = "drinking"
			state_changed.emit(behaviour)
		"feeding":
			hunger = maxf(0.0, hunger - 0.75)
			_enter_busy()
		"returning to cover":
			_enter_rest()
			fatigue = maxf(0.0, fatigue - 0.55)
		_:
			if _rng.randf() < 0.55:
				_enter_busy()
			else:
				_pick_purposeful_target()
	intent = "wandering"


## Walks outward looking for anything at or below the waterline.
func _find_water() -> Vector3:
	if world == null:
		return Vector3.ZERO
	for ring in 6:
		var radius := 14.0 + float(ring) * 16.0
		for step in 8:
			var a := TAU * (float(step) / 8.0) + _rng.randf_range(-0.3, 0.3)
			var p := global_position + Vector3(cos(a), 0.0, sin(a)) * radius
			var h := float(world.surface_height(p.x, p.z))
			if h <= float(TerrainGenerator.SEA_LEVEL):
				# Stop at the bank rather than wading in.
				var toward := (global_position - p).normalized()
				return _valid_ground(p + toward * 2.5)
	return Vector3.ZERO


## Grazers want open ground, browsers want the treeline. Approximated by
## preferring somewhere flatter or steeper than here rather than by reading
## the vegetation, which would cost a lot more for a similar-looking result.
func _find_forage() -> Vector3:
	var best := global_position
	var best_score := -INF
	for attempt in 7:
		var a := _rng.randf_range(-PI, PI)
		var radius := _rng.randf_range(10.0, 38.0)
		var p := _valid_ground(global_position + Vector3(cos(a), 0.0, sin(a)) * radius)
		if p.y <= float(TerrainGenerator.SEA_LEVEL):
			continue
		var slope: float = world.gen.gradient_slope(p.x, p.z) if world != null \
			and world.gen != null else 0.0
		# Big grazers want it flat; small browsers are happier in broken ground.
		var want: float = 0.0 if species.size_class == "large" else 0.35
		var score := -absf(slope - want) + _rng.randf() * 0.2
		if score > best_score:
			best_score = score
			best = p
	return best


## Shared by the player-flee path and the predator-flee path.
func _flee_from(threat: Vector3) -> void:
	var away := (global_position - threat).normalized()
	if away.length() < 0.1:
		away = Vector3.FORWARD
	var run := 30.0 + species.flee_distance
	_target = _valid_ground(global_position + away * run + Vector3(
		_rng.randf_range(-12.0, 12.0), 0.0, _rng.randf_range(-12.0, 12.0)))
	_flee_timer = FLEE_MEMORY + _rng.randf_range(0.0, 4.0)
	intent = "fleeing"
	_set_state(State.FLEE, "fleeing")
	spooked.emit(self)
	if herd_leader != null and herd_leader != self and not herd_leader.is_dead:
		herd_leader.alarm()


func _enter_flee() -> void:
	var away := (global_position - player.global_position).normalized() if player != null \
		else Vector3.FORWARD
	if away.length() < 0.1:
		away = Vector3.FORWARD
	var run := 30.0 + species.flee_distance
	_target = _valid_ground(global_position + away * run + Vector3(
		_rng.randf_range(-12.0, 12.0), 0.0, _rng.randf_range(-12.0, 12.0)))
	_flee_timer = FLEE_MEMORY + _rng.randf_range(0.0, 4.0)
	_set_state(State.FLEE, "fleeing")
	spooked.emit(self)
	# Herds break together.
	if herd_leader != null and herd_leader != self and not herd_leader.is_dead:
		herd_leader.alarm()


## Called by a herd mate that has been spooked.
func alarm() -> void:
	if is_dead or state == State.FLEE:
		return
	awareness = maxf(awareness, 0.85)


func _enter_busy() -> void:
	var options: Array = species.behaviours.filter(func(b: String) -> bool:
		return b not in ["fleeing", "alert"])
	if options.is_empty():
		options = ["grazing"]
	var pick: String = options[_rng.randi_range(0, options.size() - 1)]
	_set_state(State.BUSY, pick)
	_state_timer = _rng.randf_range(4.0, 11.0)


func _enter_rest() -> void:
	_set_state(State.REST, "resting")
	_state_timer = _rng.randf_range(8.0, 22.0)


func _set_state(new_state: State, new_behaviour: String) -> void:
	state = new_state
	if behaviour != new_behaviour:
		behaviour = new_behaviour
		state_changed.emit(behaviour)


func _pick_new_target() -> void:
	var angle := _rng.randf_range(-PI, PI)
	var radius := _rng.randf_range(6.0, _home_radius)
	var candidate := _home + Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
	# Herd members stay near the leader instead of their own home point.
	if herd_leader != null and herd_leader != self and not herd_leader.is_dead:
		candidate = herd_leader.global_position + Vector3(
			_rng.randf_range(-9.0, 9.0), 0.0, _rng.randf_range(-9.0, 9.0))
	_target = _valid_ground(candidate)
	_set_state(State.WANDER, "walking")
	_state_timer = _rng.randf_range(5.0, 14.0)


## Nudges a destination onto ground the animal is willing to stand on.
func _valid_ground(p: Vector3) -> Vector3:
	if world == null:
		return p
	var h := world.surface_height(p.x, p.z)
	var wants_water := species.swims or species.near_water > 0.7
	if h < TerrainGenerator.SEA_LEVEL and not wants_water:
		# Walk back toward home rather than into the lake.
		var back := (_home - p).normalized()
		p += back * 14.0
		h = world.surface_height(p.x, p.z)
	return Vector3(p.x, float(h), p.z)


func _move(delta: float) -> void:
	if world == null:
		return
	var to_target := _target - global_position
	to_target.y = 0.0
	var distance := to_target.length()

	var want_speed := 0.0
	match state:
		State.FLEE:
			want_speed = species.speed_run
		State.WANDER:
			want_speed = species.speed_walk
		State.ALERT:
			want_speed = 0.0
		State.BUSY:
			want_speed = species.speed_walk * 0.22
		_:
			want_speed = 0.0
	if distance < 1.2:
		want_speed = 0.0

	_speed = move_toward(_speed, want_speed, delta * (26.0 if state == State.FLEE else 7.0))

	if distance > 0.4:
		var desired := atan2(to_target.x, to_target.z)
		var turn := species.turn_rate * delta * (1.8 if state == State.FLEE else 1.0)
		_yaw = rotate_toward(_yaw, desired, turn)

	var forward := Vector3(sin(_yaw), 0.0, cos(_yaw))
	var step := forward * _speed * delta
	var next := global_position + step

	# Refuse to climb a cliff; turn along it instead.
	var next_h := float(world.surface_height(next.x, next.z))
	if next_h - global_position.y > 1.6:
		_yaw += delta * 2.4
		next = global_position
		next_h = float(world.surface_height(global_position.x, global_position.z))

	var target_y := next_h
	if species.swims and next_h < TerrainGenerator.SEA_LEVEL:
		target_y = world.water_level() - species.shoulder_height * 0.35
	elif species.can_fly and state == State.FLEE:
		target_y = next_h + 6.0 + sin(Time.get_ticks_msec() * 0.002) * 1.5

	global_position = Vector3(next.x, lerpf(global_position.y, target_y,
		1.0 - pow(0.0008, delta)), next.z)
	rotation.y = _yaw

	_leave_tracks()


func _leave_tracks() -> void:
	if track_manager == null or _speed < 0.3:
		return
	_track_distance += global_position.distance_to(_last_track_pos)
	_last_track_pos = global_position
	var stride: float = maxf(species.body_length * 0.55, 0.6)
	if _track_distance < stride:
		return
	_track_distance = 0.0
	if track_manager.has_method("register_track"):
		track_manager.register_track(species, global_position, _yaw, get_instance_id())


func _animate(delta: float) -> void:
	if _model == null:
		return
	var moving := clampf(_speed / maxf(species.speed_run, 0.1), 0.0, 1.0)
	_gait += delta * (3.0 + moving * 16.0)

	for i in _legs.size():
		var phase: float = _gait + (PI if i == 1 or i == 2 else 0.0)
		_legs[i].rotation.x = sin(phase) * moving * 0.9

	if _head != null:
		var head_pitch := 0.0
		if behaviour in ["grazing", "browsing", "feeding", "rooting", "dabbling",
				"foraging"]:
			head_pitch = 0.85 + sin(_gait * 0.6) * 0.12
		elif state == State.ALERT:
			head_pitch = -0.18
		elif state == State.REST:
			head_pitch = 0.35
		_head.rotation.x = lerp_angle(_head.rotation.x, head_pitch, delta * 4.0)
		# When alert, the head tracks the player - that is the shot you want.
		var yaw_target := 0.0
		if _look_at_player > 0.01 and player != null:
			var to_player := player.global_position - global_position
			yaw_target = clampf(wrapf(atan2(to_player.x, to_player.z) - _yaw, -PI, PI),
				-1.1, 1.1)
			_look_at_player = maxf(0.0, _look_at_player - delta * 0.25)
		_head.rotation.y = lerp_angle(_head.rotation.y, yaw_target, delta * 3.0)

	if _tail != null:
		var flick: float = sin(_gait * 0.8) * 0.18
		if state == State.FLEE and species.shape in ["deer", "pronghorn"]:
			flick = 1.1                       # tail up, flagging
		_tail.rotation.x = lerp_angle(_tail.rotation.x, flick, delta * 6.0)

	for i in _wings.size():
		var flap: float = 0.0
		if species.can_fly and (state == State.FLEE or global_position.y
				- float(world.surface_height(global_position.x, global_position.z)) > 1.5):
			flap = sin(_gait * 2.2) * 1.1
		var side: float = 1.0 if i == 0 else -1.0
		_wings[i].rotation.z = lerp_angle(_wings[i].rotation.z, flap * side, delta * 10.0)


func _maybe_call(delta: float) -> void:
	if not AudioDirector.has_call(species.id):
		return
	_call_timer -= delta
	if _call_timer > 0.0:
		return
	_call_timer = _rng.randf_range(species.call_cooldown.x, species.call_cooldown.y)
	if _rng.randf() > species.call_chance:
		return
	if sky != null and not species.is_active_at(sky.time_of_day) and _rng.randf() > 0.25:
		return
	AudioDirector.play_call(species.id, global_position, -6.0)
	if player != null and player.global_position.distance_to(global_position) < 140.0:
		Codex.record_call(species.id)
		if behaviour in ["bugling", "howling", "calling"]:
			pass
		elif species.shape in ["elk", "canine"]:
			_set_state(state, "bugling" if species.shape == "elk" else "howling")


## Reports a sighting to the Discovery Book once the player has clearly seen it.
func _report_sighting() -> void:
	if _sighted_reported or player == null or sky == null:
		return
	var distance := player.global_position.distance_to(global_position)
	if distance > 90.0:
		return
	var cam := player.camera()
	if not cam.is_position_in_frustum(global_position + Vector3.UP * 0.4):
		return
	_sighted_reported = true
	Codex.record_sighting(species.id, global_position,
		world.biome_at(global_position.x, global_position.z), sky.time_of_day)
	Codex.record_behaviour(species.id, behaviour)


# --------------------------------------------------------------------- damage

func apply_hit(damage: float, point: Vector3, zone: String) -> void:
	if is_dead:
		return
	health -= damage
	if health <= 0.0:
		_die()
		return
	wounded = true
	awareness = 1.4
	_enter_flee()
	AudioDirector.play_call(species.id, global_position, -2.0)


func _die() -> void:
	is_dead = true
	health = 0.0
	_set_state(State.DEAD, "downed")
	_speed = 0.0
	# Roll onto its side where it stands.
	if _model != null:
		_model.rotation.z = PI * 0.5
		_model.position.y = species.shoulder_height * 0.35
	collision_layer = 1 << 2
	died.emit(self)


func harvest() -> Dictionary:
	var data := measurements.duplicate()
	data["species"] = species.id
	Codex.record_harvest(species.id, measurements)
	SaveSystem.bump_stat("harvests", 1.0)
	return data


# ------------------------------------------------------------------ interface

## Everything the photo scorer needs. Villagers implement the same contract.
func subject_info() -> Dictionary:
	return {
		"kind": "animal",
		"species": species.id,
		"name": species.name,
		"state": "downed" if is_dead else behaviour,
		"rarity": species.rarity,
		"value": species.photo_value,
		"position": global_position + Vector3(0.0, species.shoulder_height * 0.75, 0.0),
		"radius": maxf(species.body_length * 0.42, species.shoulder_height * 0.5),
		"forward": -global_transform.basis.z,
		"alert": state == State.ALERT or state == State.FLEE,
	}


func distance_to_player() -> float:
	return player.global_position.distance_to(global_position) if player != null else 999.0
