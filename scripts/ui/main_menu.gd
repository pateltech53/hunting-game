class_name MainMenu
extends Control
## Title screen: choose a mode, pick or type a world seed, or just open the
## Discovery Book and look at what you have already found.

var _seed_field: LineEdit
var _seed_value := 0
var _mode: Game.Mode = Game.Mode.EXPEDITION
var _mode_buttons: Array[Button] = []
var _summary: Label
var _preview: MapView
var _preview_gen: TerrainGenerator


func _ready() -> void:
	UITheme.full_screen(self)
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS
	_seed_value = int(SaveSystem.profile.get("last_seed", 0))
	if _seed_value == 0:
		_seed_value = randi() & 0x7FFFFFFF
	_build()
	_refresh_preview()


func _build() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.035, 0.045, 0.052)
	UITheme.full_screen(bg)
	add_child(bg)

	var columns := HBoxContainer.new()
	columns.set_anchors_preset(Control.PRESET_FULL_RECT)
	columns.offset_left = 70
	columns.offset_right = -70
	columns.offset_top = 50
	columns.offset_bottom = -50
	columns.add_theme_constant_override("separation", 40)
	add_child(columns)

	# --- left: title and actions -------------------------------------------
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 8)
	left.custom_minimum_size = Vector2(400, 0)
	columns.add_child(left)

	left.add_child(UITheme.label("WILDLIGHT", 52, UITheme.ACCENT))
	left.add_child(UITheme.label("A voxel photography and hunting game", 15, UITheme.INK_DIM))
	left.add_child(UITheme.spacer(14))

	left.add_child(UITheme.label("MODE", 12, UITheme.ACCENT_DIM))
	var modes := VBoxContainer.new()
	modes.add_theme_constant_override("separation", 4)
	for entry: Array in [
		[Game.Mode.EXPEDITION, "Expedition", "Assignments, reputation, lenses to earn."],
		[Game.Mode.FREE_ROAM, "Free Roam", "The same world, no assignments. Just go."],
		[Game.Mode.SANDBOX, "Sandbox", "Every lens unlocked. Control time, weather and wildlife."],
	]:
		var b := UITheme.button(entry[1])
		b.tooltip_text = entry[2]
		b.pressed.connect(_on_mode.bind(entry[0]))
		modes.add_child(b)
		_mode_buttons.append(b)
	left.add_child(modes)
	_highlight_mode()

	left.add_child(UITheme.spacer(10))
	left.add_child(UITheme.label("WORLD SEED", 12, UITheme.ACCENT_DIM))
	var seed_row := HBoxContainer.new()
	seed_row.add_theme_constant_override("separation", 6)
	_seed_field = LineEdit.new()
	_seed_field.text = str(_seed_value)
	_seed_field.custom_minimum_size = Vector2(180, 38)
	_seed_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_seed_field.text_changed.connect(_on_seed_typed)
	seed_row.add_child(_seed_field)
	var dice := UITheme.button("Roll", false)
	dice.custom_minimum_size = Vector2(90, 38)
	dice.pressed.connect(func() -> void:
		_seed_value = randi() & 0x7FFFFFFF
		_seed_field.text = str(_seed_value)
		AudioDirector.play("ui_click", -14.0)
		_refresh_preview())
	seed_row.add_child(dice)
	left.add_child(seed_row)

	_summary = UITheme.label("", 13, UITheme.INK_DIM)
	_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_summary.custom_minimum_size = Vector2(380, 44)
	left.add_child(_summary)

	left.add_child(UITheme.spacer(10))
	var start := UITheme.button("Head out")
	start.pressed.connect(_start)
	left.add_child(start)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var book := UITheme.button("Discovery Book", false)
	book.custom_minimum_size = Vector2(0, 38)
	book.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	book.pressed.connect(_open_book)
	row.add_child(book)
	var options := UITheme.button("Settings", false)
	options.custom_minimum_size = Vector2(0, 38)
	options.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	options.pressed.connect(_open_settings)
	row.add_child(options)
	left.add_child(row)

	var quit := UITheme.button("Quit", false)
	quit.custom_minimum_size = Vector2(0, 34)
	quit.pressed.connect(func() -> void: Game.quit_game())
	left.add_child(quit)

	# --- right: preview and career ------------------------------------------
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 10)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(right)

	_preview = MapView.new()
	_preview.custom_minimum_size = Vector2(420, 420)
	_preview.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_preview.show_player = false
	_preview.span = 2600.0
	_preview.resolution = 112
	right.add_child(_preview)

	right.add_child(_career_panel())


func _career_panel() -> Control:
	var panel := UITheme.panel()
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 3)
	var stats: Dictionary = SaveSystem.profile.get("stats", {})
	var progress: Dictionary = SaveSystem.profile.get("progress", {})
	box.add_child(UITheme.label("FIELD RECORD", 12, UITheme.ACCENT_DIM))
	box.add_child(UITheme.label("%d of %d species in the book" % [
		Codex.discovered_count(), SpeciesLibrary.total_count()], 16))
	box.add_child(UITheme.label(
		"%d photographs  ·  best score %d  ·  reputation %d" % [
			int(float(stats.get("photos_taken", 0.0))),
			int(float(stats.get("best_photo_score", 0.0))),
			int(progress.get("reputation", 0))], 13, UITheme.INK_DIM))
	var lenses: Array = progress.get("unlocked_lenses", [])
	box.add_child(UITheme.label("%d of %d lenses unlocked" % [lenses.size(),
		LensLibrary.ids().size()], 13, UITheme.INK_DIM))
	var hours := float(stats.get("time_played", 0.0)) / 3600.0
	box.add_child(UITheme.label("%.1f hours in the field  ·  %.1f km walked" % [
		hours, float(stats.get("distance_walked", 0.0)) * 0.001], 13, UITheme.INK_DIM))
	panel.add_child(box)
	return panel


func _on_mode(mode: Game.Mode) -> void:
	_mode = mode
	AudioDirector.play("ui_click", -14.0)
	_highlight_mode()


func _highlight_mode() -> void:
	var modes := [Game.Mode.EXPEDITION, Game.Mode.FREE_ROAM, Game.Mode.SANDBOX]
	for i in _mode_buttons.size():
		_mode_buttons[i].modulate = Color(1, 1, 1) if modes[i] == _mode \
			else Color(0.72, 0.72, 0.72)


func _on_seed_typed(text: String) -> void:
	var digits := ""
	for c: String in text:
		if c >= "0" and c <= "9":
			digits += c
	if digits == "":
		_seed_value = 1
	else:
		_seed_value = int(digits) & 0x7FFFFFFF
	_refresh_preview()


func _refresh_preview() -> void:
	_preview_gen = TerrainGenerator.new(_seed_value)
	_preview.setup(_preview_gen)
	_preview.centre = Vector2.ZERO
	_preview.refresh(true)

	# Describe the world by sampling a coarse grid of biomes.
	var counts := {}
	for i in 12:
		for j in 12:
			var x := (float(i) - 5.5) * 190.0
			var z := (float(j) - 5.5) * 190.0
			var id := _preview_gen.biome_at(x, z)
			counts[id] = int(counts.get(id, 0)) + 1
	var ranked: Array = counts.keys()
	ranked.sort_custom(func(a: String, b: String) -> bool:
		return int(counts[a]) > int(counts[b]))
	var names: Array[String] = []
	for i in mini(3, ranked.size()):
		names.append(BiomeLibrary.display_name(ranked[i]))
	var spawn := _preview_gen.find_flat_ground(Vector2.ZERO, 120.0, 60)
	_summary.text = "%s — mostly %s. You start at %d, %d." % [
		Game.random_world_name(_seed_value), ", ".join(names),
		int(spawn.x), int(spawn.z)]


func _start() -> void:
	AudioDirector.play("ui_click", -8.0)
	Game.start_game(_mode, _seed_value)


func _open_book() -> void:
	AudioDirector.play("ui_click", -14.0)
	var book := DiscoveryBook.new()
	book.setup(_preview_gen)
	add_child(book)


func _open_settings() -> void:
	AudioDirector.play("ui_click", -14.0)
	add_child(SettingsPanel.new())
