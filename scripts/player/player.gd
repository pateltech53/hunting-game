class_name Player
extends CharacterBody3D
## The hunter. Movement, stance, noise and scent - the three things wildlife
## actually reacts to - plus the rig that carries the camera and the rifle.

signal tool_changed(tool_id: String)
signal stance_changed(crouched: bool)
signal stamina_changed(value: float)

enum Tool { CAMERA, RIFLE }

const WALK_SPEED := 4.1
const SPRINT_SPEED := 7.4
const CROUCH_SPEED := 1.7
const AIM_SPEED := 2.4
const ACCEL := 11.0
const AIR_ACCEL := 2.5
const JUMP_VELOCITY := 7.4
const STAND_HEIGHT := 1.78
const CROUCH_HEIGHT := 1.05

var world: VoxelWorld
var sky: SkySystem
var weather: WeatherSystem

var rig: CameraRig
var photo_camera: Node          ## PhotoCamera
var rifle: Node                 ## Rifle
var current_tool: Tool = Tool.CAMERA

var crouched := false
var sprinting := false
var stamina := 1.0
var touch_move := Vector2.ZERO
var touch_look := Vector2.ZERO
var input_enabled := true

var _collider: CollisionShape3D
var _capsule: CapsuleShape3D
var _model: Node3D
var _step_distance := 0.0
var _last_position := Vector3.ZERO
var _current_biome := "emerald_vale"
var _noise := 0.0
var _rng := RandomNumberGenerator.new()
var _model_yaw := 0.0


func _ready() -> void:
	collision_layer = 1 << 1
	collision_mask = 1
	_rng.randomize()

	_capsule = CapsuleShape3D.new()
	_capsule.radius = 0.34
	_capsule.height = STAND_HEIGHT
	_collider = CollisionShape3D.new()
	_collider.shape = _capsule
	_collider.position = Vector3(0.0, STAND_HEIGHT * 0.5, 0.0)
	add_child(_collider)

	rig = CameraRig.new()
	rig.name = "Rig"
	rig.position = Vector3(0.0, STAND_HEIGHT - 0.18, 0.0)
	add_child(rig)
	rig.view_mode_changed.connect(_on_view_mode_changed)

	_build_model()
	_last_position = global_position


func _build_model() -> void:
	_model = VoxelBody.build_humanoid({
		"skin": Color(0.76, 0.58, 0.44),
		"shirt": Color(0.30, 0.34, 0.27),
		"trousers": Color(0.26, 0.24, 0.21),
		"hair": Color(0.24, 0.19, 0.14),
		"hat": Color(0.32, 0.28, 0.20, 1.0),
		"pack": Color(0.38, 0.31, 0.21),
		"has_pack": true,
	}, STAND_HEIGHT)
	_model.name = "HunterModel"
	_model.visible = false
	add_child(_model)


func attach_systems(voxel_world: VoxelWorld, sky_system: SkySystem,
		weather_system: WeatherSystem) -> void:
	world = voxel_world
	sky = sky_system
	weather = weather_system


func _on_view_mode_changed(third_person: bool) -> void:
	if _model != null:
		_model.visible = third_person
	AudioDirector.play("ui_move", -14.0)


func _unhandled_input(event: InputEvent) -> void:
	if not input_enabled or Game.is_paused:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rig.apply_look(event.relative.x, event.relative.y)


func _physics_process(delta: float) -> void:
	if not input_enabled:
		velocity.x = 0.0
		velocity.z = 0.0
		if not is_on_floor():
			velocity.y -= _gravity() * delta
		move_and_slide()
		_clamp_to_terrain()
		return

	_handle_look_stick(delta)
	_handle_stance(delta)

	var input_dir := _movement_input()
	var basis := Basis(Vector3.UP, rig.yaw)
	var direction := (basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()

	var aiming: bool = photo_camera != null and photo_camera.get("raised")
	var target_speed := WALK_SPEED
	if crouched:
		target_speed = CROUCH_SPEED
	elif aiming:
		target_speed = AIM_SPEED
	elif sprinting and stamina > 0.02 and input_dir.length() > 0.1:
		target_speed = SPRINT_SPEED

	var accel: float = ACCEL if is_on_floor() else AIR_ACCEL
	var target := direction * target_speed
	velocity.x = move_toward(velocity.x, target.x, accel * delta * 3.0)
	velocity.z = move_toward(velocity.z, target.z, accel * delta * 3.0)

	if is_on_floor():
		if Input.is_action_just_pressed("jump") and not crouched:
			velocity.y = JUMP_VELOCITY
			stamina = maxf(0.0, stamina - 0.08)
	else:
		velocity.y -= _gravity() * delta

	move_and_slide()
	_clamp_to_terrain()
	_update_stamina(delta, target_speed)
	_update_noise(delta, target_speed)
	_update_footsteps()
	_update_model(delta, direction)

	rig.set_bob(Vector2(velocity.x, velocity.z).length() / SPRINT_SPEED)
	SaveSystem.bump_stat("distance_walked", global_position.distance_to(_last_position))
	_last_position = global_position

	if world != null:
		_current_biome = world.biome_at(global_position.x, global_position.z)


func _gravity() -> float:
	return float(ProjectSettings.get_setting("physics/3d/default_gravity", 22.0))


## Safety net against falling through the world.
##
## Chunk collision only exists near the player, so anything that moves you
## faster than the streamer can keep up - a sandbox teleport, a long fall past
## the load radius - would otherwise drop you out of the level. The terrain
## height field is a pure function of the seed and is always available, so we
## can always tell where the ground is even when nothing has been meshed yet.
func _clamp_to_terrain() -> void:
	if world == null:
		return
	var ground := float(world.surface_height(global_position.x, global_position.z))
	if global_position.y < ground:
		global_position.y = ground
		if velocity.y < 0.0:
			velocity.y = 0.0


func _movement_input() -> Vector2:
	var dir := Vector2.ZERO
	if Settings.scheme == Settings.Scheme.TOUCH:
		dir = touch_move
	else:
		dir = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	return dir.limit_length(1.0)


func _handle_look_stick(delta: float) -> void:
	if touch_look != Vector2.ZERO:
		rig.apply_look(touch_look.x, touch_look.y)
		touch_look = Vector2.ZERO
	# Right stick on a gamepad.
	var stick := Vector2(
		Input.get_joy_axis(0, JOY_AXIS_RIGHT_X),
		Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y))
	if stick.length() > 0.14:
		var scale := Settings.gamepad_sensitivity * 220.0 * delta
		rig.apply_look(stick.x * scale, stick.y * scale)


func _handle_stance(delta: float) -> void:
	sprinting = Input.is_action_pressed("sprint")
	var want_crouch := Input.is_action_pressed("crouch")
	if want_crouch != crouched:
		crouched = want_crouch
		stance_changed.emit(crouched)
	var target_height: float = CROUCH_HEIGHT if crouched else STAND_HEIGHT
	_capsule.height = move_toward(_capsule.height, target_height, delta * 4.0)
	_collider.position.y = _capsule.height * 0.5
	rig.position.y = _capsule.height - 0.18


func _update_stamina(delta: float, speed: float) -> void:
	var before := stamina
	if sprinting and speed >= SPRINT_SPEED - 0.01 and Vector2(velocity.x, velocity.z).length() > 2.0:
		stamina = maxf(0.0, stamina - delta * 0.16)
	else:
		var rate: float = 0.30 if crouched else 0.16
		stamina = minf(1.0, stamina + delta * rate)
	if absf(stamina - before) > 0.001:
		stamina_changed.emit(stamina)


## What the wildlife can hear. Crouching is the difference between getting
## close and watching a white tail disappear into the trees.
func _update_noise(delta: float, speed: float) -> void:
	var planar := Vector2(velocity.x, velocity.z).length()
	var target := 0.0
	if planar > 0.2:
		target = clampf(planar / SPRINT_SPEED, 0.15, 1.0)
		if crouched:
			target *= 0.32
		elif speed >= SPRINT_SPEED - 0.01:
			target *= 1.35
	var surface := _surface()
	if surface == "gravel":
		target *= 1.25
	elif surface == "water":
		target *= 1.45
	elif surface == "snow":
		target *= 0.75
	# Rain masks your approach.
	if weather != null:
		target *= lerpf(1.0, 0.6, weather.precipitation())
	_noise = move_toward(_noise, clampf(target, 0.0, 1.6), delta * 3.0)


func noise_level() -> float:
	return _noise


func _surface() -> String:
	if world == null:
		return "grass"
	if world.is_water_at(global_position.x, global_position.z):
		return "water"
	var biome := BiomeLibrary.get_biome(_current_biome)
	return biome.footstep_surface


func _update_footsteps() -> void:
	var planar := Vector2(velocity.x, velocity.z).length()
	if not is_on_floor() or planar < 0.4:
		return
	_step_distance += planar * get_physics_process_delta_time()
	var stride: float = 2.4 if planar > 5.0 else 1.9
	if crouched:
		stride = 1.3
	if _step_distance < stride:
		return
	_step_distance = 0.0
	var volume: float = -16.0 if crouched else -9.0
	AudioDirector.play_variant("step_%s" % _surface(), 3, global_position, volume, 0.12)


func _update_model(delta: float, direction: Vector3) -> void:
	if _model == null or not _model.visible:
		return
	# The body turns toward movement; the head follows the camera.
	if direction.length() > 0.1:
		_model_yaw = atan2(direction.x, direction.z)
	else:
		_model_yaw = lerp_angle(_model_yaw, rig.yaw + PI, delta * 4.0)
	_model.rotation.y = lerp_angle(_model.rotation.y, _model_yaw, delta * 9.0)
	var head := _model.get_node_or_null("Head")
	if head != null:
		head.rotation.x = clampf(rig.pitch, -0.8, 0.8)
	var swing := sin(Time.get_ticks_msec() * 0.006 * maxf(1.0,
		Vector2(velocity.x, velocity.z).length())) * clampf(
		Vector2(velocity.x, velocity.z).length() / WALK_SPEED, 0.0, 1.2)
	for pair: Array in [["LegL", 1.0], ["LegR", -1.0], ["ArmL", -1.0], ["ArmR", 1.0]]:
		var node: Node3D = _model.get_node_or_null(pair[0])
		if node != null:
			node.rotation.x = swing * 0.6 * float(pair[1])


# ------------------------------------------------------------------ interface

func camera() -> Camera3D:
	return rig.camera


func head_position() -> Vector3:
	return global_position + Vector3(0.0, _capsule.height - 0.18, 0.0)


func eye_position() -> Vector3:
	return rig.camera.global_position


func current_biome() -> String:
	return _current_biome


## Resolves the biome immediately instead of waiting for the next physics tick.
## Needed right after a spawn or a teleport, when anything that reads the biome
## would otherwise get a stale answer.
func refresh_biome() -> void:
	if world != null:
		_current_biome = world.biome_at(global_position.x, global_position.z)


func is_third_person() -> bool:
	return rig.third_person


func set_tool(t: Tool) -> void:
	if current_tool == t:
		return
	current_tool = t
	if photo_camera != null:
		photo_camera.set_active(t == Tool.CAMERA)
	if rifle != null:
		rifle.set_active(t == Tool.RIFLE)
	tool_changed.emit("camera" if t == Tool.CAMERA else "rifle")
	AudioDirector.play("lens", -8.0)


func toggle_tool() -> void:
	set_tool(Tool.RIFLE if current_tool == Tool.CAMERA else Tool.CAMERA)


func teleport(to: Vector3) -> void:
	global_position = to
	velocity = Vector3.ZERO
	_last_position = to
	refresh_biome()


## Scent carries downwind. Returns how strongly an animal at [param from]
## would smell the player, 0..1.
func scent_strength_at(from: Vector3, wind_dir: Vector3, wind_power: float) -> float:
	var to_animal := from - global_position
	var distance := to_animal.length()
	if distance < 0.5:
		return 1.0
	var alignment := to_animal.normalized().dot(wind_dir.normalized())
	if alignment <= 0.0:
		return 0.0                       # the animal is upwind, it smells nothing
	var reach: float = lerpf(18.0, 1.0, clampf(distance / 120.0, 0.0, 1.0))
	return clampf(alignment * reach * (0.4 + wind_power * 0.8) / 18.0, 0.0, 1.0)
