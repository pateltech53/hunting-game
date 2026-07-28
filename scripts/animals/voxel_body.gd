class_name VoxelBody
extends RefCounted
## Builds every creature in the game out of voxels, as a small rig of named
## parts so the AI can animate a walk cycle, turn a head toward the camera and
## flick an ear without any imported animation data.
##
## Models are built at 1 voxel = 0.1 m and then scaled to the species' real
## shoulder height. Everything faces -Z, matching Godot's forward.

const VOXEL := 0.1

## Per-shape proportions, in voxels.
const SHAPES := {
	"deer": {"body_len": 17, "body_h": 8, "body_w": 7, "leg_len": 8, "leg_thick": 2,
		"neck_len": 6, "neck_rise": 5, "head_len": 5, "head_h": 4, "head_w": 4,
		"ear": 2, "tail_len": 3, "tail_w": 2, "tail_up": true, "snout": 2,
		"antler": "branch", "hump": 0},
	"elk": {"body_len": 21, "body_h": 10, "body_w": 9, "leg_len": 10, "leg_thick": 3,
		"neck_len": 7, "neck_rise": 6, "head_len": 6, "head_h": 5, "head_w": 4,
		"ear": 2, "tail_len": 3, "tail_w": 2, "tail_up": false, "snout": 3,
		"antler": "branch_big", "hump": 1, "mane": true},
	"moose": {"body_len": 26, "body_h": 13, "body_w": 11, "leg_len": 15, "leg_thick": 3,
		"neck_len": 6, "neck_rise": 4, "head_len": 8, "head_h": 5, "head_w": 5,
		"ear": 3, "tail_len": 2, "tail_w": 2, "tail_up": false, "snout": 4,
		"antler": "palm", "hump": 3, "dewlap": true},
	"canine": {"body_len": 15, "body_h": 7, "body_w": 6, "leg_len": 6, "leg_thick": 2,
		"neck_len": 3, "neck_rise": 2, "head_len": 5, "head_h": 4, "head_w": 4,
		"ear": 2, "tail_len": 7, "tail_w": 2, "tail_up": false, "snout": 3,
		"antler": "none", "hump": 0},
	"fox": {"body_len": 11, "body_h": 5, "body_w": 4, "leg_len": 4, "leg_thick": 1,
		"neck_len": 2, "neck_rise": 1, "head_len": 4, "head_h": 3, "head_w": 3,
		"ear": 3, "tail_len": 8, "tail_w": 3, "tail_up": false, "snout": 2,
		"antler": "none", "hump": 0},
	"bear": {"body_len": 18, "body_h": 11, "body_w": 10, "leg_len": 7, "leg_thick": 4,
		"neck_len": 2, "neck_rise": 1, "head_len": 5, "head_h": 5, "head_w": 5,
		"ear": 2, "tail_len": 1, "tail_w": 2, "tail_up": false, "snout": 2,
		"antler": "none", "hump": 3},
	"boar": {"body_len": 14, "body_h": 8, "body_w": 7, "leg_len": 4, "leg_thick": 2,
		"neck_len": 1, "neck_rise": 0, "head_len": 6, "head_h": 4, "head_w": 4,
		"ear": 2, "tail_len": 3, "tail_w": 1, "tail_up": false, "snout": 3,
		"antler": "tusk", "hump": 2},
	"hare": {"body_len": 6, "body_h": 4, "body_w": 3, "leg_len": 2, "leg_thick": 1,
		"neck_len": 1, "neck_rise": 1, "head_len": 3, "head_h": 3, "head_w": 3,
		"ear": 5, "tail_len": 1, "tail_w": 2, "tail_up": true, "snout": 1,
		"antler": "none", "hump": 0},
	"ram": {"body_len": 15, "body_h": 9, "body_w": 7, "leg_len": 7, "leg_thick": 2,
		"neck_len": 3, "neck_rise": 3, "head_len": 4, "head_h": 4, "head_w": 4,
		"ear": 2, "tail_len": 2, "tail_w": 2, "tail_up": false, "snout": 2,
		"antler": "curl", "hump": 1},
	"pronghorn": {"body_len": 13, "body_h": 7, "body_w": 5, "leg_len": 8, "leg_thick": 1,
		"neck_len": 5, "neck_rise": 4, "head_len": 4, "head_h": 3, "head_w": 3,
		"ear": 3, "tail_len": 2, "tail_w": 2, "tail_up": true, "snout": 2,
		"antler": "prong", "hump": 0},
	"cat": {"body_len": 10, "body_h": 5, "body_w": 4, "leg_len": 4, "leg_thick": 1,
		"neck_len": 2, "neck_rise": 1, "head_len": 3, "head_h": 3, "head_w": 4,
		"ear": 2, "tail_len": 3, "tail_w": 2, "tail_up": true, "snout": 1,
		"antler": "none", "hump": 0},
	"otter": {"body_len": 12, "body_h": 4, "body_w": 4, "leg_len": 2, "leg_thick": 1,
		"neck_len": 2, "neck_rise": 1, "head_len": 3, "head_h": 3, "head_w": 3,
		"ear": 1, "tail_len": 6, "tail_w": 2, "tail_up": false, "snout": 1,
		"antler": "none", "hump": 0},
}

const BIRD_SHAPES := {
	"owl": {"body_len": 5, "body_h": 6, "body_w": 5, "head": 4, "wing": 3, "tail": 3,
		"tufts": true, "beak": 1, "big_eyes": true},
	"corvid": {"body_len": 7, "body_h": 4, "body_w": 4, "head": 3, "wing": 4, "tail": 5,
		"tufts": false, "beak": 2, "big_eyes": false},
	"duck": {"body_len": 6, "body_h": 4, "body_w": 4, "head": 3, "wing": 3, "tail": 2,
		"tufts": false, "beak": 2, "big_eyes": false},
}

static var _cache: Dictionary = {}


static func _hash(x: int, y: int, z: int) -> float:
	var n: int = x * 73856093 + y * 19349663 + z * 83492791
	n = (n ^ (n >> 13)) * 1274126177
	return float(absi(n ^ (n >> 16)) % 1000) / 1000.0


## Fills an axis-aligned box of voxels with a slightly jittered colour.
static func box(voxels: Dictionary, from: Vector3i, to: Vector3i, color: Color,
		jitter: float = 0.05) -> void:
	for x in range(mini(from.x, to.x), maxi(from.x, to.x) + 1):
		for y in range(mini(from.y, to.y), maxi(from.y, to.y) + 1):
			for z in range(mini(from.z, to.z), maxi(from.z, to.z) + 1):
				var j := (_hash(x, y, z) - 0.5) * jitter * 2.0
				voxels[Vector3i(x, y, z)] = Color(
					clampf(color.r + j, 0.0, 1.0),
					clampf(color.g + j, 0.0, 1.0),
					clampf(color.b + j, 0.0, 1.0))


## Builds the rig for a species and returns its root. Children are named so
## the animal controller can find them: Body, Head, LegFL, LegFR, LegBL,
## LegBR, Tail.
static func build(species: Species) -> Node3D:
	var root := Node3D.new()
	root.name = "Model"
	var palette: Dictionary = species.palette
	var primary: Color = palette.get("primary", Color(0.5, 0.4, 0.3))
	var secondary: Color = palette.get("secondary", primary.lightened(0.15))
	var accent: Color = palette.get("accent", Color(0.9, 0.9, 0.85))
	var dark: Color = palette.get("dark", Color(0.12, 0.10, 0.09))

	if BIRD_SHAPES.has(species.shape):
		_build_bird(root, species, BIRD_SHAPES[species.shape], primary, secondary,
			accent, dark)
	else:
		var s: Dictionary = SHAPES.get(species.shape, SHAPES["deer"])
		_build_quadruped(root, species, s, primary, secondary, accent, dark)

	# Scale so the model's shoulder sits at the species' real height.
	var shape: Dictionary = SHAPES.get(species.shape, {})
	var model_height: float = float(int(shape.get("leg_len", 6)) + int(shape.get("body_h", 7))) \
		* VOXEL if not shape.is_empty() else species.shoulder_height
	var factor: float = species.shoulder_height / maxf(model_height, 0.01)
	root.scale = Vector3.ONE * factor
	return root


static func _mesh_node(voxels: Dictionary, node_name: String) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	var mesh := VoxelMesher.build_mesh(voxels, PropMeshes.MODEL_ORIGIN, true, VOXEL)
	# A part can end up with no visible faces; keep the node so the rig still
	# has the pivot, but give it a real (empty) mesh resource.
	mi.mesh = mesh if mesh != null else ArrayMesh.new()
	mi.material_override = PropMeshes.material()
	return mi


static func _build_quadruped(root: Node3D, species: Species, s: Dictionary,
		primary: Color, secondary: Color, accent: Color, dark: Color) -> void:
	var bl: int = s["body_len"]
	var bh: int = s["body_h"]
	var bw: int = s["body_w"]
	var leg: int = s["leg_len"]
	var lt: int = s["leg_thick"]
	var hw := bw / 2

	# --- torso ------------------------------------------------------------
	var body_voxels := {}
	var y0 := leg
	box(body_voxels, Vector3i(-hw, y0, -bl / 2), Vector3i(hw, y0 + bh - 1, bl / 2), primary)
	# Flanks and belly in the lighter tones.
	box(body_voxels, Vector3i(-hw, y0, -bl / 2), Vector3i(hw, y0 + 1, bl / 2),
		accent.lerp(secondary, 0.5))
	box(body_voxels, Vector3i(-hw, y0 + bh - 2, -bl / 2), Vector3i(hw, y0 + bh - 1, bl / 2),
		secondary)
	var hump: int = s.get("hump", 0)
	if hump > 0:
		box(body_voxels, Vector3i(-hw + 1, y0 + bh, -bl / 2 + 1),
			Vector3i(hw - 1, y0 + bh + hump - 1, -bl / 2 + 4), primary.darkened(0.05))
	if s.get("mane", false):
		box(body_voxels, Vector3i(-hw, y0 + bh - 1, -bl / 2), Vector3i(hw, y0 + bh + 1,
			-bl / 2 + 3), dark.lerp(primary, 0.35))
	var body := _mesh_node(body_voxels, "Body")
	root.add_child(body)

	# --- neck and head ----------------------------------------------------
	var neck_pivot := Node3D.new()
	neck_pivot.name = "Head"
	neck_pivot.position = Vector3(0.0, float(y0 + bh - 2) * VOXEL, float(-bl / 2 + 1) * VOXEL)
	root.add_child(neck_pivot)

	var head_voxels := {}
	var nl: int = s["neck_len"]
	var nr: int = s["neck_rise"]
	var nw: int = maxi(1, bw / 3)
	for i in nl:
		var t := float(i) / float(maxi(nl - 1, 1))
		var y := int(round(t * float(nr)))
		box(head_voxels, Vector3i(-nw, y, -i), Vector3i(nw, y + nw + 1, -i), primary)
	var hl: int = s["head_len"]
	var hh: int = s["head_h"]
	var hhw: int = s["head_w"] / 2
	var head_z := -nl
	var head_y := nr + 1
	box(head_voxels, Vector3i(-hhw, head_y, head_z - hl + 1), Vector3i(hhw, head_y + hh - 1,
		head_z), primary)
	# Muzzle.
	var snout: int = s.get("snout", 2)
	if snout > 0:
		box(head_voxels, Vector3i(-maxi(hhw - 1, 0), head_y, head_z - hl - snout + 1),
			Vector3i(maxi(hhw - 1, 0), head_y + maxi(hh - 2, 1), head_z - hl),
			secondary.lerp(dark, 0.25))
		box(head_voxels, Vector3i(-maxi(hhw - 1, 0), head_y, head_z - hl - snout),
			Vector3i(maxi(hhw - 1, 0), head_y, head_z - hl - snout), dark)
	# Eyes, with a highlight voxel. Portrait scoring looks for these.
	for side: int in [-1, 1]:
		head_voxels[Vector3i(side * hhw, head_y + hh - 2, head_z - hl + 2)] = dark
		head_voxels[Vector3i(side * hhw, head_y + hh - 1, head_z - hl + 2)] = \
			Color(0.95, 0.95, 0.98)
	# Ears.
	var ear: int = s.get("ear", 2)
	for side: int in [-1, 1]:
		box(head_voxels, Vector3i(side * hhw, head_y + hh, head_z - 1),
			Vector3i(side * hhw, head_y + hh + ear - 1, head_z), secondary)
	_add_headgear(head_voxels, species, s, head_y + hh, head_z - 1, hhw, dark, accent)
	neck_pivot.add_child(_mesh_node(head_voxels, "HeadMesh"))

	# --- legs -------------------------------------------------------------
	var leg_x := maxi(hw - lt + 1, 1)
	var front_z := -bl / 2 + lt
	var back_z := bl / 2 - lt
	var pairs := {
		"LegFL": Vector3i(-leg_x, 0, front_z), "LegFR": Vector3i(leg_x, 0, front_z),
		"LegBL": Vector3i(-leg_x, 0, back_z), "LegBR": Vector3i(leg_x, 0, back_z),
	}
	for leg_name: String in pairs:
		var origin: Vector3i = pairs[leg_name]
		var pivot := Node3D.new()
		pivot.name = leg_name
		pivot.position = Vector3(float(origin.x) * VOXEL, float(leg) * VOXEL,
			float(origin.z) * VOXEL)
		root.add_child(pivot)
		var lv := {}
		box(lv, Vector3i(-(lt - 1) / 2, -leg, -(lt - 1) / 2),
			Vector3i(lt / 2, -1, lt / 2), primary.lerp(dark, 0.35))
		box(lv, Vector3i(-(lt - 1) / 2, -leg, -(lt - 1) / 2),
			Vector3i(lt / 2, -leg + 1, lt / 2), dark)
		pivot.add_child(_mesh_node(lv, "%sMesh" % leg_name))

	# --- tail -------------------------------------------------------------
	var tail_pivot := Node3D.new()
	tail_pivot.name = "Tail"
	tail_pivot.position = Vector3(0.0, float(y0 + bh - 3) * VOXEL, float(bl / 2) * VOXEL)
	root.add_child(tail_pivot)
	var tv := {}
	var tl: int = s["tail_len"]
	var tw: int = s["tail_w"]
	var thw := maxi(tw / 2, 0)
	if s.get("tail_up", false):
		box(tv, Vector3i(-thw, 0, 0), Vector3i(thw, tl, 1), accent)
	else:
		box(tv, Vector3i(-thw, -tl + 1, 0), Vector3i(thw, 0, tw), primary)
		box(tv, Vector3i(-thw, -tl + 1, 0), Vector3i(thw, -tl + 2, tw), accent)
	tail_pivot.add_child(_mesh_node(tv, "TailMesh"))


static func _add_headgear(voxels: Dictionary, species: Species, s: Dictionary, top_y: int,
		front_z: int, hw: int, dark: Color, accent: Color) -> void:
	var kind: String = s.get("antler", "none")
	if kind == "none":
		return
	var bone := Color(0.62, 0.56, 0.44)
	match kind:
		"branch", "branch_big":
			var size: int = 5 if kind == "branch" else 8
			for side: int in [-1, 1]:
				var x := side * hw
				for i in size:
					box(voxels, Vector3i(x + side * (i / 3), top_y + i, front_z - i / 2),
						Vector3i(x + side * (i / 3), top_y + i, front_z - i / 2), bone)
					if i % 2 == 1 and i > 1:
						box(voxels, Vector3i(x + side * (i / 3 + 1), top_y + i,
							front_z - i / 2 - 1),
							Vector3i(x + side * (i / 3 + 1), top_y + i + 1,
							front_z - i / 2 - 1), bone)
		"palm":
			for side: int in [-1, 1]:
				var x := side * hw
				box(voxels, Vector3i(x, top_y, front_z), Vector3i(x + side * 2, top_y + 2,
					front_z), bone)
				box(voxels, Vector3i(x + side * 2, top_y + 2, front_z - 3),
					Vector3i(x + side * 5, top_y + 3, front_z + 2), bone)
		"curl":
			for side: int in [-1, 1]:
				var x := side * hw
				var pts := [Vector3i(0, 1, 0), Vector3i(1, 1, -1), Vector3i(2, 0, -2),
					Vector3i(2, -1, -1), Vector3i(1, -2, 0), Vector3i(0, -2, 1),
					Vector3i(0, -1, 2)]
				for p: Vector3i in pts:
					box(voxels, Vector3i(x + side * p.x, top_y + p.y, front_z + p.z),
						Vector3i(x + side * p.x, top_y + p.y, front_z + p.z), bone)
		"prong":
			for side: int in [-1, 1]:
				var x := side * hw
				box(voxels, Vector3i(x, top_y, front_z), Vector3i(x, top_y + 3, front_z),
					dark.lerp(bone, 0.4))
				box(voxels, Vector3i(x + side, top_y + 2, front_z),
					Vector3i(x + side, top_y + 2, front_z), dark.lerp(bone, 0.4))
		"tusk":
			for side: int in [-1, 1]:
				box(voxels, Vector3i(side * maxi(hw - 1, 0), top_y - 3, front_z - 3),
					Vector3i(side * maxi(hw - 1, 0), top_y - 2, front_z - 3),
					Color(0.90, 0.88, 0.80))


static func _build_bird(root: Node3D, species: Species, s: Dictionary, primary: Color,
		secondary: Color, accent: Color, dark: Color) -> void:
	var bl: int = s["body_len"]
	var bh: int = s["body_h"]
	var bw: int = s["body_w"]
	var hw := bw / 2
	var stand := 2

	var body_voxels := {}
	box(body_voxels, Vector3i(-hw, stand, -bl / 2), Vector3i(hw, stand + bh - 1, bl / 2),
		primary)
	box(body_voxels, Vector3i(-hw, stand, -bl / 2), Vector3i(hw, stand + 1, bl / 2),
		secondary)
	# Legs.
	for side: int in [-1, 1]:
		box(body_voxels, Vector3i(side * maxi(hw - 1, 0), 0, 0),
			Vector3i(side * maxi(hw - 1, 0), stand - 1, 0), Color(0.72, 0.62, 0.30))
	# Tail fan.
	var tl: int = s["tail"]
	box(body_voxels, Vector3i(-hw + 1, stand + 1, bl / 2), Vector3i(hw - 1, stand + 2,
		bl / 2 + tl), secondary.darkened(0.1))
	root.add_child(_mesh_node(body_voxels, "Body"))

	# Head on its own pivot so the bird can track you.
	var head_pivot := Node3D.new()
	head_pivot.name = "Head"
	head_pivot.position = Vector3(0.0, float(stand + bh - 2) * VOXEL, float(-bl / 2) * VOXEL)
	root.add_child(head_pivot)
	var head_voxels := {}
	var hs: int = s["head"]
	var hh := hs / 2
	box(head_voxels, Vector3i(-hh, 0, -hs + 1), Vector3i(hh, hs - 1, 0), primary)
	var eye_bright := Color(0.95, 0.80, 0.20) if s.get("big_eyes", false) \
		else Color(0.92, 0.92, 0.94)
	for side: int in [-1, 1]:
		head_voxels[Vector3i(side * hh, hs - 2, -hs + 1)] = eye_bright
		if s.get("big_eyes", false):
			head_voxels[Vector3i(side * hh, hs - 3, -hs + 1)] = dark
	var beak: int = s["beak"]
	var beak_col := Color(0.86, 0.72, 0.24) if species.shape == "duck" else dark
	box(head_voxels, Vector3i(0, maxi(hs - 3, 0), -hs - beak + 1), Vector3i(0, hs - 2, -hs),
		beak_col)
	if s.get("tufts", false):
		for side: int in [-1, 1]:
			box(head_voxels, Vector3i(side * hh, hs, -hs + 2),
				Vector3i(side * hh, hs + 1, -hs + 2), secondary)
	head_pivot.add_child(_mesh_node(head_voxels, "HeadMesh"))

	# Wings fold along the body and open when the bird flies.
	var wing: int = s["wing"]
	for side: int in [-1, 1]:
		var pivot := Node3D.new()
		pivot.name = "WingL" if side < 0 else "WingR"
		pivot.position = Vector3(float(side * hw) * VOXEL, float(stand + bh - 2) * VOXEL, 0.0)
		root.add_child(pivot)
		var wv := {}
		box(wv, Vector3i(0, -bh + 2, -bl / 2 + 1), Vector3i(side * wing, 0, bl / 2),
			secondary.darkened(0.08))
		pivot.add_child(_mesh_node(wv, "WingMesh"))


## A blocky person. Used for the third-person hunter and every villager.
static func build_humanoid(palette: Dictionary, height_m: float) -> Node3D:
	var root := Node3D.new()
	root.name = "Model"
	var skin: Color = palette.get("skin", Color(0.78, 0.60, 0.45))
	var shirt: Color = palette.get("shirt", Color(0.35, 0.42, 0.32))
	var trousers: Color = palette.get("trousers", Color(0.28, 0.26, 0.24))
	var hair: Color = palette.get("hair", Color(0.24, 0.18, 0.13))
	var hat: Color = palette.get("hat", Color(0.0, 0.0, 0.0, 0.0))
	var pack: Color = palette.get("pack", Color(0.36, 0.30, 0.20))

	var leg_len := 7
	var torso_h := 7
	var torso_w := 3
	var torso_d := 2

	var body := {}
	box(body, Vector3i(-torso_w, leg_len, -torso_d), Vector3i(torso_w, leg_len + torso_h - 1,
		torso_d), shirt)
	box(body, Vector3i(-torso_w, leg_len, -torso_d), Vector3i(torso_w, leg_len + 1, torso_d),
		trousers)
	if palette.get("has_pack", false):
		box(body, Vector3i(-2, leg_len + 2, torso_d), Vector3i(2, leg_len + torso_h - 1,
			torso_d + 1), pack)
	root.add_child(_mesh_node(body, "Body"))

	var head_pivot := Node3D.new()
	head_pivot.name = "Head"
	head_pivot.position = Vector3(0.0, float(leg_len + torso_h) * VOXEL, 0.0)
	root.add_child(head_pivot)
	var head := {}
	box(head, Vector3i(-2, 0, -2), Vector3i(2, 4, 2), skin)
	box(head, Vector3i(-2, 4, -2), Vector3i(2, 4, 2), hair)
	for side: int in [-1, 1]:
		head[Vector3i(side, 2, -2)] = Color(0.12, 0.10, 0.10)
	if hat.a > 0.0:
		box(head, Vector3i(-3, 5, -3), Vector3i(3, 5, 3), hat)
		box(head, Vector3i(-2, 6, -2), Vector3i(2, 7, 2), hat)
	head_pivot.add_child(_mesh_node(head, "HeadMesh"))

	for side: int in [-1, 1]:
		var arm_pivot := Node3D.new()
		arm_pivot.name = "ArmL" if side < 0 else "ArmR"
		arm_pivot.position = Vector3(float(side * (torso_w + 1)) * VOXEL,
			float(leg_len + torso_h - 1) * VOXEL, 0.0)
		root.add_child(arm_pivot)
		var av := {}
		box(av, Vector3i(-1, -6, -1), Vector3i(1, 0, 1), shirt)
		box(av, Vector3i(-1, -6, -1), Vector3i(1, -5, 1), skin)
		arm_pivot.add_child(_mesh_node(av, "ArmMesh"))

		var leg_pivot := Node3D.new()
		leg_pivot.name = "LegL" if side < 0 else "LegR"
		leg_pivot.position = Vector3(float(side * 1) * VOXEL, float(leg_len) * VOXEL, 0.0)
		root.add_child(leg_pivot)
		var lv := {}
		box(lv, Vector3i(-1, -leg_len, -1), Vector3i(1, 0, 1), trousers)
		box(lv, Vector3i(-1, -leg_len, -1), Vector3i(1, -leg_len + 1, 2),
			Color(0.20, 0.16, 0.13))
		leg_pivot.add_child(_mesh_node(lv, "LegMesh"))

	var model_h := float(leg_len + torso_h + 5) * VOXEL
	root.scale = Vector3.ONE * (height_m / model_h)
	return root
