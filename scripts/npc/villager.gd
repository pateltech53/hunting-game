class_name Villager
extends CharacterBody3D
## A person in a village. They make the street, portrait, group and wedding
## genres possible - and unlike the wildlife, they will look at the camera.

const FIRST_NAMES := ["Ada", "Bren", "Corin", "Della", "Eamon", "Fen", "Greta", "Hal",
	"Ines", "Jory", "Kit", "Lune", "Mabel", "Nis", "Orla", "Pell", "Quen", "Rook",
	"Sable", "Tam", "Vesna", "Wren"]
const TRADES := ["woodcutter", "trapper", "baker", "smith", "fisher", "herbalist",
	"shepherd", "cooper", "innkeeper", "fiddler"]

var role := "villager"           ## villager | bride | groom | guest | officiant
var village_key := ""            ## which settlement this person belongs to
var person_name := ""
var trade := ""
var world: VoxelWorld
var player: Player
var anchor := Vector3.ZERO
var wander_radius := 16.0

var _model: Node3D
var _head: Node3D
var _limbs: Dictionary = {}
var _target := Vector3.ZERO
var _speed := 0.0
var _yaw := 0.0
var _gait := 0.0
var _timer := 0.0
var _posing := 0.0
var _state := "walking"
var _rng := RandomNumberGenerator.new()


func setup(spawn: Vector3, voxel_world: VoxelWorld, hunter: Player, new_role: String,
		seed_value: int) -> void:
	world = voxel_world
	player = hunter
	role = new_role
	_rng.seed = seed_value
	anchor = spawn
	global_position = spawn
	_target = spawn
	_yaw = _rng.randf_range(-PI, PI)
	rotation.y = _yaw

	person_name = FIRST_NAMES[_rng.randi_range(0, FIRST_NAMES.size() - 1)]
	trade = TRADES[_rng.randi_range(0, TRADES.size() - 1)]

	collision_layer = 1 << 4
	collision_mask = 0
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.3
	capsule.height = 1.7
	var cs := CollisionShape3D.new()
	cs.shape = capsule
	cs.position = Vector3(0.0, 0.85, 0.0)
	add_child(cs)

	_model = VoxelBody.build_humanoid(_palette(), 1.72)
	add_child(_model)
	_head = _model.get_node_or_null("Head")
	for limb: String in ["ArmL", "ArmR", "LegL", "LegR"]:
		var node: Node3D = _model.get_node_or_null(limb)
		if node != null:
			_limbs[limb] = node
	_pick_target()


func _palette() -> Dictionary:
	var skins := [Color(0.86, 0.70, 0.55), Color(0.70, 0.52, 0.38), Color(0.48, 0.33, 0.23),
		Color(0.36, 0.24, 0.17), Color(0.92, 0.80, 0.68)]
	var shirts := [Color(0.32, 0.40, 0.30), Color(0.44, 0.28, 0.24), Color(0.26, 0.32, 0.44),
		Color(0.52, 0.44, 0.24), Color(0.36, 0.30, 0.38)]
	var hairs := [Color(0.20, 0.15, 0.11), Color(0.35, 0.22, 0.12), Color(0.62, 0.52, 0.32),
		Color(0.72, 0.70, 0.68), Color(0.12, 0.10, 0.10)]
	var p := {
		"skin": skins[_rng.randi_range(0, skins.size() - 1)],
		"shirt": shirts[_rng.randi_range(0, shirts.size() - 1)],
		"trousers": Color(0.26, 0.24, 0.22),
		"hair": hairs[_rng.randi_range(0, hairs.size() - 1)],
		"hat": Color(0, 0, 0, 0),
		"has_pack": _rng.randf() < 0.25,
	}
	match role:
		"bride":
			p["shirt"] = Color(0.96, 0.95, 0.93)
			p["trousers"] = Color(0.94, 0.93, 0.90)
		"groom":
			p["shirt"] = Color(0.20, 0.21, 0.26)
			p["trousers"] = Color(0.17, 0.18, 0.22)
			p["hat"] = Color(0.14, 0.14, 0.18, 1.0)
		"officiant":
			p["shirt"] = Color(0.30, 0.26, 0.36)
		"guest":
			p["hat"] = Color(0.55, 0.42, 0.30, 1.0) if _rng.randf() < 0.4 \
				else Color(0, 0, 0, 0)
		_:
			if _rng.randf() < 0.35:
				p["hat"] = Color(0.42, 0.34, 0.22, 1.0)
	return p


func _physics_process(delta: float) -> void:
	_timer -= delta
	_update_posing(delta)

	if _posing > 0.0:
		_speed = move_toward(_speed, 0.0, delta * 8.0)
	else:
		if _timer <= 0.0:
			_pick_target()
		var to_target := _target - global_position
		to_target.y = 0.0
		if to_target.length() < 1.0:
			_speed = move_toward(_speed, 0.0, delta * 4.0)
			if _state != "standing":
				_state = "standing"
		else:
			_speed = move_toward(_speed, 1.35, delta * 3.0)
			_state = "walking"
			_yaw = rotate_toward(_yaw, atan2(to_target.x, to_target.z), delta * 3.2)

	var forward := Vector3(sin(_yaw), 0.0, cos(_yaw))
	var next := global_position + forward * _speed * delta
	var ground := float(world.surface_height(next.x, next.z)) if world != null \
		else global_position.y
	global_position = Vector3(next.x, lerpf(global_position.y, ground,
		1.0 - pow(0.001, delta)), next.z)
	rotation.y = _yaw
	_animate(delta)


## Villagers notice a raised camera and hold still for it. Wildlife does not.
func _update_posing(delta: float) -> void:
	_posing = maxf(0.0, _posing - delta)
	if player == null or player.photo_camera == null:
		return
	if not player.photo_camera.get("raised"):
		return
	var distance := player.global_position.distance_to(global_position)
	if distance > 22.0:
		return
	var cam := player.camera()
	if not cam.is_position_in_frustum(global_position + Vector3.UP):
		return
	_posing = 1.5
	_state = "posing"
	var to_player := player.global_position - global_position
	_yaw = rotate_toward(_yaw, atan2(to_player.x, to_player.z), delta * 4.0)


func _pick_target() -> void:
	if role in ["bride", "groom", "officiant"]:
		_target = anchor
		_timer = 6.0
		return
	var angle := _rng.randf_range(-PI, PI)
	var radius := _rng.randf_range(2.0, wander_radius)
	_target = anchor + Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
	_timer = _rng.randf_range(4.0, 12.0)


func _animate(delta: float) -> void:
	_gait += delta * (2.0 + _speed * 6.0)
	var swing: float = sin(_gait) * clampf(_speed / 1.4, 0.0, 1.0) * 0.7
	for pair: Array in [["LegL", 1.0], ["LegR", -1.0], ["ArmL", -1.0], ["ArmR", 1.0]]:
		var node: Node3D = _limbs.get(pair[0], null)
		if node != null:
			node.rotation.x = swing * float(pair[1])
	if _head != null and player != null:
		var want := 0.0
		if _posing > 0.0:
			var to_player := player.global_position - global_position
			want = clampf(wrapf(atan2(to_player.x, to_player.z) - _yaw, -PI, PI), -1.0, 1.0)
		_head.rotation.y = lerp_angle(_head.rotation.y, want, delta * 5.0)


func subject_info() -> Dictionary:
	return {
		"kind": "person",
		"species": "",
		"name": "%s the %s" % [person_name, trade] if role == "villager" else \
			"%s (%s)" % [person_name, role],
		"state": _state,
		"rarity": 0.35 if role in ["bride", "groom"] else 0.05,
		"value": 45 if role in ["bride", "groom"] else 25,
		"position": global_position + Vector3(0.0, 1.45, 0.0),
		"radius": 0.62,
		"forward": -global_transform.basis.z,
		"alert": false,
	}
