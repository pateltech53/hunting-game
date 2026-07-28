class_name VoxelMesher
extends RefCounted
## Turns a sparse dictionary of `Vector3i -> Color` into a culled, ambient
## occluded mesh. Used for trees, village buildings, props and every animal in
## the game, so they all share one look.
##
## Winding follows Godot's clockwise-front convention: for a face with outward
## normal n the first triangle satisfies (b - a) x (c - a) == -n.

## The six cube faces, as four parallel tables of plain values.
##
## These are deliberately flat arrays of Vector3 rather than an array of
## dictionaries: this function runs on several chunk worker threads at once,
## and copying a nested container out of a shared script constant on multiple
## threads is not safe. Indexing a constant array of plain values is.
const FACE_COUNT := 6
const FACE_DIR := [
	Vector3i(0, 1, 0), Vector3i(0, -1, 0), Vector3i(1, 0, 0),
	Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1),
]
const FACE_BASE := [
	Vector3(0, 1, 0), Vector3(0, 0, 0), Vector3(1, 0, 0),
	Vector3(0, 0, 0), Vector3(0, 0, 1), Vector3(0, 0, 0),
]
## Corners walk (0,0) (1,0) (1,1) (0,1) in (axis1, axis2), which produces the
## clockwise-front winding Godot expects for every direction.
const FACE_A1 := [
	Vector3(1, 0, 0), Vector3(0, 0, 1), Vector3(0, 0, 1),
	Vector3(0, 1, 0), Vector3(0, 1, 0), Vector3(1, 0, 0),
]
const FACE_A2 := [
	Vector3(0, 0, 1), Vector3(1, 0, 0), Vector3(0, 1, 0),
	Vector3(0, 0, 1), Vector3(1, 0, 0), Vector3(0, 1, 0),
]
## Two triangles per quad, as flat corner indices.
const TRI := [0, 1, 2, 0, 2, 3]
const CORNER_U := [0.0, 1.0, 1.0, 0.0]
const CORNER_V := [0.0, 0.0, 1.0, 1.0]

## Corner indices for the six quads of a box, flat for the same reason.
const BOX_QUADS := [
	4, 5, 6, 7,   3, 2, 1, 0,   1, 5, 6, 2,
	0, 3, 7, 4,   2, 6, 7, 3,   0, 4, 5, 1,
]

const AO_STRENGTH := 0.42


## Builds mesh arrays for a voxel set.
##   origin_offset - subtracted from every voxel so a model can be centred
##   ao            - bake corner occlusion into the vertex colours
static func build_arrays(voxels: Dictionary, origin_offset: Vector3 = Vector3.ZERO,
		ao: bool = true, scale: float = 1.0) -> Array:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()

	var corner_pos := PackedVector3Array()
	corner_pos.resize(4)
	var corner_shade := PackedFloat32Array()
	corner_shade.resize(4)

	for pos: Vector3i in voxels:
		var color: Color = voxels[pos]
		var base_pos := (Vector3(pos) - origin_offset) * scale
		for f in FACE_COUNT:
			var dir: Vector3i = FACE_DIR[f]
			if voxels.has(pos + dir):
				continue
			var n := Vector3(dir)
			var a1: Vector3 = FACE_A1[f]
			var a2: Vector3 = FACE_A2[f]
			var fbase: Vector3 = FACE_BASE[f]
			for c in 4:
				var u: float = CORNER_U[c]
				var v: float = CORNER_V[c]
				corner_pos[c] = base_pos + (fbase + a1 * u + a2 * v) * scale
				corner_shade[c] = _corner_shade(voxels, pos, dir, a1, a2, u, v) \
					if ao else 1.0
			for t in 6:
				var k: int = TRI[t]
				verts.push_back(corner_pos[k])
				normals.push_back(n)
				var s: float = corner_shade[k]
				colors.push_back(Color(color.r * s, color.g * s, color.b * s, color.a))

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	return arrays


static func _corner_shade(voxels: Dictionary, pos: Vector3i, dir: Vector3i, a1: Vector3,
		a2: Vector3, u: float, v: float) -> float:
	var s1 := int(u) * 2 - 1
	var s2 := int(v) * 2 - 1
	var d1 := Vector3i(a1) * s1
	var d2 := Vector3i(a2) * s2
	var side1 := voxels.has(pos + dir + d1)
	var side2 := voxels.has(pos + dir + d2)
	var corner := voxels.has(pos + dir + d1 + d2)
	var occ := 0
	if side1 and side2:
		occ = 3
	else:
		occ = int(side1) + int(side2) + int(corner)
	return 1.0 - AO_STRENGTH * (float(occ) / 3.0)


static func build_mesh(voxels: Dictionary, origin_offset: Vector3 = Vector3.ZERO,
		ao: bool = true, scale: float = 1.0) -> ArrayMesh:
	var arrays := build_arrays(voxels, origin_offset, ao, scale)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	if verts.is_empty():
		return null
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## The one material every voxel surface in the game uses.
static func make_material(shaded: bool = true) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.95
	mat.metallic = 0.0
	mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED if not shaded \
		else BaseMaterial3D.SPECULAR_SCHLICK_GGX
	mat.cull_mode = BaseMaterial3D.CULL_BACK
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	return mat


static func make_water_material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = color
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.roughness = 0.08
	mat.metallic = 0.25
	mat.metallic_specular = 0.9
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mat


static func make_foliage_material() -> StandardMaterial3D:
	var mat := make_material()
	# Leaves catch a little light from behind, which matters a lot at dawn.
	mat.backlight_enabled = true
	mat.backlight = Color(0.16, 0.20, 0.12)
	mat.cull_mode = BaseMaterial3D.CULL_BACK
	return mat


## An axis-aligned box as raw triangle soup, for cheap chunk collision.
static func box_faces(from: Vector3, to: Vector3, out: PackedVector3Array) -> void:
	var p := [
		Vector3(from.x, from.y, from.z), Vector3(to.x, from.y, from.z),
		Vector3(to.x, from.y, to.z), Vector3(from.x, from.y, to.z),
		Vector3(from.x, to.y, from.z), Vector3(to.x, to.y, from.z),
		Vector3(to.x, to.y, to.z), Vector3(from.x, to.y, to.z),
	]
	# Six quads as flat corner indices: top, bottom, +x, -x, +z, -z.
	for q in 6:
		var base := q * 4
		var i0: int = BOX_QUADS[base]
		var i1: int = BOX_QUADS[base + 1]
		var i2: int = BOX_QUADS[base + 2]
		var i3: int = BOX_QUADS[base + 3]
		out.push_back(p[i0])
		out.push_back(p[i1])
		out.push_back(p[i2])
		out.push_back(p[i0])
		out.push_back(p[i2])
		out.push_back(p[i3])
