class_name SettingsPanel
extends Control
## Options, shared by the main menu and the pause menu.

signal closed

const QUALITY_NAMES := ["Potato", "Low", "Medium", "High", "Ultra"]


func _ready() -> void:
	UITheme.full_screen(self)
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(UITheme.scrim(0.85))

	var panel := UITheme.panel(UITheme.PANEL_SOLID, 6)
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -320
	panel.offset_right = 320
	panel.offset_top = -290
	panel.offset_bottom = 290
	add_child(panel)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	box.custom_minimum_size = Vector2(600, 0)
	scroll.add_child(box)

	box.add_child(UITheme.heading("Settings", 26))
	box.add_child(UITheme.separator())

	box.add_child(UITheme.eyebrow("Display"))
	var quality := OptionButton.new()
	for i in QUALITY_NAMES.size():
		quality.add_item(QUALITY_NAMES[i], i)
	quality.selected = int(Settings.quality)
	quality.item_selected.connect(func(index: int) -> void:
		Settings.quality = index as Settings.Quality
		Settings.apply()
		Game.notify("Quality set to %s. Reload the world to rebuild terrain."
			% QUALITY_NAMES[index], "info"))
	box.add_child(_row("Quality", quality))

	box.add_child(_slider_row("View distance", 3, 10, 1, Settings.view_distance_chunks,
		func(v: float) -> void:
			Settings.view_distance_chunks = int(v)
			Settings.apply()))
	box.add_child(_slider_row("Field of view", 60, 100, 1, Settings.fov,
		func(v: float) -> void:
			Settings.fov = v
			Settings.apply()))
	box.add_child(_check_row("Volumetric fog", Settings.volumetric_fog,
		func(on: bool) -> void:
			Settings.volumetric_fog = on
			Settings.apply()))
	box.add_child(_slider_row("Photo resolution", 800, 2560, 80,
		float(Settings.photo_resolution),
		func(v: float) -> void:
			Settings.photo_resolution = int(v)
			Settings.apply()))

	box.add_child(UITheme.spacer(6))
	box.add_child(UITheme.eyebrow("Camera"))
	box.add_child(_check_row("Viewfinder grid", Settings.show_viewfinder_grid,
		func(on: bool) -> void:
			Settings.show_viewfinder_grid = on
			Settings.apply()))
	box.add_child(_check_row("Live histogram", Settings.show_histogram,
		func(on: bool) -> void:
			Settings.show_histogram = on
			Settings.apply()))

	box.add_child(UITheme.spacer(6))
	box.add_child(UITheme.eyebrow("Input"))
	box.add_child(_slider_row("Mouse sensitivity", 0.0005, 0.006, 0.0001,
		Settings.mouse_sensitivity,
		func(v: float) -> void:
			Settings.mouse_sensitivity = v
			Settings.apply()))
	box.add_child(_slider_row("Touch sensitivity", 0.001, 0.010, 0.0002,
		Settings.touch_look_sensitivity,
		func(v: float) -> void:
			Settings.touch_look_sensitivity = v
			Settings.apply()))
	box.add_child(_check_row("Invert vertical look", Settings.invert_y,
		func(on: bool) -> void:
			Settings.invert_y = on
			Settings.apply()))
	box.add_child(_check_row("On-screen controls", Settings.touch_controls_enabled,
		func(on: bool) -> void:
			Settings.touch_controls_enabled = on
			Settings.apply()
			Game.notify("On-screen controls %s." % ("on" if on else "off"), "info")))

	box.add_child(UITheme.spacer(6))
	box.add_child(UITheme.eyebrow("Audio"))
	box.add_child(_slider_row("Master", 0.0, 1.0, 0.02, Settings.master_volume,
		func(v: float) -> void:
			Settings.master_volume = v
			Settings.apply()))
	box.add_child(_slider_row("Music", 0.0, 1.0, 0.02, Settings.music_volume,
		func(v: float) -> void:
			Settings.music_volume = v
			Settings.apply()))
	box.add_child(_slider_row("Effects", 0.0, 1.0, 0.02, Settings.sfx_volume,
		func(v: float) -> void:
			Settings.sfx_volume = v
			Settings.apply()))
	box.add_child(_slider_row("Ambience", 0.0, 1.0, 0.02, Settings.ambience_volume,
		func(v: float) -> void:
			Settings.ambience_volume = v
			Settings.apply()))

	box.add_child(UITheme.spacer(10))
	var close := UITheme.button("Back")
	close.pressed.connect(_close)
	box.add_child(close)


func _row(title: String, control: Control) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var l := UITheme.label(title, 15)
	l.custom_minimum_size = Vector2(220, 0)
	row.add_child(l)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(control)
	return row


func _slider_row(title: String, min_v: float, max_v: float, step: float, value: float,
		on_change: Callable) -> Control:
	var slider := UITheme.slider(min_v, max_v, step, value)
	var readout := UITheme.label(_format(value), 13, UITheme.INK_DIM)
	readout.custom_minimum_size = Vector2(70, 0)
	readout.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	slider.value_changed.connect(func(v: float) -> void:
		readout.text = _format(v)
		on_change.call(v))
	var wrapper := HBoxContainer.new()
	wrapper.add_theme_constant_override("separation", 8)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wrapper.add_child(slider)
	wrapper.add_child(readout)
	return _row(title, wrapper)


func _format(v: float) -> String:
	if absf(v) < 0.02 and v != 0.0:
		return "%.4f" % v
	if v == floor(v):
		return "%d" % int(v)
	return "%.2f" % v


func _check_row(title: String, value: bool, on_change: Callable) -> Control:
	var check := CheckBox.new()
	check.button_pressed = value
	check.toggled.connect(func(on: bool) -> void:
		AudioDirector.play("ui_click", -18.0)
		on_change.call(on))
	return _row(title, check)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		_close()
		get_viewport().set_input_as_handled()


func _close() -> void:
	Settings.save_settings()
	AudioDirector.play("ui_back", -14.0)
	closed.emit()
	queue_free()
