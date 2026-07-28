class_name Viewfinder
extends Control
## Everything drawn over the frame while the camera is raised: the mask, the
## composition grid, the focus box, a real luminance histogram and a level.

var camera: PhotoCamera
var sky: SkySystem
var raised := 0.0                 ## 0..1, animates in and out
var histogram := PackedFloat32Array()
var focus_hit := 0.0
var subject_marks: Array = []     ## screen positions of tracked subjects

var listen_contacts: Array = []
var listening := false
var scan_charge := 0.0
var player_yaw := 0.0

var _histogram_timer := 0.0
var _level_angle := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	UITheme.full_screen(self)
	histogram.resize(32)
	histogram.fill(0.0)


func _process(delta: float) -> void:
	var want: float = 1.0 if (camera != null and camera.raised) else 0.0
	raised = move_toward(raised, want, delta * 6.0)
	if camera != null and camera.raised and Settings.show_histogram:
		_histogram_timer -= delta
		if _histogram_timer <= 0.0:
			_histogram_timer = 0.45
			_sample_histogram()
	queue_redraw()


## Reads the frame back at low resolution. Only while the camera is up, and
## only a couple of times a second - it is a GPU readback.
func _sample_histogram() -> void:
	var texture := get_viewport().get_texture()
	if texture == null:
		return
	var image := texture.get_image()
	if image == null:
		return
	image.resize(80, 45, Image.INTERPOLATE_BILINEAR)
	var bins := PackedFloat32Array()
	bins.resize(32)
	bins.fill(0.0)
	var total := 0.0
	for y in image.get_height():
		for x in image.get_width():
			var c := image.get_pixel(x, y)
			var luma := c.r * 0.2126 + c.g * 0.7152 + c.b * 0.0722
			var idx := clampi(int(luma * 31.0), 0, 31)
			bins[idx] += 1.0
			total += 1.0
	if total <= 0.0:
		return
	var peak := 0.0
	for i in bins.size():
		peak = maxf(peak, bins[i])
	for i in bins.size():
		bins[i] = bins[i] / maxf(peak, 1.0)
	histogram = bins


func _draw() -> void:
	draw_field_senses(player_yaw, listen_contacts, scan_charge, listening)
	if raised <= 0.01 or camera == null:
		_draw_hipfire_reticle()
		return
	var rect := get_rect()
	var alpha := raised

	# --- letterbox mask -----------------------------------------------------
	var inset := rect.size * 0.055 * raised
	var frame := Rect2(inset, rect.size - inset * 2.0)
	var mask := Color(0.02, 0.025, 0.03, 0.55 * alpha)
	draw_rect(Rect2(0, 0, rect.size.x, frame.position.y), mask)
	draw_rect(Rect2(0, frame.end.y, rect.size.x, rect.size.y - frame.end.y), mask)
	draw_rect(Rect2(0, frame.position.y, frame.position.x, frame.size.y), mask)
	draw_rect(Rect2(frame.end.x, frame.position.y, rect.size.x - frame.end.x, frame.size.y),
		mask)

	# --- composition grid ---------------------------------------------------
	if Settings.show_viewfinder_grid:
		var grid := Color(1, 1, 1, 0.16 * alpha)
		for i in [1, 2]:
			var x := frame.position.x + frame.size.x * (float(i) / 3.0)
			var y := frame.position.y + frame.size.y * (float(i) / 3.0)
			draw_line(Vector2(x, frame.position.y), Vector2(x, frame.end.y), grid, 1.0)
			draw_line(Vector2(frame.position.x, y), Vector2(frame.end.x, y), grid, 1.0)

	# --- frame corners ------------------------------------------------------
	var corner_col := Color(0.93, 0.72, 0.32, 0.85 * alpha)
	var arm := minf(frame.size.x, frame.size.y) * 0.05
	for corner: Array in [
		[frame.position, Vector2(1, 0), Vector2(0, 1)],
		[Vector2(frame.end.x, frame.position.y), Vector2(-1, 0), Vector2(0, 1)],
		[Vector2(frame.position.x, frame.end.y), Vector2(1, 0), Vector2(0, -1)],
		[frame.end, Vector2(-1, 0), Vector2(0, -1)],
	]:
		var origin: Vector2 = corner[0]
		draw_line(origin, origin + (corner[1] as Vector2) * arm, corner_col, 2.0)
		draw_line(origin, origin + (corner[2] as Vector2) * arm, corner_col, 2.0)

	# --- focus box ----------------------------------------------------------
	var centre := rect.size * 0.5
	var box := 34.0 + focus_hit * 8.0
	var focus_col := Color(0.55, 0.90, 0.55, alpha) if camera.autofocus \
		else Color(0.93, 0.72, 0.32, alpha)
	draw_rect(Rect2(centre - Vector2(box, box) * 0.5, Vector2(box, box)), focus_col, false, 1.5)
	draw_line(centre - Vector2(5, 0), centre + Vector2(5, 0), focus_col, 1.0)
	draw_line(centre - Vector2(0, 5), centre + Vector2(0, 5), focus_col, 1.0)

	# --- subject markers ----------------------------------------------------
	for mark: Dictionary in subject_marks:
		var pos: Vector2 = mark["pos"]
		var size: float = clampf(float(mark["size"]) * rect.size.y * 0.5, 10.0, 400.0)
		var col: Color = Color(0.55, 0.85, 1.0, 0.5 * alpha)
		draw_rect(Rect2(pos - Vector2(size, size) * 0.5, Vector2(size, size)), col, false, 1.0)

	# --- level --------------------------------------------------------------
	var level_y := frame.end.y - 26.0
	var level_w := frame.size.x * 0.18
	var pitch := 0.0
	if camera.player != null:
		pitch = camera.player.rig.pitch
	_level_angle = lerpf(_level_angle, clampf(pitch * 2.2, -0.5, 0.5), 0.2)
	var level_col := Color(0.55, 0.90, 0.55, alpha) if absf(pitch) < 0.03 \
		else Color(1, 1, 1, 0.45 * alpha)
	var lc := Vector2(rect.size.x * 0.5, level_y)
	var dir := Vector2(cos(_level_angle), sin(_level_angle)) * level_w * 0.5
	draw_line(lc - dir, lc + dir, level_col, 2.0)

	# --- histogram ----------------------------------------------------------
	if Settings.show_histogram and histogram.size() > 0:
		var hw := 150.0
		var hh := 54.0
		var origin := Vector2(frame.end.x - hw - 14.0, frame.position.y + 14.0)
		draw_rect(Rect2(origin, Vector2(hw, hh)), Color(0, 0, 0, 0.45 * alpha))
		var bar_w := hw / float(histogram.size())
		for i in histogram.size():
			var h := histogram[i] * hh
			var shade: float = float(i) / float(histogram.size())
			draw_rect(Rect2(origin + Vector2(float(i) * bar_w, hh - h),
				Vector2(bar_w - 0.5, h)),
				Color(shade, shade, shade, 0.85 * alpha))
		draw_rect(Rect2(origin, Vector2(hw, hh)), Color(1, 1, 1, 0.18 * alpha), false, 1.0)

	# --- exposure meter -----------------------------------------------------
	var err := camera.exposure_error()
	var meter_w := frame.size.x * 0.30
	var mo := Vector2(rect.size.x * 0.5 - meter_w * 0.5, frame.end.y - 48.0)
	draw_rect(Rect2(mo, Vector2(meter_w, 3.0)), Color(1, 1, 1, 0.20 * alpha))
	for stop in range(-3, 4):
		var tx := mo.x + meter_w * (0.5 + float(stop) / 6.0)
		var tall: float = 8.0 if stop == 0 else 5.0
		draw_line(Vector2(tx, mo.y - tall), Vector2(tx, mo.y + tall + 3.0),
			Color(1, 1, 1, 0.30 * alpha), 1.0)
	var needle_x := mo.x + meter_w * clampf(0.5 + err / 6.0, 0.0, 1.0)
	var needle_col := UITheme.GOOD if absf(err) < 0.5 else \
		(UITheme.WARN if absf(err) < 1.5 else UITheme.BAD)
	needle_col.a = alpha
	draw_line(Vector2(needle_x, mo.y - 11.0), Vector2(needle_x, mo.y + 14.0), needle_col, 2.5)


func _draw_hipfire_reticle() -> void:
	var centre := get_rect().size * 0.5
	var col := Color(1, 1, 1, 0.35)
	draw_line(centre - Vector2(7, 0), centre - Vector2(2, 0), col, 1.5)
	draw_line(centre + Vector2(2, 0), centre + Vector2(7, 0), col, 1.5)
	draw_line(centre - Vector2(0, 7), centre - Vector2(0, 2), col, 1.5)
	draw_line(centre + Vector2(0, 2), centre + Vector2(0, 7), col, 1.5)


## Bearing ring for the listening mode, and the charge ring for a scan. Drawn
## here because this control is already full screen and already redraws.
func draw_field_senses(player_yaw: float, listen_contacts: Array, scan_charge: float,
		listening: bool) -> void:
	var rect := get_rect()
	if listening:
		var centre := Vector2(rect.size.x * 0.5, rect.size.y - 118.0)
		var radius := 58.0
		draw_arc(centre, radius, 0.0, TAU, 64, Color(1, 1, 1, 0.14), 1.5)
		for i in 8:
			var a := TAU * float(i) / 8.0
			var tick := Vector2(sin(a), -cos(a))
			draw_line(centre + tick * (radius - 5.0), centre + tick * radius,
				Color(1, 1, 1, 0.22), 1.0)
		# North relative to the way the player is facing.
		var north := Vector2(sin(-player_yaw), -cos(-player_yaw))
		draw_line(centre, centre + north * (radius - 12.0), Color(0.55, 0.72, 0.95, 0.5), 1.5)
		for contact: Dictionary in listen_contacts:
			var relative: float = float(contact["bearing"]) - player_yaw
			var dir := Vector2(sin(relative), -cos(relative))
			var strength: float = float(contact["strength"])
			var col := Color(0.93, 0.72, 0.32, clampf(0.35 + strength * 0.65, 0.0, 1.0))
			var inner: float = radius * (0.30 + 0.55 * (1.0 - strength))
			draw_line(centre + dir * inner, centre + dir * radius, col, 2.0 + strength * 2.5)
			draw_circle(centre + dir * radius, 3.0 + strength * 3.0, col)
		draw_circle(centre, 3.0, Color(1, 1, 1, 0.4))
	if scan_charge > 0.001:
		var sc := Vector2(rect.size.x * 0.5, rect.size.y * 0.5 + 46.0)
		draw_arc(sc, 20.0, -PI * 0.5, -PI * 0.5 + TAU * scan_charge, 32,
			Color(0.93, 0.72, 0.32, 0.9), 3.0)
