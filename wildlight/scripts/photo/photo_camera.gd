class_name PhotoCamera
extends Node
## The camera you actually shoot with: lens, aperture, shutter, ISO, focus, and
## the capture itself.
##
## Raising the camera swaps the walking field of view for the lens's real one
## and hands exposure control to you. Get the settings wrong and the viewfinder
## goes black or white long before the scorer says anything.

signal raised_changed(raised: bool)
signal settings_changed
signal photo_taken(record: Dictionary)
signal focus_changed(distance: float)

const FILM_ADVANCE := 0.55        ## seconds between frames
const AF_MASK := 1 | (1 << 2) | (1 << 3) | (1 << 4)

var player: Player
var sky: SkySystem
var world: VoxelWorld
var scorer: PhotoScorer
var hud: CanvasLayer

var raised := false
var active := true

var lens: Lens
var focal_length := 50.0
var aperture := 5.6
var shutter_index := 6            ## index into LensLibrary.SHUTTER_DENOMINATORS
var iso_index := 1                ## index into LensLibrary.ISO_STOPS
var focus_distance := 12.0
var autofocus := true

var _lens_index := 0
var _available: Array = []
var _cooldown := 0.0
var _attributes: CameraAttributesPractical
var _base_fov := 74.0
var _busy := false
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	_available = LensLibrary.available()
	lens = _available[0]
	focal_length = lens.focal_min
	aperture = clampf(5.6, lens.aperture_min, lens.aperture_max)
	_attributes = CameraAttributesPractical.new()
	_attributes.dof_blur_amount = 0.12
	_attributes.auto_exposure_enabled = false


func setup(p: Player, sky_system: SkySystem, voxel_world: VoxelWorld,
		photo_scorer: PhotoScorer) -> void:
	player = p
	sky = sky_system
	world = voxel_world
	scorer = photo_scorer
	_base_fov = Settings.fov
	if player != null:
		player.camera().attributes = _attributes


func set_active(value: bool) -> void:
	active = value
	if not active and raised:
		set_raised(false)


func _unhandled_input(event: InputEvent) -> void:
	if not active or Game.is_paused or player == null:
		return
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_wheel(1)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_wheel(-1)


func _wheel(direction: int) -> void:
	if raised and lens.is_zoom():
		set_focal(focal_length * (1.0 + 0.12 * float(direction)))
	elif raised:
		adjust_focus(float(direction) * (0.12 if focus_distance < 8.0 else 0.06))
	else:
		cycle_lens(direction)


func _process(delta: float) -> void:
	if player == null:
		return
	_cooldown = maxf(0.0, _cooldown - delta)
	if not active:
		_apply_camera(delta)
		return

	if not Game.is_paused:
		var want_raised := Input.is_action_pressed("raise_camera")
		if want_raised != raised:
			set_raised(want_raised)
		if raised:
			_handle_settings_input()
			if Input.is_action_just_pressed("capture") and _cooldown <= 0.0 and not _busy:
				capture()
		if Input.is_action_just_pressed("lens_next"):
			cycle_lens(1)
		elif Input.is_action_just_pressed("lens_prev"):
			cycle_lens(-1)
	_apply_camera(delta)


func _handle_settings_input() -> void:
	if Input.is_action_just_pressed("aperture_open"):
		step_aperture(-1)
	elif Input.is_action_just_pressed("aperture_close"):
		step_aperture(1)
	if Input.is_action_just_pressed("shutter_faster"):
		step_shutter(-1)
	elif Input.is_action_just_pressed("shutter_slower"):
		step_shutter(1)
	if Input.is_action_just_pressed("iso_up"):
		step_iso(1)
	elif Input.is_action_just_pressed("iso_down"):
		step_iso(-1)
	if Input.is_action_just_pressed("autofocus"):
		autofocus = not autofocus
		if autofocus:
			run_autofocus()
		settings_changed.emit()
	if Input.is_action_pressed("focus_near"):
		adjust_focus(-0.04)
	elif Input.is_action_pressed("focus_far"):
		adjust_focus(0.04)


func set_raised(value: bool) -> void:
	if raised == value:
		return
	raised = value
	if player != null:
		player.rig.set_aiming(raised)
	if raised:
		AudioDirector.play("camera_raise", -10.0)
		if autofocus:
			run_autofocus()
	raised_changed.emit(raised)


# -------------------------------------------------------------- lens controls

func cycle_lens(direction: int) -> void:
	_available = LensLibrary.available()
	if _available.size() <= 1:
		return
	_lens_index = wrapi(_lens_index + direction, 0, _available.size())
	lens = _available[_lens_index]
	focal_length = lens.focal_min
	aperture = lens.clamp_aperture(aperture)
	focus_distance = maxf(focus_distance, lens.min_focus)
	AudioDirector.play("lens", -6.0)
	settings_changed.emit()


func select_lens(id: String) -> void:
	_available = LensLibrary.available()
	for i in _available.size():
		if _available[i].id == id:
			_lens_index = i
			lens = _available[i]
			focal_length = lens.focal_min
			aperture = lens.clamp_aperture(aperture)
			AudioDirector.play("lens", -6.0)
			settings_changed.emit()
			return


func set_focal(value: float) -> void:
	focal_length = lens.clamp_focal(value)
	settings_changed.emit()


func step_aperture(direction: int) -> void:
	var stops: Array = LensLibrary.APERTURE_STOPS
	var idx := 0
	var best := INF
	for i in stops.size():
		var d: float = absf(float(stops[i]) - aperture)
		if d < best:
			best = d
			idx = i
	idx = clampi(idx + direction, 0, stops.size() - 1)
	var candidate := float(stops[idx])
	if candidate < lens.aperture_min or candidate > lens.aperture_max:
		return
	aperture = candidate
	AudioDirector.play("lens", -18.0, 1.3)
	settings_changed.emit()


func step_shutter(direction: int) -> void:
	shutter_index = clampi(shutter_index + direction, 0,
		LensLibrary.SHUTTER_DENOMINATORS.size() - 1)
	AudioDirector.play("lens", -20.0, 1.5)
	settings_changed.emit()


func step_iso(direction: int) -> void:
	iso_index = clampi(iso_index + direction, 0, LensLibrary.ISO_STOPS.size() - 1)
	AudioDirector.play("lens", -20.0, 1.1)
	settings_changed.emit()


func shutter_denominator() -> int:
	return LensLibrary.SHUTTER_DENOMINATORS[shutter_index]


func iso() -> int:
	return LensLibrary.ISO_STOPS[iso_index]


func adjust_focus(amount: float) -> void:
	autofocus = false
	# Focus moves logarithmically - fine control up close, coarse far away.
	focus_distance = clampf(focus_distance * (1.0 + amount * 3.0) + amount * 0.4,
		lens.min_focus, 900.0)
	focus_changed.emit(focus_distance)


func run_autofocus() -> void:
	var hit := _centre_ray()
	if hit.is_empty():
		focus_distance = 60.0
	else:
		focus_distance = clampf(player.eye_position().distance_to(hit["position"]),
			lens.min_focus, 900.0)
	AudioDirector.play("focus", -18.0)
	focus_changed.emit(focus_distance)


func _centre_ray() -> Dictionary:
	if player == null:
		return {}
	var cam := player.camera()
	var from := cam.global_position
	var to := from - cam.global_transform.basis.z * 900.0
	var params := PhysicsRayQueryParameters3D.create(from, to)
	params.collision_mask = AF_MASK
	params.exclude = [player.get_rid()]
	var space := player.get_world_3d().direct_space_state
	return space.intersect_ray(params)


# ------------------------------------------------------------------- exposure

func camera_ev() -> float:
	return LensLibrary.camera_ev(aperture, shutter_denominator(), iso())


func scene_ev() -> float:
	return sky.scene_ev() if sky != null else 12.0


## Positive means the scene is brighter than the camera is set for, i.e. the
## frame will come out over-exposed.
func exposure_error() -> float:
	return scene_ev() - camera_ev()


## Extra grain from pushing the sensor, 0..1.
func noise_level() -> float:
	return clampf((float(iso()) - 400.0) / 12000.0, 0.0, 1.0)


## How likely the shot is to be smeared by hand shake or subject movement.
func shake_risk() -> float:
	var denominator := float(shutter_denominator())
	# The old rule of thumb: you need 1/focal length to hand-hold.
	var needed := focal_length / maxf(lens.stability, 0.1)
	var risk := clampf(needed / maxf(denominator, 1.0), 0.0, 3.0)
	if player != null:
		var speed := Vector2(player.velocity.x, player.velocity.z).length()
		risk *= 1.0 + speed * 0.35
		if player.crouched:
			risk *= 0.6
	return clampf(risk - 0.5, 0.0, 2.0)


func _apply_camera(delta: float) -> void:
	var cam := player.camera()
	var target_fov: float = lens.fov_for(focal_length) if raised else _base_fov
	cam.fov = lerpf(cam.fov, target_fov, 1.0 - pow(0.0005, delta))

	if autofocus and raised:
		# Continuous autofocus keeps the centre of frame sharp.
		var hit := _centre_ray()
		if not hit.is_empty():
			var d := player.eye_position().distance_to(hit["position"])
			focus_distance = lerpf(focus_distance, clampf(d, lens.min_focus, 900.0),
				1.0 - pow(0.002, delta))

	var dof := lens.depth_of_field(focal_length, aperture, focus_distance)
	_attributes.dof_blur_near_enabled = raised
	_attributes.dof_blur_far_enabled = raised
	_attributes.dof_blur_near_distance = dof.x
	_attributes.dof_blur_near_transition = maxf(dof.x * 0.45, 0.15)
	_attributes.dof_blur_far_distance = dof.y
	_attributes.dof_blur_far_transition = maxf(dof.y * 0.35, 1.0)
	# Wide apertures on long glass smear the background hardest.
	_attributes.dof_blur_amount = clampf(
		0.03 + (focal_length / 400.0) * (5.6 / maxf(aperture, 0.7)) * 0.22, 0.02, 0.5)

	if sky != null:
		if raised:
			var natural := sky.natural_light_scale()
			var comp: float = pow(2.0, exposure_error() * 0.9) / natural
			sky.exposure_compensation = lerpf(sky.exposure_compensation,
				clampf(comp, 0.03, 18.0), 1.0 - pow(0.0001, delta))
		else:
			sky.exposure_compensation = lerpf(sky.exposure_compensation, 1.0,
				1.0 - pow(0.0001, delta))


# -------------------------------------------------------------------- capture

func capture() -> void:
	if _busy or player == null:
		return
	_busy = true
	_cooldown = FILM_ADVANCE
	AudioDirector.play("shutter", -3.0, _rng.randf_range(0.97, 1.03))
	player.rig.add_shake(0.18)

	# Analyse the scene while it is still on screen.
	var analysis := {}
	if scorer != null:
		analysis = scorer.analyse(self)

	var image := await _grab_frame()
	if image == null:
		_busy = false
		return

	var id := "photo_%d_%03d" % [int(Time.get_unix_time_from_system()), _rng.randi_range(0, 999)]
	var paths := SaveSystem.store_photo_image(image, id)
	if paths.is_empty():
		_busy = false
		return

	var record: Dictionary = scorer.score(self, analysis) if scorer != null else {}
	record["id"] = id
	record["path"] = paths["full"]
	record["thumb"] = paths["thumb"]
	record["seed"] = Game.world_seed
	record["world"] = Game.world_name
	record["taken"] = int(Time.get_unix_time_from_system())
	SaveSystem.register_photo(record)
	if scorer != null:
		scorer.commit(record)

	photo_taken.emit(record)
	Game.photo_captured.emit(record)
	_busy = false


## Hides the interface for exactly one frame and grabs what the player sees,
## so the photo is the composition they framed.
func _grab_frame() -> Image:
	var overlay_was_visible := false
	if hud != null and is_instance_valid(hud):
		overlay_was_visible = hud.visible
		hud.visible = false
	await RenderingServer.frame_post_draw
	var viewport := player.get_viewport()
	var texture := viewport.get_texture()
	var image: Image = null
	if texture != null:
		image = texture.get_image()
	if hud != null and is_instance_valid(hud):
		hud.visible = overlay_was_visible
	if image == null:
		return null

	var target_w: int = Settings.photo_resolution
	if image.get_width() > target_w:
		var target_h := int(round(float(target_w) * float(image.get_height())
			/ float(image.get_width())))
		image.resize(target_w, maxi(target_h, 1), Image.INTERPOLATE_LANCZOS)

	# The Compatibility renderer (the web build) cannot draw depth of field, so
	# a missed focus would otherwise look identical to a sharp frame. Soften the
	# saved image instead, so the mistake is visible in the gallery.
	if not Settings.supports_advanced_rendering():
		var hit := _centre_ray()
		if not hit.is_empty():
			var quality := focus_quality(player.eye_position().distance_to(hit["position"]))
			if quality < 0.9:
				_apply_smear(image, (1.0 - quality) * 1.5)

	var smear := shake_risk()
	if smear > 0.35:
		_apply_smear(image, smear)
	var grain := noise_level()
	if grain > 0.08:
		_apply_grain(image, grain)
	return image


## Fakes motion blur by resampling down and back up. Cheap, and it reads as
## exactly the mistake it is.
func _apply_smear(image: Image, amount: float) -> void:
	var factor := clampf(1.0 - amount * 0.30, 0.22, 0.95)
	var w := image.get_width()
	var h := image.get_height()
	image.resize(maxi(int(float(w) * factor), 8), maxi(int(float(h) * factor), 8),
		Image.INTERPOLATE_BILINEAR)
	image.resize(w, h, Image.INTERPOLATE_BILINEAR)


## Sparse per-pixel grain. Only touches a fraction of pixels so it stays fast
## even at full resolution.
func _apply_grain(image: Image, amount: float) -> void:
	var w := image.get_width()
	var h := image.get_height()
	var count := int(float(w * h) * clampf(amount, 0.0, 1.0) * 0.10)
	var strength := amount * 0.5
	for i in count:
		var x := _rng.randi_range(0, w - 1)
		var y := _rng.randi_range(0, h - 1)
		var c := image.get_pixel(x, y)
		var n := _rng.randf_range(-strength, strength)
		image.set_pixel(x, y, Color(clampf(c.r + n, 0.0, 1.0), clampf(c.g + n, 0.0, 1.0),
			clampf(c.b + n, 0.0, 1.0), 1.0))


# ------------------------------------------------------------------- readouts

func settings_summary() -> String:
	return "%s  f/%s  %s  ISO %d" % [
		lens.display_focal(focal_length),
		("%.1f" % aperture).trim_suffix(".0"),
		LensLibrary.shutter_label(shutter_denominator()),
		iso(),
	]


func depth_of_field_range() -> Vector2:
	return lens.depth_of_field(focal_length, aperture, focus_distance)


func is_in_focus(distance: float) -> bool:
	var dof := depth_of_field_range()
	return distance >= dof.x and distance <= dof.y


## 0..1 sharpness of a subject at [param distance], falling off outside the
## depth of field rather than snapping.
func focus_quality(distance: float) -> float:
	var dof := depth_of_field_range()
	if distance >= dof.x and distance <= dof.y:
		return 1.0
	var miss: float = (dof.x - distance) if distance < dof.x else (distance - dof.y)
	var tolerance: float = maxf((dof.y - dof.x) * 0.6, 0.4)
	return clampf(1.0 - miss / tolerance, 0.0, 1.0)
