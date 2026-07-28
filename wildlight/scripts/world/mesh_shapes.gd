class_name MeshShapes
extends RefCounted
## Low-poly organic primitives, appended straight into shared vertex arrays.
##
## Used to build trees, rocks and bushes that read as living things rather than
## stacks of cubes, while staying cheap enough to instance thousands of times.
## Everything writes flat-shaded triangles unless a smooth normal is supplied,
## which keeps the faceted, hand-carved look without going blocky.

## Adds one flat-shaded triangle.
static func add_tri(verts: PackedVector3Array, normals: PackedVector3Array,
		colors: PackedColorArray, a: Vector3, b: Vector3, c: Vector3, color: Color) -> void:
	# Godot wants clockwise-front, i.e. (b - a) x (c - a) points away from the
	# visible side, so the geometric normal is the negation of that cross.
	var n := -(b - a).cross(c - a)
	if n.length_squared() < 0.0000001:
		return
	n = n.normalized()
	for v: Vector3 in [a, b, c]:
		verts.push_back(v)
		normals.push_back(n)
		colors.push_back(color)


static func add_quad(verts: PackedVector3Array, normals: PackedVector3Array,
		colors: PackedColorArray, a: Vector3, b: Vector3, c: Vector3, d: Vector3,
		color: Color) -> void:
	add_tri(verts, normals, colors, a, b, c, color)
	add_tri(verts, normals, colors, a, c, d, color)


## A tapered cylinder from [param base] to [param tip]. Trunks and branches.
static func add_limb(verts: PackedVector3Array, normals: PackedVector3Array,
		colors: PackedColorArray, base: Vector3, tip: Vector3, r_base: float,
		r_tip: float, sides: int, color: Color, tint: float = 0.10) -> void:
	var axis := tip - base
	if axis.length_squared() < 0.000001:
		return
	var up := axis.normalized()
	# Any vector not parallel to the axis gives us a stable frame.
	var reference := Vector3.UP if absf(up.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
	var side := up.cross(reference).normalized()
	var fwd := up.cross(side)

	for i in sides:
		var a0 := TAU * float(i) / float(sides)
		var a1 := TAU * float(i + 1) / float(sides)
		var d0 := side * cos(a0) + fwd * sin(a0)
		var d1 := side * cos(a1) + fwd * sin(a1)
		# Shade each facet slightly differently so a trunk is not a flat tube.
		var shade := 1.0 - tint * (0.5 + 0.5 * cos(a0 * 1.7))
		var c := Color(color.r * shade, color.g * shade, color.b * shade, color.a)
		add_quad(verts, normals, colors,
			base + d0 * r_base, base + d1 * r_base,
			tip + d1 * r_tip, tip + d0 * r_tip, c)


## A cone, used for conifer skirts.
static func add_cone(verts: PackedVector3Array, normals: PackedVector3Array,
		colors: PackedColorArray, base: Vector3, height: float, radius: float,
		sides: int, color: Color, droop: float = 0.0) -> void:
	var apex := base + Vector3(0.0, height, 0.0)
	for i in sides:
		var a0 := TAU * float(i) / float(sides)
		var a1 := TAU * float(i + 1) / float(sides)
		# Alternate the rim height so the silhouette is ragged, not a clean cone.
		var r0 := radius * (1.0 - droop * float(i % 3) * 0.18)
		var r1 := radius * (1.0 - droop * float((i + 1) % 3) * 0.18)
		var p0 := base + Vector3(cos(a0) * r0, -droop * 0.35, sin(a0) * r0)
		var p1 := base + Vector3(cos(a1) * r1, -droop * 0.35, sin(a1) * r1)
		var shade := 0.84 + 0.14 * float(i % 2)
		var c := Color(color.r * shade, color.g * shade, color.b * shade, color.a)
		add_tri(verts, normals, colors, p0, p1, apex, c)
		# Close the underside so the skirt reads solid from below.
		add_tri(verts, normals, colors, p1, p0, base, c * 0.72)


## An irregular blob, built by displacing a subdivided octahedron. This is the
## workhorse for broadleaf canopies and boulders.
static func add_blob(verts: PackedVector3Array, normals: PackedVector3Array,
		colors: PackedColorArray, centre: Vector3, radius: float, color: Color,
		rng: RandomNumberGenerator, stretch: Vector3 = Vector3.ONE,
		roughness: float = 0.30, subdivisions: int = 1) -> void:
	var base_points := [
		Vector3.UP, Vector3.DOWN, Vector3.LEFT, Vector3.RIGHT,
		Vector3.FORWARD, Vector3.BACK,
	]
	var faces := [
		[0, 3, 5], [0, 5, 2], [0, 2, 4], [0, 4, 3],
		[1, 5, 3], [1, 2, 5], [1, 4, 2], [1, 3, 4],
	]
	# Per-direction displacement, cached so shared vertices agree.
	var displaced := {}
	var displace := func(dir: Vector3) -> Vector3:
		var key := dir.snapped(Vector3(0.01, 0.01, 0.01))
		if displaced.has(key):
			return displaced[key]
		var wobble := 1.0 + rng.randf_range(-roughness, roughness)
		var p := centre + (dir.normalized() * radius * wobble) * stretch
		displaced[key] = p
		return p

	for face: Array in faces:
		var a: Vector3 = base_points[face[0]]
		var b: Vector3 = base_points[face[1]]
		var c: Vector3 = base_points[face[2]]
		_subdivide(verts, normals, colors, a, b, c, subdivisions, displace, color, rng)


static func _subdivide(verts: PackedVector3Array, normals: PackedVector3Array,
		colors: PackedColorArray, a: Vector3, b: Vector3, c: Vector3, depth: int,
		displace: Callable, color: Color, rng: RandomNumberGenerator) -> void:
	if depth <= 0:
		var shade: float = 0.80 + rng.randf() * 0.20
		add_tri(verts, normals, colors, displace.call(a), displace.call(b),
			displace.call(c), Color(color.r * shade, color.g * shade, color.b * shade,
			color.a))
		return
	var ab := (a + b).normalized()
	var bc := (b + c).normalized()
	var ca := (c + a).normalized()
	_subdivide(verts, normals, colors, a, ab, ca, depth - 1, displace, color, rng)
	_subdivide(verts, normals, colors, ab, b, bc, depth - 1, displace, color, rng)
	_subdivide(verts, normals, colors, ca, bc, c, depth - 1, displace, color, rng)
	_subdivide(verts, normals, colors, ab, bc, ca, depth - 1, displace, color, rng)


static func finish(verts: PackedVector3Array, normals: PackedVector3Array,
		colors: PackedColorArray) -> ArrayMesh:
	if verts.is_empty():
		return null
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
