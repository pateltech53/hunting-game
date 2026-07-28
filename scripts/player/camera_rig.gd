class_name CameraRig
extends Node3D
## Yaw / pitch pivot carrying the one Camera3D the game uses. Switching to
## third person pulls the same camera back on a spring arm rather than swapping
## cameras, so lens settings, depth of field and the viewfinder all survive the
## toggle.

signal view_mode_changed(third_person: bool)

const FIRST_PERSON_OFFSET := Vector3(0.0, 0.0, 0.0)
const THIRD_PERSON_OFFSET := Vector3(0.62, 0.28, 0.0)
const THIRD_PERSON_DISTANCE := 3.6
const AIM_DISTANCE := 1.8

## Terrain plus props. Canopy and trunks are props: without them in the mask
## the camera happily parks itself inside a fir and the player sees leaves.
const ARM_MASK := 1 | (1 << 3)

var yaw := 0.0
var pitch := 0.0
var pitch_limit := deg_to_rad(88.0)
var third_person := false
var aiming := false

var camera: Camera3D
var pitch_pivot: Node3D
var arm: SpringArm3D
## SpringArm3D repositions its *direct* children every frame. The camera hangs
## off this holder instead, so bob and shake can be written to the camera's own
## transform without cancelling the pull-back.
var arm_socket: Node3D

var _bob_time := 0.0
var _bob_amount := 0.0
var _shake := 0.0
var _shake_seed := 0.0
var _sway := Vector2.ZERO
var _target_distance := 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	pitch_pivot = Node3D.new()
	pitch_pivot.name = "Pitch"
	add_child(pitch_pivot)

	arm = SpringArm3D.new()
	arm.name = "Arm"
	arm.spring_length = 0.0
	arm.margin = 0.42
	arm.collision_mask = ARM_MASK
	pitch_pivot.add_child(arm)

	arm_socket = Node3D.new()
	arm_socket.name = "Socket"
	arm.add_child(arm_socket)

	camera = Camera3D.new()
	camera.name = "Camera"
	camera.fov = Settings.fov
	camera.near = 0.05
	camera.far = 900.0
	camera.current = true
	arm_socket.add_child(camera)
	_rng.randomize()


func apply_look(delta_x: float, delta_y: float) -> void:
	var sensitivity := Settings.look_sensitivity()
	yaw -= delta_x * sensitivity
	var dy := delta_y * sensitivity
	pitch -= -dy if Settings.invert_y else dy
	pitch = clampf(pitch, -pitch_limit, pitch_limit)
	yaw = wrapf(yaw, -PI, PI)


func set_third_person(enabled: bool) -> void:
	if third_person == enabled:
		return
	third_person = enabled
	view_mode_changed.emit(third_person)


func toggle_view() -> void:
	set_third_person(not third_person)


func set_aiming(value: bool) -> void:
	aiming = value


## Called by the player each frame with its planar speed, to drive head bob.
func set_bob(speed_ratio: float) -> void:
	_bob_amount = clampf(speed_ratio, 0.0, 1.6)


func add_shake(amount: float) -> void:
	_shake = minf(_shake + amount, 1.4)
	_shake_seed = _rng.randf() * 100.0


func _process(delta: float) -> void:
	rotation.y = yaw
	pitch_pivot.rotation.x = pitch

	# Third person tucks in while aiming so the viewfinder still reads.
	var want_distance := 0.0
	var want_offset := FIRST_PERSON_OFFSET
	if third_person:
		want_distance = AIM_DISTANCE if aiming else THIRD_PERSON_DISTANCE
		want_offset = THIRD_PERSON_OFFSET
	_target_distance = lerpf(_target_distance, want_distance, 1.0 - pow(0.001, delta))
	arm.spring_length = _target_distance
	arm.position = arm.position.lerp(want_offset, 1.0 - pow(0.004, delta))

	# Head bob. Damped hard while aiming - you brace the camera.
	_bob_time += delta * (7.0 + _bob_amount * 4.0)
	var bob_scale: float = _bob_amount * (0.12 if aiming else 1.0)
	var bob := Vector3(
		sin(_bob_time * 0.5) * 0.022 * bob_scale,
		absf(sin(_bob_time)) * 0.030 * bob_scale,
		0.0)

	# Breathing sway: always present, worse when tired, better when crouched.
	_sway.x = sin(_bob_time * 0.31) * 0.0016
	_sway.y = cos(_bob_time * 0.23) * 0.0013
	var sway_scale: float = 1.0 if aiming else 0.35

	var shake := Vector3.ZERO
	if _shake > 0.001:
		shake = Vector3(
			sin((_bob_time + _shake_seed) * 41.0), cos((_bob_time + _shake_seed) * 37.0),
			0.0) * _shake * 0.05
		_shake = maxf(0.0, _shake - delta * 3.2)

	camera.position = bob + shake
	camera.rotation = Vector3(_sway.y * sway_scale + shake.y * 0.6,
		_sway.x * sway_scale + shake.x * 0.6, 0.0)


func forward() -> Vector3:
	return -global_transform.basis.z


func aim_origin() -> Vector3:
	return camera.global_position


func aim_direction() -> Vector3:
	return -camera.global_transform.basis.z
