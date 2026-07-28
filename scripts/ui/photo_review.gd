class_name PhotoReview
extends Control
## The frame you just took, with the critique. Shown briefly after every shot,
## or in full when you want to look at it properly.

signal dismissed

var record: Dictionary = {}
var compact := true

var _timer := 0.0


func setup(photo: Dictionary, is_compact: bool = true) -> void:
	record = photo
	compact = is_compact
	_build()


func _build() -> void:
	UITheme.full_screen(self)
	mouse_filter = Control.MOUSE_FILTER_IGNORE if compact else Control.MOUSE_FILTER_STOP
	if not compact:
		add_child(UITheme.scrim(0.88))

	var panel := UITheme.panel(Color(0.05, 0.055, 0.06, 0.94), 6)
	if compact:
		panel.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
		panel.offset_left = -420
		panel.offset_right = -18
		panel.offset_top = -300
		panel.offset_bottom = -110
	else:
		panel.set_anchors_preset(Control.PRESET_CENTER)
		panel.offset_left = -460
		panel.offset_right = 460
		panel.offset_top = -320
		panel.offset_bottom = 320
	add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 14)

	var image := TextureRect.new()
	image.custom_minimum_size = Vector2(240, 135) if compact else Vector2(520, 293)
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	var tex := _load(record.get("thumb", record.get("path", "")))
	if tex != null:
		image.texture = tex
	top.add_child(image)

	var info := VBoxContainer.new()
	info.add_theme_constant_override("separation", 2)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var grade: String = record.get("grade", "-")
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	var grade_label := UITheme.label(grade, 42, PhotoScorer.grade_color(grade))
	head.add_child(grade_label)
	# Stars and price, because "grade B" says less than five stars and $180.
	var worth := VBoxContainer.new()
	worth.add_theme_constant_override("separation", 0)
	worth.add_child(UITheme.label(Economy.star_text(float(record.get("score", 0.0))),
		20, UITheme.ACCENT))
	var price := int(record.get("price", 0))
	worth.add_child(UITheme.label(
		"worth $%d at the wildlife centre" % price if price > 0
		else "no buyer would take this one", 11, UITheme.INK_DIM))
	head.add_child(worth)
	var score_box := VBoxContainer.new()
	score_box.add_theme_constant_override("separation", 0)
	score_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	score_box.add_child(UITheme.label("%.0f / 100" % float(record.get("score", 0.0)), 20))
	score_box.add_child(UITheme.label(record.get("genre_label", ""), 13, UITheme.ACCENT))
	head.add_child(score_box)
	info.add_child(head)

	var subject: String = record.get("subject_name", "")
	if subject != "":
		info.add_child(UITheme.label("%s  ·  %s  ·  %dm" % [subject,
			record.get("subject_state", ""), int(float(record.get("subject_distance", 0.0)))],
			13, UITheme.INK_DIM))
	info.add_child(UITheme.label("%s  ·  %s" % [record.get("lens_name", ""),
		record.get("settings", "")], 12, UITheme.INK_FAINT))
	info.add_child(UITheme.label("%s  ·  %s  ·  %s" % [record.get("clock", ""),
		record.get("light_phase", ""), BiomeLibrary.display_name(record.get("biome", ""))],
		12, UITheme.INK_FAINT))
	top.add_child(info)
	box.add_child(top)

	box.add_child(UITheme.separator())

	var breakdown: Dictionary = record.get("breakdown", {})
	var bars := GridContainer.new()
	bars.columns = 2 if compact else 3
	bars.add_theme_constant_override("h_separation", 16)
	bars.add_theme_constant_override("v_separation", 3)
	for key: String in ["composition", "subject", "focus", "exposure", "light", "moment"]:
		bars.add_child(_bar(key.capitalize(), float(breakdown.get(key, 0.0))))
	box.add_child(bars)

	var notes: Array = record.get("notes", [])
	if not notes.is_empty():
		box.add_child(UITheme.separator())
		var shown: Array = notes if not compact else notes.slice(0, 3)
		for note: String in shown:
			var l := UITheme.label("· %s" % note, 13, UITheme.INK_DIM)
			l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			l.custom_minimum_size = Vector2(360 if compact else 860, 0)
			box.add_child(l)

	if not compact:
		var buttons := HBoxContainer.new()
		buttons.add_theme_constant_override("separation", 10)
		var close := UITheme.button("Close", false)
		close.custom_minimum_size = Vector2(160, 36)
		close.pressed.connect(_dismiss)
		buttons.add_child(close)
		var discard := UITheme.button("Discard photo", false)
		discard.custom_minimum_size = Vector2(180, 36)
		discard.pressed.connect(func() -> void:
			SaveSystem.delete_photo(record)
			SaveSystem.save_profile()
			Game.notify("Photo discarded.", "info")
			_dismiss())
		buttons.add_child(discard)
		box.add_child(buttons)
	else:
		_timer = 6.0


func _bar(title: String, value: float) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 1)
	box.custom_minimum_size = Vector2(170, 0)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.add_child(UITheme.label(title, 11, UITheme.INK_FAINT))
	var pad := Control.new()
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(pad)
	row.add_child(UITheme.label("%d" % int(value), 11, UITheme.INK))
	box.add_child(row)
	var bar := ProgressBar.new()
	bar.max_value = 100.0
	bar.value = value
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 5)
	var fill := StyleBoxFlat.new()
	fill.bg_color = UITheme.GOOD if value >= 75.0 else (UITheme.ACCENT if value >= 50.0
		else UITheme.BAD)
	fill.set_corner_radius_all(2)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(1, 1, 1, 0.08)
	bg.set_corner_radius_all(2)
	bar.add_theme_stylebox_override("fill", fill)
	bar.add_theme_stylebox_override("background", bg)
	box.add_child(bar)
	return box


func _load(path: String) -> Texture2D:
	if path == "" or not FileAccess.file_exists(path):
		return null
	var img := Image.new()
	if img.load(path) != OK:
		return null
	return ImageTexture.create_from_image(img)


func _process(delta: float) -> void:
	if not compact:
		return
	_timer -= delta
	if _timer <= 0.6:
		modulate.a = clampf(_timer / 0.6, 0.0, 1.0)
	if _timer <= 0.0:
		_dismiss()


func _unhandled_input(event: InputEvent) -> void:
	if compact:
		return
	if event.is_action_pressed("pause") or event.is_action_pressed("interact"):
		_dismiss()
		get_viewport().set_input_as_handled()


func _dismiss() -> void:
	dismissed.emit()
	queue_free()
