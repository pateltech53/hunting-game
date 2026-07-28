class_name HUD
extends CanvasLayer
## The in-field interface: viewfinder overlay, conditions readout, camera and
## rifle status, assignments, scan reports and toasts.

const TOAST_LIFETIME := 5.0

var player: Player
var sky: SkySystem
var weather: WeatherSystem
var camera: PhotoCamera
var rifle: Rifle
var tracker: Tracker
var board: ContractBoard
var wildlife: WildlifeDirector
var world: VoxelWorld

var viewfinder: Viewfinder

var _root: Control
var _conditions: Label
var _purse: Label
var _location: Label
var _contract_box: VBoxContainer
var _readout: RichTextLabel
var _readout_panel: PanelContainer
var _tool_label: Label
var _stamina: ProgressBar
var _toast_box: VBoxContainer
var _scan_box: VBoxContainer
var _scan_panel: PanelContainer
var _prompt: Label
var _listen_label: Label
var _scan_clear := 0.0
var _toasts: Array = []


func _ready() -> void:
	layer = 5
	_root = Control.new()
	_root.name = "HUDRoot"
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UITheme.full_screen(_root)
	add_child(_root)

	viewfinder = Viewfinder.new()
	_root.add_child(viewfinder)

	_build_conditions()
	_build_contracts()
	_build_readout()
	_build_bottom()
	_build_toasts()
	_build_scan()

	Game.toast.connect(_on_toast)


func bind(p: Player, sky_system: SkySystem, weather_system: WeatherSystem,
		photo_camera: PhotoCamera, gun: Rifle, field_tracker: Tracker,
		contract_board: ContractBoard, director: WildlifeDirector,
		voxel_world: VoxelWorld) -> void:
	player = p
	sky = sky_system
	weather = weather_system
	camera = photo_camera
	rifle = gun
	tracker = field_tracker
	board = contract_board
	wildlife = director
	world = voxel_world

	viewfinder.camera = camera
	viewfinder.sky = sky
	camera.hud = self
	if rifle != null:
		rifle.ammo_changed.connect(_on_ammo)
		rifle.hit_reported.connect(func(text: String) -> void: _on_toast(text, "hunt"))
	if tracker != null:
		tracker.scan_report.connect(_on_scan_report)
	if board != null:
		board.contracts_changed.connect(_refresh_contracts)
		_refresh_contracts()
	if player != null:
		player.tool_changed.connect(_on_tool_changed)
		_on_tool_changed("camera")


# ------------------------------------------------------------------ building

func _build_conditions() -> void:
	var panel := UITheme.panel()
	panel.position = Vector2(18, 16)
	panel.custom_minimum_size = Vector2(250, 0)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	_conditions = UITheme.label("--:--", 20, UITheme.ACCENT)
	_location = UITheme.label("", 13, UITheme.INK_DIM)
	_location.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_purse = UITheme.label("", 12, UITheme.ACCENT_DIM)
	box.add_child(_conditions)
	box.add_child(_location)
	box.add_child(_purse)
	panel.add_child(box)
	_root.add_child(panel)


func _build_contracts() -> void:
	var panel := UITheme.panel()
	panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	panel.offset_left = -330
	panel.offset_right = -18
	panel.offset_top = 16
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	box.add_child(UITheme.label("ASSIGNMENTS", 12, UITheme.ACCENT_DIM))
	_contract_box = VBoxContainer.new()
	_contract_box.add_theme_constant_override("separation", 6)
	box.add_child(_contract_box)
	panel.add_child(box)
	_root.add_child(panel)


func _build_readout() -> void:
	_readout_panel = UITheme.panel()
	_readout_panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_readout_panel.offset_left = 18
	_readout_panel.offset_top = -132
	_readout_panel.offset_bottom = -18
	_readout_panel.custom_minimum_size = Vector2(330, 0)
	_readout = UITheme.rich("", 14)
	_readout.custom_minimum_size = Vector2(310, 0)
	_readout_panel.add_child(_readout)
	_root.add_child(_readout_panel)


func _build_bottom() -> void:
	var panel := UITheme.panel()
	panel.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	panel.offset_left = -290
	panel.offset_right = -18
	panel.offset_top = -92
	panel.offset_bottom = -18
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	_tool_label = UITheme.label("Camera", 16, UITheme.INK)
	box.add_child(_tool_label)
	_stamina = ProgressBar.new()
	_stamina.max_value = 1.0
	_stamina.value = 1.0
	_stamina.show_percentage = false
	_stamina.custom_minimum_size = Vector2(0, 8)
	var fill := StyleBoxFlat.new()
	fill.bg_color = UITheme.ACCENT
	fill.set_corner_radius_all(3)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(1, 1, 1, 0.10)
	bg.set_corner_radius_all(3)
	_stamina.add_theme_stylebox_override("fill", fill)
	_stamina.add_theme_stylebox_override("background", bg)
	box.add_child(_stamina)
	box.add_child(UITheme.label(
		"F camera  ·  R rifle  ·  click/⏎ shoot  ·  X swap  ·  Q track  ·  E listen",
		11, UITheme.INK_FAINT))
	box.add_child(UITheme.label("arrows look  ·  WASD move  ·  V view",
		11, UITheme.INK_FAINT))
	panel.add_child(box)
	_root.add_child(panel)

	_prompt = UITheme.label("", 16, UITheme.ACCENT)
	_prompt.set_anchors_preset(Control.PRESET_CENTER)
	_prompt.offset_top = 60
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.visible = false
	_root.add_child(_prompt)


func _build_toasts() -> void:
	_toast_box = VBoxContainer.new()
	_toast_box.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_toast_box.offset_left = -260
	_toast_box.offset_right = 260
	_toast_box.offset_top = 22
	_toast_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_toast_box.add_theme_constant_override("separation", 6)
	_toast_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_toast_box)


func _build_scan() -> void:
	_scan_panel = UITheme.panel()
	_scan_panel.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	_scan_panel.offset_left = 18
	_scan_panel.offset_top = -80
	_scan_panel.custom_minimum_size = Vector2(360, 0)
	_scan_panel.visible = false
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 3)
	box.add_child(UITheme.label("FIELD SIGN", 12, UITheme.ACCENT_DIM))
	_scan_box = VBoxContainer.new()
	_scan_box.add_theme_constant_override("separation", 2)
	box.add_child(_scan_box)
	_listen_label = UITheme.label("", 13, UITheme.INK_DIM)
	box.add_child(_listen_label)
	_scan_panel.add_child(box)
	_root.add_child(_scan_panel)


# ------------------------------------------------------------------- updating

func _process(delta: float) -> void:
	if player == null:
		return
	_update_conditions()
	_update_readout()
	_update_viewfinder()
	_update_toasts(delta)
	_update_scan(delta)
	_stamina.value = player.stamina


func _update_conditions() -> void:
	if sky == null:
		return
	var phase := sky.light_phase()
	_conditions.text = "%s   %s" % [sky.clock_string(), phase]
	# Money in hand, and what is still waiting to be sold - the reminder that
	# a good frame is only paid for once it reaches a settlement.
	var pending := SaveSystem.unsold_count()
	_purse.text = "$%d" % Bank.funds() if pending == 0 else \
		"$%d   ·   %d frame%s unsold ($%d)" % [Bank.funds(), pending,
			"" if pending == 1 else "s", SaveSystem.unsold_total()]
	_conditions.add_theme_color_override("font_color",
		UITheme.ACCENT if phase in ["golden hour", "blue hour"] else UITheme.INK)
	var biome := BiomeLibrary.display_name(player.current_biome())
	var weather_name: String = weather.display_name() if weather != null else ""
	_location.text = "%s  ·  %s  ·  %s\nEV %.1f  ·  %s" % [
		Game.world_name, biome, weather_name, sky.scene_ev(), Game.mode_label()]


func _update_readout() -> void:
	if player.current_tool == Player.Tool.RIFLE and rifle != null:
		var range_m := rifle.range_to_target()
		_readout.text = "[b]%s[/b]\n%d / %d rounds\nRange %s\nZeroed at %dm" % [
			"Bolt rifle",
			rifle.in_magazine, rifle.reserve,
			("%dm" % int(range_m)) if range_m > 0.5 else "--",
			int(rifle.zeroed_at)]
		if rifle.is_reloading():
			_readout.text += "\n[color=#ecb84f]Reloading...[/color]"
		return
	if camera == null:
		return
	var dof := camera.depth_of_field_range()
	var err := camera.exposure_error()
	var err_color := "#8cd280" if absf(err) < 0.5 else ("#eaa953" if absf(err) < 1.5 else "#e07068")
	var far_text: String = "inf" if dof.y >= 3999.0 else "%.1fm" % dof.y
	_readout.text = "[b]%s[/b]\n%s\nFocus %.1fm %s  ·  DoF %.1f-%s\n[color=%s]%+.1f EV[/color]  ·  %s" % [
		camera.lens.short_name,
		camera.settings_summary(),
		camera.focus_distance,
		"AF" if camera.autofocus else "MF",
		dof.x, far_text,
		err_color, err,
		"steady" if camera.shake_risk() < 0.35 else "[color=#e07068]shake[/color]",
	]


## Feeds the sight what it needs to be honest: whether the rifle is up, whether
## there is a round ready, how steady the player is, and the range to whatever
## is under the crosshair.
func _update_rifle_sight() -> void:
	viewfinder.rifle_active = rifle != null and rifle.active
	if not viewfinder.rifle_active:
		return
	viewfinder.rifle_aimed = rifle.aimed
	viewfinder.rifle_ready = rifle.in_magazine > 0
	# Sway comes off stamina: a winded hunter cannot hold a sight still.
	viewfinder.rifle_sway = clampf(1.0 - player.stamina, 0.0, 1.0) \
		* (0.4 if player.crouched else 1.0)
	viewfinder.rifle_range = 0.0
	if not rifle.aimed:
		return
	var cam := player.camera()
	var from := cam.global_position
	var to := from + (-cam.global_transform.basis.z) * Rifle.MAX_RANGE
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = Rifle.HIT_MASK
	query.exclude = [player.get_rid()]
	var hit := player.get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		viewfinder.rifle_range = from.distance_to(hit["position"])


func _update_viewfinder() -> void:
	viewfinder.player_yaw = player.rig.yaw
	_update_rifle_sight()
	if tracker != null:
		viewfinder.listening = tracker.listening
		viewfinder.listen_contacts = tracker.contacts
		viewfinder.scan_charge = tracker.scan_progress() if tracker.scanning else 0.0
	# Boxes around subjects the scorer would recognise.
	viewfinder.subject_marks.clear()
	if camera != null and camera.raised and wildlife != null:
		var cam := player.camera()
		var vp := _root.size
		for node: Node3D in wildlife.subjects():
			if not is_instance_valid(node):
				continue
			var info: Dictionary = node.subject_info()
			var pos: Vector3 = info["position"]
			if not cam.is_position_in_frustum(pos):
				continue
			var d := cam.global_position.distance_to(pos)
			if d > 260.0:
				continue
			var screen := cam.unproject_position(pos)
			var apparent := float(info.get("radius", 0.5)) * 2.0 / maxf(
				2.0 * d * tan(deg_to_rad(cam.fov) * 0.5), 0.001)
			viewfinder.subject_marks.append({"pos": screen, "size": apparent})


func _update_scan(delta: float) -> void:
	if tracker == null:
		return
	if tracker.listening:
		_scan_panel.visible = true
		if tracker.contacts.is_empty():
			_listen_label.text = "Listening... nothing moving."
		else:
			var lines: Array[String] = []
			for c: Dictionary in tracker.contacts:
				var who: String = c["name"] if c["known"] else "something"
				lines.append("%s - %s, %s" % [who, c["band"],
					tracker._compass(float(c["bearing"]))])
			_listen_label.text = "\n".join(lines)
	else:
		_listen_label.text = ""
		if _scan_clear > 0.0:
			_scan_clear -= delta
			if _scan_clear <= 0.0:
				_clear_scan()
		elif _scan_box.get_child_count() == 0:
			_scan_panel.visible = false


func _on_scan_report(lines: Array) -> void:
	_clear_scan()
	for line: String in lines:
		_scan_box.add_child(UITheme.label("· %s" % line, 13, UITheme.INK))
	_scan_panel.visible = true
	_scan_clear = 9.0


func _clear_scan() -> void:
	for child in _scan_box.get_children():
		child.queue_free()
	if not (tracker != null and tracker.listening):
		_scan_panel.visible = false


func _refresh_contracts() -> void:
	for child in _contract_box.get_children():
		child.queue_free()
	if board == null:
		return
	for c in board.active():
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 0)
		box.add_child(UITheme.label(c.title, 14, UITheme.INK))
		box.add_child(UITheme.label("%s  ·  %s" % [c.requirement_text(), c.progress_text()],
			11, UITheme.INK_FAINT))
		_contract_box.add_child(box)


func _on_tool_changed(tool_id: String) -> void:
	_tool_label.text = "Camera" if tool_id == "camera" else "Rifle"


func _on_ammo(_in_magazine: int, _reserve: int) -> void:
	pass


func _on_toast(text: String, kind: String) -> void:
	var color := UITheme.INK
	match kind:
		"discovery":
			color = UITheme.ACCENT
		"warn", "hunt":
			color = UITheme.WARN
		"unlock", "contract":
			color = UITheme.GOOD
		_:
			color = UITheme.INK
	var panel := UITheme.panel(Color(0.05, 0.06, 0.07, 0.92))
	var l := UITheme.label(text, 15, color)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(420, 0)
	panel.add_child(l)
	panel.modulate.a = 0.0
	_toast_box.add_child(panel)
	_toasts.append({"node": panel, "life": TOAST_LIFETIME})
	if _toasts.size() > 4:
		var oldest: Dictionary = _toasts.pop_front()
		if is_instance_valid(oldest["node"]):
			oldest["node"].queue_free()


func _update_toasts(delta: float) -> void:
	for i in range(_toasts.size() - 1, -1, -1):
		var t: Dictionary = _toasts[i]
		var node: Control = t["node"]
		if not is_instance_valid(node):
			_toasts.remove_at(i)
			continue
		t["life"] = float(t["life"]) - delta
		var life: float = t["life"]
		if life <= 0.0:
			node.queue_free()
			_toasts.remove_at(i)
			continue
		# Fade in fast, hold, fade out.
		var alpha := 1.0
		if life > TOAST_LIFETIME - 0.25:
			alpha = (TOAST_LIFETIME - life) / 0.25
		elif life < 0.7:
			alpha = life / 0.7
		node.modulate.a = clampf(alpha, 0.0, 1.0)


func show_prompt(text: String) -> void:
	_prompt.text = text
	_prompt.visible = text != ""
