class_name CreatureBody
extends RefCounted
## Builds every creature in the game as a small rig of named parts, so the AI
## can animate a walk cycle, turn a head toward the camera and flick an ear
## without any imported animation data.
##
## Bodies are grown from tapered limbs and faceted blobs rather than cubes:
## these are the subject of every photograph in the game, so they have to hold
## up when a 400mm lens is pointed at them. Everything faces -Z.

## Proportions in decimetres, scaled to the species' real shoulder height.
const SHAPES := {
	"deer": {"len": 17, "h": 8, "w": 6, "leg": 9, "neck": 6, "rise": 5, "head": 4,
		"muzzle": 3.0, "ear": 2.2, "tail": 2.5, "tail_up": true, "antler": "branch",
		"hump": 0.0, "slim": 1.0},
	"elk": {"len": 21, "h": 10, "w": 8, "leg": 11, "neck": 7, "rise": 6, "head": 5,
		"muzzle": 3.6, "ear": 2.4, "tail": 2.0, "tail_up": false, "antler": "branch_big",
		"hump": 1.4, "mane": true, "slim": 1.05},
	"moose": {"len": 26, "h": 13, "w": 10, "leg": 16, "neck": 6, "rise": 3, "head": 6,
		"muzzle": 5.0, "ear": 3.0, "tail": 1.5, "tail_up": false, "antler": "palm",
		"hump": 3.0, "dewlap": true, "slim": 1.0},
	"canine": {"len": 15, "h": 7, "w": 5, "leg": 7, "neck": 3, "rise": 2, "head": 4,
		"muzzle": 3.4, "ear": 2.2, "tail": 6.5, "tail_up": false, "antler": "none",
		"hump": 0.0, "bushy": 0.55, "slim": 1.0},
	"fox": {"len": 11, "h": 5, "w": 4, "leg": 4.5, "neck": 2, "rise": 1, "head": 3,
		"muzzle": 2.6, "ear": 2.8, "tail": 7.0, "tail_up": false, "antler": "none",
		"hump": 0.0, "bushy": 0.85, "slim": 0.95},
	"bear": {"len": 18, "h": 11, "w": 9, "leg": 7, "neck": 2, "rise": 0, "head": 5,
		"muzzle": 2.6, "ear": 1.8, "tail": 1.0, "tail_up": false, "antler": "none",
		"hump": 2.6, "slim": 1.15},
	"boar": {"len": 14, "h": 8, "w": 6, "leg": 4.5, "neck": 1, "rise": 0, "head": 5,
		"muzzle": 3.4, "ear": 2.0, "tail": 2.5, "tail_up": false, "antler": "tusk",
		"hump": 2.0, "slim": 1.1},
	"hare": {"len": 6, "h": 4, "w": 3, "leg": 2.4, "neck": 1, "rise": 1, "head": 2.6,
		"muzzle": 1.4, "ear": 4.5, "tail": 1.0, "tail_up": true, "antler": "none",
		"hump": 0.6, "slim": 0.95},
	"ram": {"len": 15, "h": 9, "w": 6, "leg": 8, "neck": 3, "rise": 3, "head": 3.6,
		"muzzle": 2.6, "ear": 2.0, "tail": 1.6, "tail_up": false, "antler": "curl",
		"hump": 1.0, "slim": 1.05},
	"pronghorn": {"len": 13, "h": 7, "w": 5, "leg": 9, "neck": 5, "rise": 4,
		"head": 3.2, "muzzle": 2.4, "ear": 2.6, "tail": 1.6, "tail_up": true,
		"antler": "prong", "hump": 0.0, "slim": 0.92},
	"cat": {"len": 10, "h": 5, "w": 4, "leg": 4.5, "neck": 2, "rise": 1, "head": 3,
		"muzzle": 1.6, "ear": 2.2, "tail": 3.0, "tail_up": true, "antler": "none",
		"hump": 0.0, "slim": 0.95},
	"otter": {"len": 12, "h": 4, "w": 4, "leg": 2.0, "neck": 2, "rise": 1, "head": 2.8,
		"muzzle": 1.6, "ear": 0.8, "tail": 6.0, "tail_up": false, "antler": "none",
		"hump": 0.0, "slim": 1.0},
}

const BIRDS := {
	"owl": {"len": 5, "h": 6, "w": 5, "head": 3.4, "wing": 3.5, "tail": 3,
		"tufts": true, "beak": 1.0, "big_eyes": true, "stand": 1.6},
	"corvid": {"len": 7, "h": 4.5, "w": 4, "head": 2.6, "wing": 4.5, "tail": 5,
		"tufts": false, "beak": 2.2, "big_eyes": false, "stand": 2.0},
	"duck": {"len": 6.5, "h": 4.5, "w": 4, "head": 2.4, "wing": 3.5, "tail": 2.5,
		"tufts": false, "beak": 2.0, "big_eyes": false, "stand": 1.4},
}

const DM := 0.1     ## one unit of the tables above, in metres


static func build(species: Species) -> Node3D:
	var root := Node3D.new()
	root.name = "Model"
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(species.id) * 977
	var palette: Dictionary = species.palette
	var primary: Color = palette.get("primary", Color(0.5, 0.4, 0.3))
	var secondary: Color = palette.get("secondary", primary.lightened(0.15))
	var accent: Color = palette.get("accent", Color(0.9, 0.9, 0.85))
	var dark: Color = palette.get("dark", Color(0.12, 0.10, 0.09))

	var model_height := species.shoulder_height
	if BIRDS.has(species.shape):
		var b: Dictionary = BIRDS[species.shape]
		_bird(root, species, b, primary, secondary, accent, dark, rng)
		model_height = (float(b["stand"]) + float(b["h"])) * DM
	else:
		var s: Dictionary = SHAPES.get(species.shape, SHAPES["deer"])
		_quadruped(root, species, s, primary, secondary, accent, dark, rng)
		model_height = (float(s["leg"]) + float(s["h"])) * DM

	root.scale = Vector3.ONE * (species.shoulder_height / maxf(model_height, 0.01))
	return root


static func _part(node_name: String, verts: PackedVector3Array,
		normals: PackedVector3Array, colors: PackedColorArray) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	var mesh := MeshShapes.finish(verts, normals, colors)
	mi.mesh = mesh if mesh != null else ArrayMesh.new()
	mi.material_override = WorldMaterials.creature()
	return mi


# ------------------------------------------------------------------ quadruped

static func _quadruped(root: Node3D, species: Species, s: Dictionary, primary: Color,
		secondary: Color, accent: Color, dark: Color, rng: RandomNumberGenerator) -> void:
	var body_len := float(s["len"]) * DM
	var body_h := float(s["h"]) * DM
	var body_w := float(s["w"]) * DM
	var leg := float(s["leg"]) * DM
	var slim := float(s.get("slim", 1.0))

	var spine_y := leg + body_h * 0.5
	var half_h := body_h * 0.5

	# --- torso -------------------------------------------------------------
	var bv := PackedVector3Array()
	var bn := PackedVector3Array()
	var bc := PackedColorArray()
	# Barrel of the chest and belly, as three overlapping masses.
	MeshShapes.add_blob(bv, bn, bc, Vector3(0, spine_y, 0), half_h, primary, rng,
		Vector3(body_w / body_h * slim, 1.0, body_len / body_h * 0.52), 0.12, 2)
	MeshShapes.add_blob(bv, bn, bc, Vector3(0, spine_y + half_h * 0.1, -body_len * 0.22),
		half_h * 1.02, primary, rng,
		Vector3(body_w / body_h * slim, 1.0, 0.62), 0.14, 1)
	MeshShapes.add_blob(bv, bn, bc, Vector3(0, spine_y - half_h * 0.05, body_len * 0.26),
		half_h * 0.95, secondary, rng,
		Vector3(body_w / body_h * slim, 1.0, 0.6), 0.14, 1)
	# Pale belly.
	MeshShapes.add_blob(bv, bn, bc, Vector3(0, spine_y - half_h * 0.55, 0),
		half_h * 0.55, accent.lerp(secondary, 0.45), rng,
		Vector3(body_w / body_h * 0.85, 0.5, body_len / body_h * 0.45), 0.12, 1)
	var hump := float(s.get("hump", 0.0)) * DM
	if hump > 0.01:
		MeshShapes.add_blob(bv, bn, bc,
			Vector3(0, spine_y + half_h * 0.55, -body_len * 0.18), hump,
			primary.darkened(0.06), rng, Vector3(1.0, 0.8, 1.6), 0.18, 1)
	if s.get("mane", false):
		MeshShapes.add_blob(bv, bn, bc,
			Vector3(0, spine_y + half_h * 0.2, -body_len * 0.42), half_h * 0.7,
			dark.lerp(primary, 0.35), rng, Vector3(1.0, 1.1, 0.7), 0.3, 1)
	root.add_child(_part("Body", bv, bn, bc))

	# --- neck and head ------------------------------------------------------
	var neck_len := float(s["neck"]) * DM
	var rise := float(s["rise"]) * DM
	var pivot := Node3D.new()
	pivot.name = "Head"
	pivot.position = Vector3(0, spine_y + half_h * 0.35, -body_len * 0.45)
	root.add_child(pivot)

	var hv := PackedVector3Array()
	var hn := PackedVector3Array()
	var hc := PackedColorArray()
	var head_size := float(s["head"]) * DM
	var head_at := Vector3(0, rise, -neck_len)
	# Neck as a tapered limb from the shoulder up to the skull.
	MeshShapes.add_limb(hv, hn, hc, Vector3.ZERO, head_at, half_h * 0.62,
		head_size * 0.42, 7, primary, 0.10)
	if s.get("dewlap", false):
		MeshShapes.add_blob(hv, hn, hc, head_at * 0.55 + Vector3(0, -rise * 0.45, 0),
			head_size * 0.4, primary.darkened(0.1), rng, Vector3(0.6, 1.2, 0.6), 0.2, 1)
	# Skull.
	MeshShapes.add_blob(hv, hn, hc, head_at, head_size * 0.5, primary, rng,
		Vector3(0.85, 0.9, 1.25), 0.10, 2)
	# Muzzle.
	var muzzle := float(s["muzzle"]) * DM
	var muzzle_tip := head_at + Vector3(0, -head_size * 0.12, -muzzle)
	MeshShapes.add_limb(hv, hn, hc, head_at + Vector3(0, -head_size * 0.05, 0),
		muzzle_tip, head_size * 0.34, head_size * 0.22, 6,
		secondary.lerp(primary, 0.4), 0.08)
	MeshShapes.add_blob(hv, hn, hc, muzzle_tip, head_size * 0.20, dark, rng,
		Vector3(1.0, 0.8, 0.7), 0.1, 1)
	# Eyes, set wide. Portrait scoring looks for these.
	for side: int in [-1, 1]:
		var eye := head_at + Vector3(float(side) * head_size * 0.42,
			head_size * 0.18, -head_size * 0.30)
		MeshShapes.add_blob(hv, hn, hc, eye, head_size * 0.17, dark, rng,
			Vector3.ONE, 0.05, 1)
		MeshShapes.add_blob(hv, hn, hc, eye + Vector3(float(side) * 0.004, 0.006,
			-0.010), head_size * 0.07, Color(0.96, 0.96, 0.98), rng, Vector3.ONE, 0.0, 0)
	# Ears.
	var ear := float(s["ear"]) * DM
	for side: int in [-1, 1]:
		var base := head_at + Vector3(float(side) * head_size * 0.36, head_size * 0.36,
			head_size * 0.10)
		MeshShapes.add_limb(hv, hn, hc, base,
			base + Vector3(float(side) * ear * 0.45, ear * 0.85, ear * 0.1),
			head_size * 0.20, head_size * 0.06, 5, secondary, 0.12)
	_headgear(hv, hn, hc, species, s, head_at, head_size, rng)
	pivot.add_child(_part("HeadMesh", hv, hn, hc))

	# --- legs ---------------------------------------------------------------
	var leg_x := body_w * 0.42
	var front_z := -body_len * 0.30
	var back_z := body_len * 0.30
	var thickness := maxf(body_w * 0.16, 0.03)
	var pairs := {
		"LegFL": Vector3(-leg_x, leg, front_z), "LegFR": Vector3(leg_x, leg, front_z),
		"LegBL": Vector3(-leg_x, leg, back_z), "LegBR": Vector3(leg_x, leg, back_z),
	}
	for leg_name: String in pairs:
		var p := Node3D.new()
		p.name = leg_name
		p.position = pairs[leg_name]
		root.add_child(p)
		var lv := PackedVector3Array()
		var ln := PackedVector3Array()
		var lc := PackedColorArray()
		# Two segments with a slight joint, so legs read as legs.
		var knee := Vector3(0, -leg * 0.5, (0.06 * leg) * (1.0 if leg_name.begins_with("LegB")
			else -1.0))
		MeshShapes.add_limb(lv, ln, lc, Vector3.ZERO, knee, thickness * 1.25,
			thickness * 0.8, 6, primary.lerp(dark, 0.18), 0.10)
		MeshShapes.add_limb(lv, ln, lc, knee, Vector3(0, -leg, 0), thickness * 0.8,
			thickness * 0.55, 5, primary.lerp(dark, 0.42), 0.10)
		# Hoof or paw.
		MeshShapes.add_blob(lv, ln, lc, Vector3(0, -leg + thickness * 0.4, 0),
			thickness * 0.85, dark, rng, Vector3(1.0, 0.6, 1.2), 0.08, 1)
		p.add_child(_part("%sMesh" % leg_name, lv, ln, lc))

	# --- tail ---------------------------------------------------------------
	var tail_pivot := Node3D.new()
	tail_pivot.name = "Tail"
	tail_pivot.position = Vector3(0, spine_y + half_h * 0.4, body_len * 0.48)
	root.add_child(tail_pivot)
	var tv := PackedVector3Array()
	var tn := PackedVector3Array()
	var tc := PackedColorArray()
	var tail_len := float(s["tail"]) * DM
	var bushy := float(s.get("bushy", 0.0))
	if s.get("tail_up", false):
		MeshShapes.add_limb(tv, tn, tc, Vector3.ZERO, Vector3(0, tail_len * 0.7,
			tail_len * 0.4), body_w * 0.16, body_w * 0.10, 5, primary, 0.1)
		MeshShapes.add_blob(tv, tn, tc, Vector3(0, tail_len * 0.7, tail_len * 0.45),
			body_w * 0.28, accent, rng, Vector3(1.0, 1.2, 0.7), 0.2, 1)
	else:
		var tip := Vector3(0, -tail_len * 0.35, tail_len * 0.9)
		MeshShapes.add_limb(tv, tn, tc, Vector3.ZERO, tip, body_w * 0.16,
			body_w * 0.09, 5, primary, 0.1)
		if bushy > 0.01:
			# A brush, thickest two thirds of the way along.
			for i in 3:
				var t := 0.35 + 0.3 * float(i)
				MeshShapes.add_blob(tv, tn, tc, tip * t,
					body_w * (0.30 + bushy * 0.35) * (1.0 - absf(t - 0.7)),
					primary if i < 2 else accent, rng, Vector3(1.0, 1.0, 1.3), 0.22, 1)
	tail_pivot.add_child(_part("TailMesh", tv, tn, tc))


static func _headgear(verts: PackedVector3Array, normals: PackedVector3Array,
		colors: PackedColorArray, species: Species, s: Dictionary, head_at: Vector3,
		head_size: float, rng: RandomNumberGenerator) -> void:
	var kind: String = s.get("antler", "none")
	if kind == "none":
		return
	var bone := Color(0.66, 0.60, 0.48)
	var top := head_at + Vector3(0, head_size * 0.42, head_size * 0.1)
	match kind:
		"branch", "branch_big":
			var span: float = head_size * (2.4 if kind == "branch" else 3.6)
			var thick: float = head_size * (0.12 if kind == "branch" else 0.16)
			for side: int in [-1, 1]:
				var base := top + Vector3(float(side) * head_size * 0.3, 0, 0)
				var tip := base + Vector3(float(side) * span * 0.55, span * 0.75,
					-span * 0.2)
				MeshShapes.add_limb(verts, normals, colors, base, tip, thick,
					thick * 0.45, 5, bone, 0.12)
				# Tines coming off the main beam.
				for i in 3:
					var t := 0.30 + 0.25 * float(i)
					var from := base.lerp(tip, t)
					MeshShapes.add_limb(verts, normals, colors, from,
						from + Vector3(float(side) * span * 0.12, span * 0.32,
						-span * 0.16), thick * 0.5, thick * 0.16, 4, bone, 0.12)
		"palm":
			for side: int in [-1, 1]:
				var base := top + Vector3(float(side) * head_size * 0.3, 0, 0)
				var pan := base + Vector3(float(side) * head_size * 1.5,
					head_size * 0.7, 0)
				MeshShapes.add_limb(verts, normals, colors, base, pan, head_size * 0.16,
					head_size * 0.12, 5, bone, 0.12)
				MeshShapes.add_blob(verts, normals, colors, pan, head_size * 0.9, bone,
					rng, Vector3(1.1, 0.22, 1.0), 0.14, 1)
		"curl":
			for side: int in [-1, 1]:
				var centre := top + Vector3(float(side) * head_size * 0.34, 0, 0)
				var previous := centre
				for i in range(1, 7):
					var a := float(i) * 0.85
					var next := centre + Vector3(float(side) * head_size * 0.35 * sin(a * 0.6),
						head_size * 0.30 * cos(a), head_size * 0.42 * sin(a))
					MeshShapes.add_limb(verts, normals, colors, previous, next,
						head_size * (0.30 - float(i) * 0.03),
						head_size * (0.27 - float(i) * 0.03), 5, bone, 0.14)
					previous = next
		"prong":
			for side: int in [-1, 1]:
				var base := top + Vector3(float(side) * head_size * 0.28, 0, 0)
				var tip := base + Vector3(float(side) * head_size * 0.2, head_size * 1.1, 0)
				MeshShapes.add_limb(verts, normals, colors, base, tip, head_size * 0.11,
					head_size * 0.04, 4, Color(0.16, 0.14, 0.12), 0.1)
				MeshShapes.add_limb(verts, normals, colors, base.lerp(tip, 0.55),
					base.lerp(tip, 0.55) + Vector3(float(side) * head_size * 0.35,
					head_size * 0.22, 0), head_size * 0.07, head_size * 0.03, 4,
					Color(0.16, 0.14, 0.12), 0.1)
		"tusk":
			for side: int in [-1, 1]:
				var base := head_at + Vector3(float(side) * head_size * 0.3,
					-head_size * 0.18, -head_size * 0.7)
				MeshShapes.add_limb(verts, normals, colors, base,
					base + Vector3(float(side) * head_size * 0.12, head_size * 0.42,
					-head_size * 0.12), head_size * 0.09, head_size * 0.02, 4,
					Color(0.92, 0.90, 0.82), 0.08)


# ----------------------------------------------------------------------- bird

static func _bird(root: Node3D, species: Species, s: Dictionary, primary: Color,
		secondary: Color, accent: Color, dark: Color, rng: RandomNumberGenerator) -> void:
	var body_len := float(s["len"]) * DM
	var body_h := float(s["h"]) * DM
	var body_w := float(s["w"]) * DM
	var stand := float(s["stand"]) * DM
	var centre := Vector3(0, stand + body_h * 0.5, 0)

	var bv := PackedVector3Array()
	var bn := PackedVector3Array()
	var bc := PackedColorArray()
	MeshShapes.add_blob(bv, bn, bc, centre, body_h * 0.5, primary, rng,
		Vector3(body_w / body_h, 1.0, body_len / body_h), 0.12, 2)
	MeshShapes.add_blob(bv, bn, bc, centre + Vector3(0, -body_h * 0.22, -body_len * 0.1),
		body_h * 0.34, secondary, rng, Vector3(0.9, 0.8, 1.0), 0.12, 1)
	# Tail fan.
	var tail := float(s["tail"]) * DM
	MeshShapes.add_blob(bv, bn, bc, centre + Vector3(0, 0, body_len * 0.5 + tail * 0.4),
		tail * 0.5, secondary.darkened(0.1), rng, Vector3(0.7, 0.18, 1.2), 0.14, 1)
	# Legs.
	for side: int in [-1, 1]:
		MeshShapes.add_limb(bv, bn, bc,
			Vector3(float(side) * body_w * 0.25, stand, 0),
			Vector3(float(side) * body_w * 0.25, 0.0, 0), body_w * 0.07,
			body_w * 0.05, 4, Color(0.72, 0.62, 0.30), 0.1)
	root.add_child(_part("Body", bv, bn, bc))

	var pivot := Node3D.new()
	pivot.name = "Head"
	pivot.position = centre + Vector3(0, body_h * 0.35, -body_len * 0.42)
	root.add_child(pivot)
	var hv := PackedVector3Array()
	var hn := PackedVector3Array()
	var hc := PackedColorArray()
	var head := float(s["head"]) * DM
	MeshShapes.add_blob(hv, hn, hc, Vector3.ZERO, head * 0.5, primary, rng,
		Vector3(1.0, 1.0, 1.0), 0.10, 2)
	var beak := float(s["beak"]) * DM
	var beak_col := Color(0.88, 0.74, 0.26) if species.shape == "duck" else dark
	MeshShapes.add_limb(hv, hn, hc, Vector3(0, -head * 0.05, -head * 0.3),
		Vector3(0, -head * 0.10, -head * 0.3 - beak), head * 0.22,
		head * (0.16 if species.shape == "duck" else 0.03), 5, beak_col, 0.08)
	var eye_bright := Color(0.96, 0.82, 0.22) if s.get("big_eyes", false) \
		else Color(0.92, 0.92, 0.94)
	for side: int in [-1, 1]:
		var eye := Vector3(float(side) * head * 0.34, head * 0.10, -head * 0.28)
		MeshShapes.add_blob(hv, hn, hc, eye, head * (0.26 if s.get("big_eyes", false)
			else 0.15), eye_bright, rng, Vector3.ONE, 0.04, 1)
		MeshShapes.add_blob(hv, hn, hc, eye + Vector3(0, 0, -head * 0.09),
			head * (0.13 if s.get("big_eyes", false) else 0.08), dark, rng,
			Vector3.ONE, 0.0, 0)
	if s.get("tufts", false):
		for side: int in [-1, 1]:
			var base := Vector3(float(side) * head * 0.28, head * 0.4, 0)
			MeshShapes.add_limb(hv, hn, hc, base,
				base + Vector3(float(side) * head * 0.2, head * 0.55, 0),
				head * 0.14, head * 0.02, 4, secondary, 0.1)
	pivot.add_child(_part("HeadMesh", hv, hn, hc))

	var wing := float(s["wing"]) * DM
	for side: int in [-1, 1]:
		var p := Node3D.new()
		p.name = "WingL" if side < 0 else "WingR"
		p.position = centre + Vector3(float(side) * body_w * 0.42, body_h * 0.12, 0)
		root.add_child(p)
		var wv := PackedVector3Array()
		var wn := PackedVector3Array()
		var wc := PackedColorArray()
		MeshShapes.add_blob(wv, wn, wc, Vector3(float(side) * wing * 0.35, 0, 0),
			wing * 0.5, secondary.darkened(0.08), rng, Vector3(1.0, 0.22, 0.8), 0.14, 1)
		p.add_child(_part("%sMesh" % p.name, wv, wn, wc))


# ------------------------------------------------------------------- humanoid

## A person. Used for the third-person hunter and every villager.
static func build_humanoid(palette: Dictionary, height_m: float) -> Node3D:
	var root := Node3D.new()
	root.name = "Model"
	var rng := RandomNumberGenerator.new()
	rng.seed = int(palette.get("seed", 4242))
	var skin: Color = palette.get("skin", Color(0.78, 0.60, 0.45))
	var shirt: Color = palette.get("shirt", Color(0.35, 0.42, 0.32))
	var trousers: Color = palette.get("trousers", Color(0.28, 0.26, 0.24))
	var hair: Color = palette.get("hair", Color(0.24, 0.18, 0.13))
	var hat: Color = palette.get("hat", Color(0, 0, 0, 0))
	var pack: Color = palette.get("pack", Color(0.36, 0.30, 0.20))

	var leg_len := 0.82
	var torso_h := 0.62
	var shoulder := leg_len + torso_h

	var bv := PackedVector3Array()
	var bn := PackedVector3Array()
	var bc := PackedColorArray()
	MeshShapes.add_blob(bv, bn, bc, Vector3(0, leg_len + torso_h * 0.5, 0),
		torso_h * 0.5, shirt, rng, Vector3(0.62, 1.0, 0.42), 0.10, 2)
	MeshShapes.add_blob(bv, bn, bc, Vector3(0, leg_len + torso_h * 0.08, 0),
		torso_h * 0.30, trousers, rng, Vector3(1.0, 0.7, 0.8), 0.10, 1)
	if palette.get("has_pack", false):
		MeshShapes.add_blob(bv, bn, bc,
			Vector3(0, leg_len + torso_h * 0.6, torso_h * 0.28), torso_h * 0.30,
			pack, rng, Vector3(1.0, 1.1, 0.6), 0.12, 1)
	root.add_child(_part("Body", bv, bn, bc))

	var head_pivot := Node3D.new()
	head_pivot.name = "Head"
	head_pivot.position = Vector3(0, shoulder, 0)
	root.add_child(head_pivot)
	var hv := PackedVector3Array()
	var hn := PackedVector3Array()
	var hc := PackedColorArray()
	MeshShapes.add_limb(hv, hn, hc, Vector3(0, -0.03, 0), Vector3(0, 0.08, 0), 0.055,
		0.06, 6, skin, 0.06)
	MeshShapes.add_blob(hv, hn, hc, Vector3(0, 0.20, 0), 0.125, skin, rng,
		Vector3(0.85, 1.0, 0.9), 0.08, 2)
	MeshShapes.add_blob(hv, hn, hc, Vector3(0, 0.26, 0.01), 0.122, hair, rng,
		Vector3(0.88, 0.75, 0.95), 0.10, 1)
	for side: int in [-1, 1]:
		MeshShapes.add_blob(hv, hn, hc, Vector3(float(side) * 0.048, 0.21, -0.10),
			0.022, Color(0.12, 0.10, 0.10), rng, Vector3.ONE, 0.0, 1)
	if hat.a > 0.0:
		MeshShapes.add_blob(hv, hn, hc, Vector3(0, 0.30, 0), 0.20, hat, rng,
			Vector3(1.0, 0.10, 1.0), 0.06, 1)
		MeshShapes.add_limb(hv, hn, hc, Vector3(0, 0.29, 0), Vector3(0, 0.40, 0),
			0.105, 0.095, 7, hat, 0.08)
	head_pivot.add_child(_part("HeadMesh", hv, hn, hc))

	for side: int in [-1, 1]:
		var arm := Node3D.new()
		arm.name = "ArmL" if side < 0 else "ArmR"
		arm.position = Vector3(float(side) * 0.19, shoulder - 0.05, 0)
		root.add_child(arm)
		var av := PackedVector3Array()
		var an := PackedVector3Array()
		var ac := PackedColorArray()
		MeshShapes.add_limb(av, an, ac, Vector3.ZERO, Vector3(0, -0.34, 0), 0.055,
			0.042, 5, shirt, 0.10)
		MeshShapes.add_blob(av, an, ac, Vector3(0, -0.38, 0), 0.048, skin, rng,
			Vector3.ONE, 0.1, 1)
		arm.add_child(_part("%sMesh" % arm.name, av, an, ac))

		var leg := Node3D.new()
		leg.name = "LegL" if side < 0 else "LegR"
		leg.position = Vector3(float(side) * 0.085, leg_len, 0)
		root.add_child(leg)
		var lv := PackedVector3Array()
		var ln := PackedVector3Array()
		var lc := PackedColorArray()
		MeshShapes.add_limb(lv, ln, lc, Vector3.ZERO, Vector3(0, -leg_len, 0), 0.072,
			0.052, 5, trousers, 0.10)
		MeshShapes.add_blob(lv, ln, lc, Vector3(0, -leg_len + 0.03, -0.02), 0.062,
			Color(0.20, 0.16, 0.13), rng, Vector3(0.9, 0.5, 1.5), 0.1, 1)
		leg.add_child(_part("%sMesh" % leg.name, lv, ln, lc))

	var model_h := shoulder + 0.34
	root.scale = Vector3.ONE * (height_m / model_h)
	return root
