class_name ChunkBuilder
extends RefCounted
## Builds one chunk's geometry. Runs entirely on a worker thread and returns
## plain data; [VoxelChunk] turns that into nodes on the main thread.
##
## The ground is meshed as a continuous surface sampled from the height field,
## with per-vertex normals taken from its gradient. It used to be stacked
## one-metre columns, which cost more triangles and read as a staircase; this
## produces real hillsides, and cliffs fall out of the terrain being steep
## rather than out of the mesh being blocky.

const SIZE := 32
const PAD := 8            ## columns sampled outside the chunk, for structures
                          ## that reach in from a neighbour
const GRID := SIZE + PAD * 2

## Corner grid runs from -1 to SIZE + 1 so every corner used by a cell has the
## neighbours it needs to compute a gradient.
const CGRID := SIZE + 3

const TREE_SCALE_MIN := 0.85
const TREE_SCALE_RANGE := 0.35


static func build(gen: TerrainGenerator, coord: Vector2i, grass_density: float,
		want_collision: bool) -> Dictionary:
	var ox := coord.x * SIZE
	var oz := coord.y * SIZE
	var bmin := Vector2i(ox, oz)
	var bmax := Vector2i(ox + SIZE, oz + SIZE)
	var sea := float(TerrainGenerator.SEA_LEVEL)

	# --- corner heights, normals and colours ---------------------------------
	var ch := PackedFloat32Array()
	ch.resize(CGRID * CGRID)
	for gz in CGRID:
		var wz := float(oz - 1 + gz)
		for gx in CGRID:
			ch[gz * CGRID + gx] = gen.height_at(float(ox - 1 + gx), wz)

	var cn := PackedVector3Array()
	cn.resize(CGRID * CGRID)
	var cc := PackedColorArray()
	cc.resize(CGRID * CGRID)
	var cslope := PackedFloat32Array()
	cslope.resize(CGRID * CGRID)
	var biome_names: Array = []
	biome_names.resize(CGRID * CGRID)

	for gz in range(1, CGRID - 1):
		for gx in range(1, CGRID - 1):
			var i := gz * CGRID + gx
			var h: float = ch[i]
			# Central differences over one metre give the surface gradient.
			var dhdx: float = (ch[i + 1] - ch[i - 1]) * 0.5
			var dhdz: float = (ch[i + CGRID] - ch[i - CGRID]) * 0.5
			cn[i] = Vector3(-dhdx, 1.0, -dhdz).normalized()
			var slope := Vector2(dhdx, dhdz).length()
			cslope[i] = slope
			var wx := float(ox - 1 + gx)
			var wz2 := float(oz - 1 + gz)
			var bid := gen.biome_from_height(wx, wz2, h)
			biome_names[i] = bid
			cc[i] = gen.surface_color_smooth(wx, wz2, h, BiomeLibrary.get_biome(bid), slope)

	# --- villages that reach into this chunk ---------------------------------
	var structure_voxels := {}
	var lights: Array = []
	var markers: Array = []
	var sites := Structures.village_sites_near(gen, float(ox + SIZE / 2),
		float(oz + SIZE / 2), float(SIZE))
	for site: Dictionary in sites:
		Structures.stamp_village(site, gen, structure_voxels, bmin, bmax, lights, markers)

	# --- ground surface ------------------------------------------------------
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var water_verts := PackedVector3Array()
	var water_normals := PackedVector3Array()
	var water_colors := PackedColorArray()

	var chunk_heights := PackedInt32Array()
	chunk_heights.resize(SIZE * SIZE)
	var biome_index := PackedByteArray()
	biome_index.resize(SIZE * SIZE)
	var biome_order := BiomeLibrary.ids()
	var biome_counts := {}

	var props: Array = []
	var grass: Array = []

	for lz in SIZE:
		for lx in SIZE:
			# Corner indices for this cell, offset by the one-ring padding.
			var i00 := (lz + 1) * CGRID + (lx + 1)
			var i10 := i00 + 1
			var i01 := i00 + CGRID
			var i11 := i01 + 1
			var x := float(ox + lx)
			var z := float(oz + lz)

			var p00 := Vector3(x, ch[i00], z)
			var p10 := Vector3(x + 1.0, ch[i10], z)
			var p11 := Vector3(x + 1.0, ch[i11], z + 1.0)
			var p01 := Vector3(x, ch[i01], z + 1.0)

			# Two triangles, wound so the visible side faces up.
			#
			# Gentle ground uses the smooth gradient normal so hills roll. Steep
			# ground blends toward the flat face normal, which breaks a cliff
			# into rocky facets instead of a featureless curtain.
			var facet: float = smoothstep(0.45, 1.30,
				(cslope[i00] + cslope[i10] + cslope[i11] + cslope[i01]) * 0.25)
			_emit_tri(verts, normals, colors, p00, p10, p11, cn[i00], cn[i10], cn[i11],
				cc[i00], cc[i10], cc[i11], facet)
			_emit_tri(verts, normals, colors, p00, p11, p01, cn[i00], cn[i11], cn[i01],
				cc[i00], cc[i11], cc[i01], facet)

			var centre_h: float = (ch[i00] + ch[i10] + ch[i11] + ch[i01]) * 0.25
			var slope: float = cslope[i00]
			var biome_id: String = biome_names[i00]
			var biome := BiomeLibrary.get_biome(biome_id)
			chunk_heights[lz * SIZE + lx] = int(round(centre_h))
			biome_index[lz * SIZE + lx] = maxi(biome_order.find(biome_id), 0)
			biome_counts[biome_id] = int(biome_counts.get(biome_id, 0)) + 1

			# Water sits as a flat sheet wherever the ground drops below it.
			var lowest: float = minf(minf(ch[i00], ch[i10]), minf(ch[i11], ch[i01]))
			if lowest < sea - 0.05:
				_emit_water(water_verts, water_normals, water_colors, x, z, sea,
					biome.water_color)

			# --- flora -------------------------------------------------------
			var wx := ox + lx
			var wz := oz + lz
			if _inside_village(sites, wx, wz):
				continue
			var ground := Vector3(float(wx) + 0.5, gen.height_at(float(wx) + 0.5,
				float(wz) + 0.5), float(wz) + 0.5)
			var tree := gen.tree_at(wx, wz, biome, centre_h, slope)
			if tree != "":
				props.append({
					"kind": tree, "biome": biome_id,
					"variant": int(gen.hash01(wx, wz, 15) * float(PropMeshes.VARIANTS))
						% PropMeshes.VARIANTS,
					"pos": ground,
					"yaw": gen.hash01(wx, wz, 16) * TAU,
					"scale": TREE_SCALE_MIN + gen.hash01(wx, wz, 17) * TREE_SCALE_RANGE,
				})
			elif gen.rock_at(wx, wz, biome, centre_h):
				props.append({
					"kind": "rock", "biome": biome_id,
					"variant": int(gen.hash01(wx, wz, 22) * float(PropMeshes.VARIANTS))
						% PropMeshes.VARIANTS,
					"pos": ground,
					"yaw": gen.hash01(wx, wz, 23) * TAU,
					"scale": 0.85 + gen.hash01(wx, wz, 24) * 0.6,
				})
			elif gen.bush_at(wx, wz, biome, centre_h, slope):
				props.append({
					"kind": "bush", "biome": biome_id,
					"variant": int(gen.hash01(wx, wz, 32) * float(PropMeshes.VARIANTS))
						% PropMeshes.VARIANTS,
					"pos": ground,
					"yaw": gen.hash01(wx, wz, 33) * TAU,
					"scale": 0.8 + gen.hash01(wx, wz, 34) * 0.5,
				})

			# --- ground cover -------------------------------------------------
			if grass_density > 0.0 and centre_h > sea + 0.3 and slope < 0.8:
				var per_column: float = 1.15 * grass_density
				if gen.hash01(wx, wz, 51) < per_column:
					var flower := gen.flower_at(wx, wz, biome, centre_h, slope)
					var tint := biome.grass_tuft
					var height_scale := 0.8 + gen.hash01(wx, wz, 52) * 0.7
					if flower >= 0:
						tint = biome.flower_colors[flower]
						height_scale *= 1.15
					var gx2 := float(wx) + gen.hash01(wx, wz, 53)
					var gz2 := float(wz) + gen.hash01(wx, wz, 54)
					grass.append({
						"pos": Vector3(gx2, gen.height_at(gx2, gz2), gz2),
						"yaw": gen.hash01(wx, wz, 55) * TAU,
						"scale": height_scale,
						"color": tint,
					})

	# --- structures ----------------------------------------------------------
	var structure_arrays: Array = []
	if not structure_voxels.is_empty():
		structure_arrays = VoxelMesher.build_arrays(structure_voxels, Vector3.ZERO, true, 1.0)

	# --- collision -----------------------------------------------------------
	var collision := PackedVector3Array()
	var foliage_collision := PackedVector3Array()
	if want_collision:
		collision.append_array(verts)
		if not structure_arrays.is_empty():
			collision.append_array(structure_arrays[Mesh.ARRAY_VERTEX])
		for prop: Dictionary in props:
			var bounds := PropMeshes.get_bounds(prop["biome"], prop["kind"], prop["variant"])
			var p: Vector3 = prop["pos"]
			var s: float = prop["scale"]
			if bounds.get("has_solid", false):
				var solid: AABB = bounds["solid"]
				VoxelMesher.box_faces(p + solid.position * s,
					p + (solid.position + solid.size) * s, collision)
			if bounds.get("has_canopy", false):
				var canopy: AABB = bounds["canopy"]
				VoxelMesher.box_faces(p + canopy.position * s,
					p + (canopy.position + canopy.size) * s, foliage_collision)

	var dominant := ""
	var dominant_n := -1
	for id: String in biome_counts:
		if int(biome_counts[id]) > dominant_n:
			dominant_n = int(biome_counts[id])
			dominant = id

	var terrain_arrays: Array = []
	if not verts.is_empty():
		terrain_arrays.resize(Mesh.ARRAY_MAX)
		terrain_arrays[Mesh.ARRAY_VERTEX] = verts
		terrain_arrays[Mesh.ARRAY_NORMAL] = normals
		terrain_arrays[Mesh.ARRAY_COLOR] = colors
	var water_arrays: Array = []
	if not water_verts.is_empty():
		water_arrays.resize(Mesh.ARRAY_MAX)
		water_arrays[Mesh.ARRAY_VERTEX] = water_verts
		water_arrays[Mesh.ARRAY_NORMAL] = water_normals
		water_arrays[Mesh.ARRAY_COLOR] = water_colors

	return {
		"coord": coord,
		"terrain": terrain_arrays,
		"water": water_arrays,
		"structure": structure_arrays,
		"collision": collision,
		"foliage_collision": foliage_collision,
		"props": props,
		"grass": grass,
		"lights": lights,
		"markers": markers,
		"heights": chunk_heights,
		"biome_index": biome_index,
		"dominant_biome": dominant,
		"has_water": not water_verts.is_empty(),
		"village_sites": sites,
	}


static func _push(verts: PackedVector3Array, normals: PackedVector3Array,
		colors: PackedColorArray, p: Vector3, n: Vector3, c: Color) -> void:
	verts.push_back(p)
	normals.push_back(n)
	colors.push_back(c)


## One ground triangle, blending its vertex normals toward the flat face normal
## by [param facet] so steep terrain reads as rock rather than a smooth sheet.
static func _emit_tri(verts: PackedVector3Array, normals: PackedVector3Array,
		colors: PackedColorArray, a: Vector3, b: Vector3, c: Vector3,
		na: Vector3, nb: Vector3, nc: Vector3, ca: Color, cb: Color, cc2: Color,
		facet: float) -> void:
	var face := -(b - a).cross(c - a)
	if face.length_squared() < 0.0000001:
		face = Vector3.UP
	else:
		face = face.normalized()
	_push(verts, normals, colors, a, na.lerp(face, facet).normalized(), ca)
	_push(verts, normals, colors, b, nb.lerp(face, facet).normalized(), cb)
	_push(verts, normals, colors, c, nc.lerp(face, facet).normalized(), cc2)


static func _emit_water(verts: PackedVector3Array, normals: PackedVector3Array,
		colors: PackedColorArray, x: float, z: float, y: float, col: Color) -> void:
	var p := [
		Vector3(x, y, z), Vector3(x + 1.0, y, z),
		Vector3(x + 1.0, y, z + 1.0), Vector3(x, y, z + 1.0),
	]
	for tri: Array in [[0, 1, 2], [0, 2, 3]]:
		for k: int in tri:
			verts.push_back(p[k])
			normals.push_back(Vector3.UP)
			colors.push_back(col)


static func _inside_village(sites: Array, wx: int, wz: int) -> bool:
	for site: Dictionary in sites:
		var p: Vector3 = site["position"]
		if Vector2(p.x - float(wx), p.z - float(wz)).length() < Structures.VILLAGE_RADIUS * 0.72:
			return true
	return false
