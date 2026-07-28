class_name PauseMenu
extends Control
## Pause: resume, book, settings, or back to the title.

signal resumed
signal open_book_requested
signal open_sandbox_requested


func _ready() -> void:
	UITheme.full_screen(self)
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(UITheme.scrim(0.80))

	var panel := UITheme.panel(UITheme.PANEL_SOLID, 6)
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -190
	panel.offset_right = 190
	panel.offset_top = -220
	panel.offset_bottom = 220
	add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)

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

	box.add_child(UITheme.spacer(8))
	var quit := UITheme.button("Save and leave the field")
	quit.pressed.connect(func() -> void:
		AudioDirector.play("ui_back", -10.0)
		Game.set_paused(false)
		Game.quit_to_menu())
	box.add_child(quit)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		_resume()
		get_viewport().set_input_as_handled()


func _resume() -> void:
	AudioDirector.play("ui_back", -14.0)
	resumed.emit()
	queue_free()
