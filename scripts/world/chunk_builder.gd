class_name ChunkBuilder
extends RefCounted
## Builds one chunk's geometry. Runs entirely on a worker thread and returns
## plain data; [VoxelChunk] turns that into nodes on the main thread.

const SIZE := 32
const PAD := 8            ## columns sampled outside the chunk, for slopes and
                          ## for structures that reach in from a neighbour
const GRID := SIZE + PAD * 2

const SIDE_SHADE_BOTTOM := 0.62
const AO_TOP := 0.30


static func build(gen: TerrainGenerator, coord: Vector2i, grass_density: float,
		want_collision: bool) -> Dictionary:
	var ox := coord.x * SIZE
	var oz := coord.y * SIZE
	var bmin := Vector2i(ox, oz)
	var bmax := Vector2i(ox + SIZE, oz + SIZE)

	# --- padded height + biome grid -----------------------------------------
	var heights := PackedInt32Array()
	heights.resize(GRID * GRID)
	var biome_names: Array = []
	biome_names.resize(GRID * GRID)
	var biome_refs: Array = []
	biome_refs.resize(GRID * GRID)
	for gz in GRID:
		var wz := oz - PAD + gz
		for gx in GRID:
			var wx := ox - PAD + gx
			var hf := gen.height_at(float(wx), float(wz))
			var h := int(floor(hf))
			var idx := gz * GRID + gx
			heights[idx] = h
			var bid := gen.biome_from_height(float(wx), float(wz), hf)
			biome_names[idx] = bid
			biome_refs[idx] = BiomeLibrary.get_biome(bid)

	# --- villages that reach into this chunk ---------------------------------
	var structure_voxels := {}
	var lights: Array = []
	var markers: Array = []
	var centre_x := float(ox + SIZE / 2)
	var centre_z := float(oz + SIZE / 2)
	var sites := Structures.village_sites_near(gen, centre_x, centre_z, float(SIZE))
	for site: Dictionary in sites:
		Structures.stamp_village(site, gen, structure_voxels, bmin, bmax, lights, markers)

	# --- terrain surface -----------------------------------------------------
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
	var sea := float(TerrainGenerator.SEA_LEVEL)

	for lz in SIZE:
		for lx in SIZE:
			var gx := lx + PAD
			var gz := lz + PAD
			var gi := gz * GRID + gx
			var h: int = heights[gi]
			var wx := ox + lx
			var wz := oz + lz
			var biome: Biome = biome_refs[gi]
			var biome_id: String = biome_names[gi]
			chunk_heights[lz * SIZE + lx] = h
			var bi := biome_order.find(biome_id)
			biome_index[lz * SIZE + lx] = maxi(bi, 0)
			biome_counts[biome_id] = int(biome_counts.get(biome_id, 0)) + 1

			var hx_pos: int = heights[gi + 1]
			var hx_neg: int = heights[gi - 1]
			var hz_pos: int = heights[gi + GRID]
			var hz_neg: int = heights[gi - GRID]
			var slope := float(maxi(maxi(absi(hx_pos - h), absi(hx_neg - h)),
				maxi(absi(hz_pos - h), absi(hz_neg - h))))
			var col := gen.surface_color(wx, wz, h, biome, slope)

			_emit_top(verts, normals, colors, wx, wz, h, col, heights, gi)
			_emit_side(verts, normals, colors, wx, wz, h, hx_pos, col, 0)
			_emit_side(verts, normals, colors, wx, wz, h, hx_neg, col, 1)
			_emit_side(verts, normals, colors, wx, wz, h, hz_pos, col, 2)
			_emit_side(verts, normals, colors, wx, wz, h, hz_neg, col, 3)

			# Water plane over any column that sits below sea level.
			if float(h) < sea:
				var wc := biome.water_color
				_emit_quad_y(water_verts, water_normals, water_colors,
					float(wx), float(wz), sea, wc)

			# --- flora -------------------------------------------------------
			if _inside_village(sites, wx, wz):
				continue
			var tree := gen.tree_at(wx, wz, biome, h, slope)
			if tree != "":
				props.append({
					"kind": tree, "biome": biome_id,
					"variant": int(gen.hash01(wx, wz, 15) * float(PropMeshes.VARIANTS))
						% PropMeshes.VARIANTS,
					"pos": Vector3(float(wx) + 0.5, float(h), float(wz) + 0.5),
					"yaw": floor(gen.hash01(wx, wz, 16) * 4.0) * PI * 0.5,
					"scale": 0.9 + gen.hash01(wx, wz, 17) * 0.35,
				})
			elif gen.rock_at(wx, wz, biome, h):
				props.append({
					"kind": "rock", "biome": biome_id,
					"variant": int(gen.hash01(wx, wz, 22) * float(PropMeshes.VARIANTS))
						% PropMeshes.VARIANTS,
					"pos": Vector3(float(wx) + 0.5, float(h), float(wz) + 0.5),
					"yaw": floor(gen.hash01(wx, wz, 23) * 4.0) * PI * 0.5,
					"scale": 0.85 + gen.hash01(wx, wz, 24) * 0.5,
				})
			elif gen.bush_at(wx, wz, biome, h, slope):
				props.append({
					"kind": "bush", "biome": biome_id,
					"variant": int(gen.hash01(wx, wz, 32) * float(PropMeshes.VARIANTS))
						% PropMeshes.VARIANTS,
					"pos": Vector3(float(wx) + 0.5, float(h), float(wz) + 0.5),
					"yaw": floor(gen.hash01(wx, wz, 33) * 4.0) * PI * 0.5,
					"scale": 0.8 + gen.hash01(wx, wz, 34) * 0.5,
				})

			# --- ground cover -------------------------------------------------
			if grass_density > 0.0 and float(h) > sea and slope < 2.0:
				var per_column: float = 0.55 * grass_density
				var roll := gen.hash01(wx, wz, 51)
				if roll < per_column:
					var flower := gen.flower_at(wx, wz, biome, h, slope)
					var tint := biome.grass_tuft
					var height_scale := 0.8 + gen.hash01(wx, wz, 52) * 0.7
					if flower >= 0:
						tint = biome.flower_colors[flower]
						height_scale *= 1.15
					grass.append({
						"pos": Vector3(float(wx) + gen.hash01(wx, wz, 53),
							float(h), float(wz) + gen.hash01(wx, wz, 54)),
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


static func _inside_village(sites: Array, wx: int, wz: int) -> bool:
	for site: Dictionary in sites:
		var p: Vector3 = site["position"]
		if Vector2(p.x - float(wx), p.z - float(wz)).length() < Structures.VILLAGE_RADIUS * 0.72:
			return true
	return false


## Top face, with corner occlusion read straight off the height grid: a corner
## surrounded by taller ground gets darker. This is what gives the terrain its
## soft creases without any lightmapping.
static func _emit_top(verts: PackedVector3Array, normals: PackedVector3Array,
		colors: PackedColorArray, wx: int, wz: int, h: int, col: Color,
		heights: PackedInt32Array, gi: int) -> void:
	var x := float(wx)
	var z := float(wz)
	var y := float(h)
	var hn := [
		heights[gi - 1], heights[gi + 1], heights[gi - GRID], heights[gi + GRID],
		heights[gi - GRID - 1], heights[gi - GRID + 1],
		heights[gi + GRID - 1], heights[gi + GRID + 1],
	]
	# Corner order matches the quad below: (0,0) (1,0) (1,1) (0,1) in (x, z).
	var shades := [
		_corner_ao(h, hn[0], hn[2], hn[4]),
		_corner_ao(h, hn[1], hn[2], hn[5]),
		_corner_ao(h, hn[1], hn[3], hn[7]),
		_corner_ao(h, hn[0], hn[3], hn[6]),
	]
	var p := [
		Vector3(x, y, z), Vector3(x + 1.0, y, z),
		Vector3(x + 1.0, y, z + 1.0), Vector3(x, y, z + 1.0),
	]
	var n := Vector3.UP
	for tri: Array in [[0, 1, 2], [0, 2, 3]]:
		for k: int in tri:
			verts.push_back(p[k])
			normals.push_back(n)
			var s: float = shades[k]
			colors.push_back(Color(col.r * s, col.g * s, col.b * s, 1.0))


static func _corner_ao(h: int, a: int, b: int, c: int) -> float:
	var occ := 0
	if a > h:
		occ += 1
	if b > h:
		occ += 1
	if c > h:
		occ += 1
	if a > h and b > h:
		occ = 3
	return 1.0 - AO_TOP * (float(occ) / 3.0)


## Cliff face toward one neighbour. [param dir] is 0:+x 1:-x 2:+z 3:-z.
static func _emit_side(verts: PackedVector3Array, normals: PackedVector3Array,
		colors: PackedColorArray, wx: int, wz: int, h: int, nh: int, col: Color,
		dir: int) -> void:
	if nh >= h:
		return
	var x := float(wx)
	var z := float(wz)
	var top := float(h)
	var bottom := float(nh)
	var p: Array
	var n: Vector3
	match dir:
		0:
			n = Vector3.RIGHT
			p = [Vector3(x + 1, bottom, z), Vector3(x + 1, bottom, z + 1),
				Vector3(x + 1, top, z + 1), Vector3(x + 1, top, z)]
		1:
			n = Vector3.LEFT
			p = [Vector3(x, bottom, z), Vector3(x, top, z),
				Vector3(x, top, z + 1), Vector3(x, bottom, z + 1)]
		2:
			n = Vector3.BACK
			p = [Vector3(x, bottom, z + 1), Vector3(x, top, z + 1),
				Vector3(x + 1, top, z + 1), Vector3(x + 1, bottom, z + 1)]
		_:
			n = Vector3.FORWARD
			p = [Vector3(x, bottom, z), Vector3(x + 1, bottom, z),
				Vector3(x + 1, top, z), Vector3(x, top, z)]
	# Darker at the base of the face - cheap contact shadow on every cliff.
	var side := col.darkened(0.12)
	for tri: Array in [[0, 1, 2], [0, 2, 3]]:
		for k: int in tri:
			var v: Vector3 = p[k]
			verts.push_back(v)
			normals.push_back(n)
			var t: float = clampf((v.y - bottom) / maxf(top - bottom, 0.001), 0.0, 1.0)
			var s: float = lerpf(SIDE_SHADE_BOTTOM, 1.0, t)
			colors.push_back(Color(side.r * s, side.g * s, side.b * s, 1.0))


static func _emit_quad_y(verts: PackedVector3Array, normals: PackedVector3Array,
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
