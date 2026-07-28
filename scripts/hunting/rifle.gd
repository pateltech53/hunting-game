class_name Rifle
extends Node
## The other tool on your back. Bolt action, five rounds, real bullet drop, and
## hit zones that decide whether an animal drops or runs wounded.
##
## The Discovery Book only ever records a species from a photograph, so the
## rifle is what you do after the picture, not instead of it.

signal fired(from: Vector3, to: Vector3)
signal ammo_changed(in_magazine: int, reserve: int)
signal hit_reported(text: String)
signal aimed_changed(aimed: bool)

const MUZZLE_VELOCITY := 830.0
const GRAVITY := 9.81
const MAX_RANGE := 480.0
const STEP := 8.0
const HIT_MASK := 1 | (1 << 2) | (1 << 3)
const MAGAZINE := 5

var player: Player
var world: VoxelWorld
var wildlife: WildlifeDirector
var active := false

var in_magazine := MAGAZINE
var reserve := 25
var zeroed_at := 150.0          ## metres the sights are zeroed for
## Shouldering the rifle is its own key, separate from raising the camera, so
## the two tools never fight over one button.
var aimed := false

var _cycle := 0.0
var _reloading := 0.0
var _flash: OmniLight3D
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	_flash = OmniLight3D.new()
	_flash.light_color = Color(1.0, 0.86, 0.62)
	_flash.light_energy = 0.0
	_flash.omni_range = 14.0
	_flash.shadow_enabled = false
	add_child(_flash)


func setup(p: Player, voxel_world: VoxelWorld, director: WildlifeDirector) -> void:
	player = p
	world = voxel_world
	wildlife = director


func set_active(value: bool) -> void:
	active = value
	if not active:
		set_aimed(false)


func _process(delta: float) -> void:
	_cycle = maxf(0.0, _cycle - delta)
	if _reloading > 0.0:
		_reloading = maxf(0.0, _reloading - delta)
		if _reloading == 0.0:
			_finish_reload()
	if _flash.light_energy > 0.0:
		_flash.light_energy = maxf(0.0, _flash.light_energy - delta * 26.0)
	if not active or player == null or Game.is_paused:
		if aimed:
			set_aimed(false)
		return
	set_aimed(Input.is_action_pressed("aim_rifle"))
	# Firing from the hip is not a thing here: shoulder it first.
	if aimed and Input.is_action_just_pressed("capture") \
			and _cycle <= 0.0 and _reloading <= 0.0:
		fire()
	if Input.is_action_just_pressed("reload"):
		reload()


func set_aimed(value: bool) -> void:
	if aimed == value:
		return
	aimed = value
	if player != null:
		player.rig.set_aiming(aimed)
	if aimed:
		AudioDirector.play("rifle_cycle", -22.0, 1.7)
	aimed_changed.emit(aimed)


func fire() -> void:
	if in_magazine <= 0:
		AudioDirector.play("rifle_cycle", -12.0, 1.4)
		hit_reported.emit("Empty. Press T to reload.")
		return
	in_magazine -= 1
	_cycle = 1.1
	ammo_changed.emit(in_magazine, reserve)
	SaveSystem.bump_stat("shots_fired", 1.0)

	var cam := player.camera()
	var origin := cam.global_position
	var direction := -cam.global_transform.basis.z
	# Sights are zeroed, so aim high at long range and the drop works for you.
	var drop_at_zero := 0.5 * GRAVITY * pow(zeroed_at / MUZZLE_VELOCITY, 2.0)
	direction = (direction * zeroed_at + Vector3.UP * drop_at_zero).normalized()
	# A little dispersion from stance and breathing.
	var spread := 0.0016
	if player.crouched:
		spread *= 0.5
	if Vector2(player.velocity.x, player.velocity.z).length() > 1.0:
		spread *= 3.0
	direction = (direction + Vector3(_rng.randf_range(-spread, spread),
		_rng.randf_range(-spread, spread), _rng.randf_range(-spread, spread))).normalized()

	AudioDirector.play("rifle", 0.0, _rng.randf_range(0.97, 1.03))
	player.rig.add_shake(1.0)
	_flash.global_position = origin + direction * 0.6
	_flash.light_energy = 6.0
	_spook(origin, 220.0)

	var result := _trace(origin, direction)
	fired.emit(origin, result.get("end", origin + direction * MAX_RANGE))
	if result.has("collider"):
		_resolve_hit(result)
	else:
		hit_reported.emit("Miss.")

	# Work the bolt.
	await get_tree().create_timer(0.45).timeout
	if in_magazine > 0:
		AudioDirector.play("rifle_cycle", -14.0)


## Steps the bullet through the world under gravity so range actually matters.
func _trace(origin: Vector3, direction: Vector3) -> Dictionary:
	var space := player.get_world_3d().direct_space_state
	var pos := origin
	var velocity := direction * MUZZLE_VELOCITY
	var travelled := 0.0
	var exclude: Array[RID] = [player.get_rid()]
	while travelled < MAX_RANGE:
		var dt := STEP / MUZZLE_VELOCITY
		var next := pos + velocity * dt
		velocity.y -= GRAVITY * dt
		var params := PhysicsRayQueryParameters3D.create(pos, next)
		params.collision_mask = HIT_MASK
		params.exclude = exclude
		var hit := space.intersect_ray(params)
		if not hit.is_empty():
			hit["distance"] = origin.distance_to(hit["position"])
			hit["end"] = hit["position"]
			return hit
		pos = next
		travelled += STEP
	return {"end": pos}


func _resolve_hit(hit: Dictionary) -> void:
	var collider: Object = hit["collider"]
	var point: Vector3 = hit["position"]
	var distance: float = hit["distance"]
	if not (collider is Animal):
		AudioDirector.play_3d("step_gravel_0", point, -6.0, 0.7)
		hit_reported.emit("Impact at %d m." % int(distance))
		return

	var animal: Animal = collider
	var local_y := point.y - animal.global_position.y
	var shoulder := animal.species.shoulder_height
	var zone := "body"
	var damage := 55.0
	if local_y > shoulder * 0.95:
		zone = "head"
		damage = 200.0
	elif local_y > shoulder * 0.55:
		zone = "vitals"
		damage = 120.0
	elif local_y < shoulder * 0.3:
		zone = "leg"
		damage = 32.0
	# Energy falls off with range.
	damage *= clampf(1.0 - distance / (MAX_RANGE * 1.6), 0.35, 1.0)

	animal.apply_hit(damage, point, zone)
	if animal.is_dead:
		hit_reported.emit("%s down - %s shot at %d m." % [animal.species.name, zone,
			int(distance)])
		Game.notify("%s down. Approach and press F to record it." % animal.species.name,
			"hunt")
	else:
		hit_reported.emit("%s hit in the %s and running." % [animal.species.name, zone])
		Game.notify("Wounded. Follow the trail.", "warn")


func _spook(origin: Vector3, radius: float) -> void:
	if wildlife == null:
		return
	for animal: Animal in wildlife.active_animals():
		if animal.is_dead:
			continue
		if origin.distance_to(animal.global_position) < radius:
			animal.alarm()


func reload() -> void:
	if _reloading > 0.0 or in_magazine >= MAGAZINE or reserve <= 0:
		return
	_reloading = 2.1
	AudioDirector.play("rifle_cycle", -8.0, 0.9)


func _finish_reload() -> void:
	var needed := MAGAZINE - in_magazine
	var taken := mini(needed, reserve)
	in_magazine += taken
	reserve -= taken
	ammo_changed.emit(in_magazine, reserve)
	AudioDirector.play("rifle_cycle", -10.0, 1.1)


func is_reloading() -> bool:
	return _reloading > 0.0


## Where the bullet would land at the point the player is aiming, so the HUD
## can show a real holdover mark.
func predicted_drop(distance: float) -> float:
	var t := distance / MUZZLE_VELOCITY
	var t_zero := zeroed_at / MUZZLE_VELOCITY
	return 0.5 * GRAVITY * (t * t) - (distance / zeroed_at) * 0.5 * GRAVITY * (t_zero * t_zero)


func range_to_target() -> float:
	if player == null:
		return 0.0
	var cam := player.camera()
	var space := player.get_world_3d().direct_space_state
	var params := PhysicsRayQueryParameters3D.create(cam.global_position,
		cam.global_position - cam.global_transform.basis.z * MAX_RANGE)
	params.collision_mask = HIT_MASK
	params.exclude = [player.get_rid()]
	var hit := space.intersect_ray(params)
	if hit.is_empty():
		return 0.0
	return cam.global_position.distance_to(hit["position"])
