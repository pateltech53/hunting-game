class_name PauseMenu
extends Control
## Pause: resume, book, settings, or back to the title - and the one place
## that answers "what are the controls" and "how do I get my mouse back".

signal resumed
signal open_book_requested
signal open_sandbox_requested

var _mode_buttons: Array[Button] = []
var _controls_box: VBoxContainer
var _blurb: Label


func _ready() -> void:
	UITheme.full_screen(self)
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(UITheme.scrim(0.80))

	var panel := UITheme.panel(UITheme.PANEL_SOLID, 6)
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -400
	panel.offset_right = 400
	panel.offset_top = -290
	panel.offset_bottom = 290
	add_child(panel)

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 26)
	panel.add_child(columns)

	# ------------------------------------------------------------ left column
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	box.custom_minimum_size = Vector2(300, 0)
	columns.add_child(box)

	box.add_child(UITheme.heading("Paused", 28))
	box.add_child(UITheme.label("%s  ·  %s" % [Game.world_name, Game.mode_label()], 13,
		UITheme.INK_DIM))
	box.add_child(UITheme.separator())

	var resume := UITheme.button("Resume")
	resume.pressed.connect(_resume)
	box.add_child(resume)

	var book := UITheme.button("Discovery Book")
	book.pressed.connect(func() -> void:
		AudioDirector.play("ui_click", -14.0)
		open_book_requested.emit())
	box.add_child(book)

	if Game.is_sandbox():
		var sandbox := UITheme.button("Sandbox Controls")
		sandbox.pressed.connect(func() -> void:
			AudioDirector.play("ui_click", -14.0)
			open_sandbox_requested.emit())
		box.add_child(sandbox)

	var options := UITheme.button("Settings")
	options.pressed.connect(func() -> void:
		AudioDirector.play("ui_click", -14.0)
		add_child(SettingsPanel.new()))
	box.add_child(options)

	box.add_child(UITheme.spacer(6))
	box.add_child(UITheme.label("CONTROL MODE", 11, UITheme.ACCENT))
	for mode: int in [Settings.ControlMode.COMPUTER, Settings.ControlMode.MOUSE,
			Settings.ControlMode.CONTROLLER]:
		var b := UITheme.button(Settings.CONTROL_MODE_NAMES[mode])
		b.pressed.connect(_choose_mode.bind(mode))
		box.add_child(b)
		_mode_buttons.append(b)
	_blurb = UITheme.label("", 11, UITheme.INK_DIM)
	_blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_blurb.custom_minimum_size = Vector2(300, 30)
	box.add_child(_blurb)

	box.add_child(UITheme.spacer(6))
	var quit := UITheme.button("Save and leave the field")
	quit.pressed.connect(func() -> void:
		AudioDirector.play("ui_back", -10.0)
		Game.set_paused(false)
		Game.quit_to_menu())
	box.add_child(quit)

	# ----------------------------------------------------------- right column
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 4)
	right.custom_minimum_size = Vector2(400, 0)
	columns.add_child(right)
	right.add_child(UITheme.heading("Controls", 20))
	_controls_box = VBoxContainer.new()
	_controls_box.add_theme_constant_override("separation", 2)
	right.add_child(_controls_box)

	_refresh()


func _choose_mode(mode: int) -> void:
	AudioDirector.play("ui_click", -14.0)
	Settings.set_control_mode(mode as Settings.ControlMode)
	_refresh()


## Repaints the mode buttons and the binding list for whichever mode is live.
func _refresh() -> void:
	var modes := [Settings.ControlMode.COMPUTER, Settings.ControlMode.MOUSE,
		Settings.ControlMode.CONTROLLER]
	for i in _mode_buttons.size():
		var chosen: bool = modes[i] == Settings.control_mode
		_mode_buttons[i].text = "%s  %s" % ["●" if chosen else "○",
			Settings.CONTROL_MODE_NAMES[modes[i]]]
		_mode_buttons[i].modulate = Color(1, 1, 1, 1.0 if chosen else 0.62)
	_blurb.text = Settings.CONTROL_MODE_BLURBS[Settings.control_mode]

	for child in _controls_box.get_children():
		child.queue_free()
	for row: Array in Settings.controls_reference():
		var line := HBoxContainer.new()
		var what := UITheme.label(String(row[0]), 12, UITheme.INK_DIM)
		what.custom_minimum_size = Vector2(190, 0)
		line.add_child(what)
		line.add_child(UITheme.label(String(row[1]), 12))
		_controls_box.add_child(line)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		_resume()
		get_viewport().set_input_as_handled()


## Resuming is also how you hand the pointer back to the camera: in Mouse mode
## the cursor is recaptured here, which is the fix for a pause that leaves you
## with a loose cursor and no way to look around.
func _resume() -> void:
	AudioDirector.play("ui_back", -14.0)
	resumed.emit()
	queue_free()
