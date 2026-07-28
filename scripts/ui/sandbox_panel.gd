class_name SandboxPanel
extends Control
## Sandbox controls: scrub the clock, force weather, drop wildlife in front of
## you, and jump around the world. Everything a photographer would want in
## order to set a shot up deliberately.

signal closed

var sky: SkySystem
var weather: WeatherSystem
var wildlife: WildlifeDirector
var player: Player
var world: VoxelWorld

var _time_slider: HSlider
var _time_label: Label
var _species_picker: OptionButton


func setup(sky_system: SkySystem, weather_system: WeatherSystem,
		director: WildlifeDirector, hunter: Player, voxel_world: VoxelWorld) -> void:
	sky = sky_system
	weather = weather_system
	wildlife = director
	player = hunter
	world = voxel_world


func _ready() -> void:
	UITheme.full_screen(self)
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(UITheme.scrim(0.55))

	var panel := UITheme.panel(UITheme.PANEL_SOLID, 6)
	panel.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	panel.offset_left = -420
	panel.offset_right = -24
	panel.offset_top = -300
	panel.offset_bottom = 300
	add_child(panel)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	box.custom_minimum_size = Vector2(370, 0)
	scroll.add_child(box)

	box.add_child(UITheme.heading("Sandbox", 24))
	box.add_child(UITheme.separator())

	# --- time ---------------------------------------------------------------
	box.add_child(UITheme.eyebrow("Time Of Day"))
	_time_label = UITheme.label("", 15)
	box.add_child(_time_label)
	_time_slider = UITheme.slider(0.0, 23.99, 0.05, sky.time_of_day if sky != null else 12.0)
	_time_slider.value_changed.connect(func(v: float) -> void:
		if sky != null:
			sky.set_time(v)
		_update_time_label())
	box.add_child(_time_slider)

	var freeze := CheckBox.new()
	freeze.text = "Freeze the clock"
	freeze.button_pressed = sky.time_frozen if sky != null else false
	freeze.toggled.connect(func(on: bool) -> void:
		if sky != null:
			sky.time_frozen = on)
	box.add_child(freeze)

	var presets := HBoxContainer.new()
	presets.add_theme_constant_override("separation", 4)
	for entry: Array in [["Dawn", 5.6], ["Golden", 7.2], ["Noon", 12.0],
			["Golden PM", 17.4], ["Blue", 19.4], ["Night", 23.0]]:
		var b := UITheme.button(entry[0], false)
		b.custom_minimum_size = Vector2(0, 30)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(func() -> void:
			if sky != null:
				sky.set_time(entry[1])
				_time_slider.set_value_no_signal(entry[1])
				_update_time_label())
		presets.add_child(b)
	box.add_child(presets)

	box.add_child(_row("Day length (minutes)", UITheme.slider(1.0, 90.0, 1.0,
		sky.day_length_minutes if sky != null else 24.0), func(v: float) -> void:
			if sky != null:
				sky.day_length_minutes = v))

	# --- weather ------------------------------------------------------------
	box.add_child(UITheme.spacer(6))
	box.add_child(UITheme.eyebrow("Weather"))
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	for id: String in WeatherSystem.PRESETS:
		var preset: Dictionary = WeatherSystem.PRESETS[id]
		var b := UITheme.button(preset["name"], false)
		b.custom_minimum_size = Vector2(112, 30)
		b.pressed.connect(func() -> void:
			if weather != null:
				weather.locked = true
				weather.set_weather(id, false)
			AudioDirector.play("ui_click", -16.0))
		grid.add_child(b)
	box.add_child(grid)
	var unlock := CheckBox.new()
	unlock.text = "Let the weather drift on its own"
	unlock.button_pressed = not (weather != null and weather.locked)
	unlock.toggled.connect(func(on: bool) -> void:
		if weather != null:
			weather.locked = not on)
	box.add_child(unlock)

	# --- wildlife -----------------------------------------------------------
	box.add_child(UITheme.spacer(6))
	box.add_child(UITheme.eyebrow("Wildlife"))
	_species_picker = OptionButton.new()
	var ids := SpeciesLibrary.ids()
	for i in ids.size():
		var s := SpeciesLibrary.get_species(ids[i])
		_species_picker.add_item(s.name, i)
	box.add_child(_species_picker)

	var spawn_row := HBoxContainer.new()
	spawn_row.add_theme_constant_override("separation", 4)
	var spawn := UITheme.button("Spawn ahead", false)
	spawn.custom_minimum_size = Vector2(0, 32)
	spawn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spawn.pressed.connect(_spawn_selected)
	spawn_row.add_child(spawn)
	var clear := UITheme.button("Clear all", false)
	clear.custom_minimum_size = Vector2(0, 32)
	clear.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	clear.pressed.connect(func() -> void:
		if wildlife != null:
			wildlife.clear_all()
		Game.notify("Wildlife cleared.", "info"))
	spawn_row.add_child(clear)
	box.add_child(spawn_row)

	# --- travel -------------------------------------------------------------
	box.add_child(UITheme.spacer(6))
	box.add_child(UITheme.eyebrow("Travel"))
	var travel := VBoxContainer.new()
	travel.add_theme_constant_override("separation", 4)
	for biome_id: String in BiomeLibrary.ids():
		var b := UITheme.button("Find %s" % BiomeLibrary.display_name(biome_id), false)
		b.custom_minimum_size = Vector2(0, 30)
		b.pressed.connect(_travel_to.bind(biome_id))
		travel.add_child(b)
	var village := UITheme.button("Nearest village", false)
	village.custom_minimum_size = Vector2(0, 30)
	village.pressed.connect(_travel_to_village)
	travel.add_child(village)
	box.add_child(travel)

	box.add_child(UITheme.spacer(10))
	var close := UITheme.button("Close  (G)")
	close.pressed.connect(_close)
	box.add_child(close)

	_update_time_label()


func _row(title: String, control: Control, on_change: Callable) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var l := UITheme.label(title, 14)
	l.custom_minimum_size = Vector2(180, 0)
	row.add_child(l)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if control is HSlider:
		(control as HSlider).value_changed.connect(on_change)
	row.add_child(control)
	return row


func _update_time_label() -> void:
	if sky == null:
		return
	_time_label.text = "%s   ·   %s   ·   EV %.1f" % [sky.clock_string(),
		sky.light_phase(), sky.scene_ev()]


func _process(_delta: float) -> void:
	if sky != null and not sky.time_frozen:
		_time_slider.set_value_no_signal(sky.time_of_day)
		_update_time_label()


func _spawn_selected() -> void:
	if wildlife == null or player == null:
		return
	var ids := SpeciesLibrary.ids()
	var idx := _species_picker.selected
	if idx < 0 or idx >= ids.size():
		return
	var ahead := player.global_position - player.camera().global_transform.basis.z * 26.0
	wildlife.sandbox_spawn(ids[idx], ahead)


func _travel_to(biome_id: String) -> void:
	if world == null or player == null:
		return
	# Walk outward in a spiral from the player until that biome turns up.
	var origin := Vector2(player.global_position.x, player.global_position.z)
	for ring in range(1, 90):
		var radius := float(ring) * 60.0
		for step in 12:
			var a := TAU * float(step) / 12.0 + float(ring) * 0.4
			var p := origin + Vector2(cos(a), sin(a)) * radius
			if world.biome_at(p.x, p.y) != biome_id:
				continue
			var h := world.surface_height(p.x, p.y)
			if h <= TerrainGenerator.SEA_LEVEL:
				continue
			player.teleport(Vector3(p.x, float(h) + 1.5, p.y))
			Game.notify("Moved to the %s, %d m away." % [
				BiomeLibrary.display_name(biome_id), int(radius)], "info")
			return
	Game.notify("No %s within range of here." % BiomeLibrary.display_name(biome_id), "warn")


func _travel_to_village() -> void:
	if world == null or player == null:
		return
	var sites := Structures.village_sites_near(world.gen, player.global_position.x,
		player.global_position.z, 900.0)
	if sites.is_empty():
		Game.notify("No village within a kilometre.", "warn")
		return
	var best: Dictionary = sites[0]
	var best_d := INF
	for site: Dictionary in sites:
		var d: float = player.global_position.distance_to(site["position"])
		if d < best_d:
			best_d = d
			best = site
	var pos: Vector3 = best["position"]
	player.teleport(Vector3(pos.x, pos.y + 1.5, pos.z))
	Game.notify("Moved to %s." % best["name"], "info")


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("sandbox_panel") or event.is_action_pressed("pause"):
		_close()
		get_viewport().set_input_as_handled()


func _close() -> void:
	AudioDirector.play("ui_back", -14.0)
	closed.emit()
	queue_free()
