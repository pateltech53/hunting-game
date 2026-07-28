class_name MapView
extends Control
## Renders a small biome map straight out of the terrain generator, then draws
## sightings, villages and the player on top of it. Used by the Discovery
## Book's range page and by the in-field map.

var gen: TerrainGenerator
var centre := Vector2.ZERO
var span := 900.0            ## metres across the map
var markers: Array = []      ## {position: Vector2, color: Color, label: String, size: float}
var player_position := Vector2.ZERO
var player_yaw := 0.0
var show_player := true
var resolution := 128

var _texture: ImageTexture
var _rendered_key := ""


func _ready() -> void:
	custom_minimum_size = Vector2(320, 320)


func setup(generator: TerrainGenerator) -> void:
	gen = generator


func refresh(force: bool = false) -> void:
	if gen == null:
		return
	var key := "%d_%d_%d" % [int(centre.x), int(centre.y), int(span)]
	if key == _rendered_key and not force:
		return
	_rendered_key = key
	var img := Image.create(resolution, resolution, false, Image.FORMAT_RGBA8)
	var step := span / float(resolution)
	var origin := centre - Vector2(span, span) * 0.5
	for py in resolution:
		for px in resolution:
			var wx := origin.x + float(px) * step
			var wz := origin.y + float(py) * step
			var h := gen.height_at(wx, wz)
			var col: Color
			if h < float(TerrainGenerator.SEA_LEVEL):
				var depth := clampf((float(TerrainGenerator.SEA_LEVEL) - h) / 12.0, 0.0, 1.0)
				col = Color(0.16, 0.30, 0.40).lerp(Color(0.06, 0.14, 0.24), depth)
			else:
				var biome := BiomeLibrary.get_biome(gen.biome_from_height(wx, wz, h))
				col = biome.grass_a
				# Shade by altitude so ridges and valleys read.
				var alt := clampf((h - float(TerrainGenerator.SEA_LEVEL)) / 55.0, 0.0, 1.0)
				col = col.lerp(biome.rock, alt * 0.55)
				col = col.lightened(alt * 0.14)
			img.set_pixel(px, py, col)
	_texture = ImageTexture.create_from_image(img)
	queue_redraw()


func world_to_local(world_pos: Vector2) -> Vector2:
	var rect := get_rect()
	var origin := centre - Vector2(span, span) * 0.5
	var t := (world_pos - origin) / span
	return Vector2(t.x * rect.size.x, t.y * rect.size.y)


func _draw() -> void:
	var rect := get_rect()
	if _texture != null:
		draw_texture_rect(_texture, Rect2(Vector2.ZERO, rect.size), false)
	else:
		draw_rect(Rect2(Vector2.ZERO, rect.size), Color(0.10, 0.11, 0.12))

	# Distance rings every 200 m from the centre.
	var centre_px := rect.size * 0.5
	var ring_step := 200.0 / span * rect.size.x
	var rings := int(rect.size.x * 0.5 / maxf(ring_step, 1.0))
	for i in range(1, rings + 1):
		draw_arc(centre_px, ring_step * float(i), 0.0, TAU, 48,
			Color(1, 1, 1, 0.10), 1.0)

	for m: Dictionary in markers:
		var p := world_to_local(m["position"])
		if p.x < -8.0 or p.y < -8.0 or p.x > rect.size.x + 8.0 or p.y > rect.size.y + 8.0:
			continue
		var size: float = float(m.get("size", 4.0))
		var col: Color = m.get("color", UITheme.ACCENT)
		draw_circle(p, size, col)
		draw_arc(p, size + 1.5, 0.0, TAU, 16, Color(0, 0, 0, 0.5), 1.0)

	if show_player:
		var p := world_to_local(player_position)
		var dir := Vector2(sin(-player_yaw), -cos(-player_yaw))
		var side := Vector2(-dir.y, dir.x)
		var pts := PackedVector2Array([p + dir * 8.0, p - dir * 4.0 + side * 5.0,
			p - dir * 4.0 - side * 5.0])
		draw_colored_polygon(pts, Color(0.98, 0.96, 0.92))
		draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[0]]),
			Color(0.1, 0.1, 0.1, 0.8), 1.0)

	draw_rect(Rect2(Vector2.ZERO, rect.size), Color(0, 0, 0, 0.35), false, 2.0)
	# North marker.
	draw_line(Vector2(rect.size.x - 18.0, 26.0), Vector2(rect.size.x - 18.0, 10.0),
		Color(0.95, 0.95, 0.95, 0.8), 2.0)


func set_markers_from_sightings(sightings: Array, color: Color) -> void:
	markers.clear()
	for s: Dictionary in sightings:
		markers.append({
			"position": Vector2(float(s.get("x", 0.0)), float(s.get("z", 0.0))),
			"color": color,
			"size": clampf(3.0 + float(s.get("count", 1)) * 0.8, 3.0, 8.0),
		})


func frame_markers(padding: float = 260.0) -> void:
	if markers.is_empty():
		return
	var min_p := Vector2(INF, INF)
	var max_p := Vector2(-INF, -INF)
	for m: Dictionary in markers:
		var p: Vector2 = m["position"]
		min_p = min_p.min(p)
		max_p = max_p.max(p)
	centre = (min_p + max_p) * 0.5
	span = maxf(maxf(max_p.x - min_p.x, max_p.y - min_p.y) + padding, 400.0)
