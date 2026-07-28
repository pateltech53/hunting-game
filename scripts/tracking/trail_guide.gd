class_name TrailGuide
extends Node3D
## The path you get for holding the track key: the prints one animal left,
## strung together into a line of glowing motes you can walk along.
##
## It is deliberately not a quest arrow. The trail follows where the animal
## actually went, ends where the prints go cold, and fades on its own, so
## following it is still tracking rather than map-reading.

const MOTE_LIMIT := 96
const SPACING := 1.6            ## metres between motes along the path
const HOLD_SECONDS := 26.0      ## how long a revealed trail stays lit
const FADE_SECONDS := 4.0
const SEARCH_RADIUS := 46.0

var track_manager: TrackManager
var world: VoxelWorld

var active := false
var target_name := ""
var target_distance := 0.0

var _multimesh: MultiMeshInstance3D
var _points: PackedVector3Array = PackedVector3Array()
var _remaining := 0.0
var _pulse := 0.0
var _target: Animal = null


func _ready() -> void:
	var mesh := SphereMesh.new()
	mesh.radius = 0.11
	mesh.height = 0.22
	mesh.radial_segments = 6
	mesh.rings = 3

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.78, 0.34)
	mat.emission_energy_multiplier = 1.8
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.disable_receive_shadows = true
	mesh.material = mat

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = MOTE_LIMIT
	mm.visible_instance_count = 0

	_multimesh = MultiMeshInstance3D.new()
	_multimesh.name = "TrailMotes"
	_multimesh.multimesh = mm
	_multimesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_multimesh)


func setup(tracks: TrackManager, voxel_world: VoxelWorld) -> void:
	track_manager = tracks
	world = voxel_world


## Called when a scan completes. Returns a short line for the scan report, or
## an empty string when there was no trail worth showing.
func reveal(from: Vector3) -> String:
	if track_manager == null:
		return ""
	var trail := track_manager.trail_near(from, SEARCH_RADIUS)
	if trail.size() < 3:
		return ""

	var species_id: String = trail[trail.size() - 1]["species"]
	var species := SpeciesLibrary.get_species(species_id)
	var walker: int = trail[trail.size() - 1].get("walker", 0)
	_target = instance_from_id(walker) as Animal if walker != 0 else null
	if _target != null and (not is_instance_valid(_target) or _target.is_dead):
		_target = null

	# Start from the print nearest the player and follow it forwards in time,
	# so the motes lead away from you rather than back the way the animal came.
	var start := 0
	var best := INF
	for i in trail.size():
		var d: float = from.distance_to(trail[i]["position"])
		if d < best:
			best = d
			start = i
	var path := PackedVector3Array()
	for i in range(start, trail.size()):
		path.append(trail[i]["position"])
	# Close the last gap onto the animal itself when it is still nearby, so a
	# fresh trail actually delivers you to it.
	if _target != null and path.size() > 0:
		var last := path[path.size() - 1]
		if last.distance_to(_target.global_position) < 60.0:
			path.append(_target.global_position)
	if path.size() < 2:
		return ""

	_points = _resample(path)
	_remaining = HOLD_SECONDS
	active = true
	target_name = species.name if species != null else "something"
	target_distance = from.distance_to(_points[_points.size() - 1])
	AudioDirector.play("discovery", -16.0, 1.25)
	return "A trail of %s leads %s - follow the lights." % [
		target_name.to_lower(), _bearing(from, _points[mini(3, _points.size() - 1)])]


## Walks the polyline at a fixed spacing so motes are evenly spread however
## far apart the original prints were.
func _resample(path: PackedVector3Array) -> PackedVector3Array:
	var out := PackedVector3Array()
	var carry := 0.0
	for i in range(path.size() - 1):
		var a := path[i]
		var b := path[i + 1]
		var seg := a.distance_to(b)
		if seg < 0.001:
			continue
		var travelled := carry
		while travelled < seg:
			var point := a.lerp(b, travelled / seg)
			if world != null:
				point.y = float(world.surface_height(point.x, point.z)) + 0.55
			out.append(point)
			if out.size() >= MOTE_LIMIT:
				return out
			travelled += SPACING
		carry = travelled - seg
	return out


func clear() -> void:
	active = false
	_remaining = 0.0
	_points = PackedVector3Array()
	_target = null
	target_name = ""
	if _multimesh != null:
		_multimesh.multimesh.visible_instance_count = 0


func _process(delta: float) -> void:
	if not active:
		return
	_remaining -= delta
	if _remaining <= 0.0:
		clear()
		return
	_pulse += delta * 2.4

	# Keep the tail of the trail pinned to the animal while it is still moving,
	# otherwise a fresh trail points at where it stood a minute ago.
	if _target != null and is_instance_valid(_target) and not _target.is_dead \
			and _points.size() > 0:
		_points[_points.size() - 1] = _target.global_position + Vector3.UP * 0.55

	var fade: float = clampf(_remaining / FADE_SECONDS, 0.0, 1.0)
	var mm := _multimesh.multimesh
	var count: int = mini(_points.size(), MOTE_LIMIT)
	mm.visible_instance_count = count
	for i in count:
		var point := _points[i]
		# A wave running along the path shows which way to walk.
		var phase := _pulse - float(i) * 0.35
		var bob := sin(phase) * 0.09
		var glow: float = 0.45 + 0.55 * maxf(sin(phase), 0.0)
		var scale: float = 0.75 + glow * 0.5
		var basis := Basis().scaled(Vector3.ONE * scale)
		mm.set_instance_transform(i, Transform3D(basis,
			point + Vector3.UP * bob - global_position))
		var col := Color(1.0, 0.80, 0.38, clampf(glow * 0.85 * fade, 0.0, 1.0))
		# The last mote is the animal itself: mark it out.
		if i == count - 1:
			col = Color(0.62, 1.0, 0.72, clampf(0.9 * fade, 0.0, 1.0))
		mm.set_instance_color(i, col)


func _bearing(from: Vector3, to: Vector3) -> String:
	var d := to - from
	var deg := fposmod(rad_to_deg(atan2(d.x, -d.z)), 360.0)
	var names := ["north", "north-east", "east", "south-east", "south", "south-west",
		"west", "north-west"]
	return names[int(round(deg / 45.0)) % 8]
