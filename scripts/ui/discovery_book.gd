class_name DiscoveryBook
extends Control
## The Discovery Book.
##
## A species enters the book the first time you photograph it, and that first
## photograph becomes the cover of its page for good - unless you find a better
## one later and promote it from the gallery. Everything else on the page has
## to be earned by observation: where you have seen it, when it is out, what it
## was doing, what its prints look like.

signal closed

const PAGE_TABS := ["Field Notes", "Gallery", "Range"]

var gen: TerrainGenerator
var selected_id := ""
var _tab := 0

var _list_box: VBoxContainer
var _detail: VBoxContainer
var _progress: Label
var _cover_rect: TextureRect
var _cover_caption: Label
var _content: VBoxContainer
var _tab_buttons: Array[Button] = []
var _map: MapView


func _ready() -> void:
	UITheme.full_screen(self)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()
	var ids := SpeciesLibrary.ids()
	for id: String in ids:
		if Codex.is_discovered(id):
			selected_id = id
			break
	if selected_id == "" and not ids.is_empty():
		selected_id = ids[0]
	_refresh_list()
	_refresh_detail()


func setup(generator: TerrainGenerator) -> void:
	gen = generator
	if _map != null:
		_map.setup(gen)


func _build() -> void:
	add_child(UITheme.scrim(0.86))

	var frame := PanelContainer.new()
	frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	frame.offset_left = 40
	frame.offset_top = 30
	frame.offset_right = -40
	frame.offset_bottom = -30
	var paper := UITheme.panel_style(UITheme.PAPER, 4, Color(0.32, 0.26, 0.18, 0.6))
	paper.content_margin_left = 20
	paper.content_margin_right = 20
	paper.content_margin_top = 16
	paper.content_margin_bottom = 16
	frame.add_theme_stylebox_override("panel", paper)
	add_child(frame)

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 10)
	frame.add_child(outer)

	# --- header -------------------------------------------------------------
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 16)
	var title := UITheme.label("Discovery Book", 30, UITheme.PAPER_INK)
	header.add_child(title)
	_progress = UITheme.label("", 15, UITheme.PAPER_INK_DIM)
	_progress.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(_progress)
	var pad := Control.new()
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(pad)
	var close := UITheme.paper_button("Close  (Tab)")
	close.custom_minimum_size = Vector2(150, 34)
	close.pressed.connect(_close)
	header.add_child(close)
	outer.add_child(header)

	var rule := Panel.new()
	rule.custom_minimum_size = Vector2(0, 2)
	var rule_style := StyleBoxFlat.new()
	rule_style.bg_color = Color(0.32, 0.26, 0.18, 0.45)
	rule.add_theme_stylebox_override("panel", rule_style)
	outer.add_child(rule)

	# --- two pages ----------------------------------------------------------
	var pages := HBoxContainer.new()
	pages.add_theme_constant_override("separation", 22)
	pages.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(pages)

	var left := ScrollContainer.new()
	left.custom_minimum_size = Vector2(320, 0)
	left.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_list_box = VBoxContainer.new()
	_list_box.add_theme_constant_override("separation", 4)
	_list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_child(_list_box)
	pages.add_child(left)

	var divider := Panel.new()
	divider.custom_minimum_size = Vector2(2, 0)
	var div_style := StyleBoxFlat.new()
	div_style.bg_color = Color(0.32, 0.26, 0.18, 0.35)
	divider.add_theme_stylebox_override("panel", div_style)
	pages.add_child(divider)

	_detail = VBoxContainer.new()
	_detail.add_theme_constant_override("separation", 10)
	_detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pages.add_child(_detail)

	_build_detail_skeleton()


func _build_detail_skeleton() -> void:
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 16)
	_cover_rect = TextureRect.new()
	_cover_rect.custom_minimum_size = Vector2(320, 180)
	_cover_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_cover_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	top.add_child(_cover_rect)

	var head_box := VBoxContainer.new()
	head_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head_box.add_theme_constant_override("separation", 3)
	_cover_caption = UITheme.label("", 13, UITheme.PAPER_INK_DIM)
	_cover_caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	head_box.add_child(_cover_caption)
	top.add_child(head_box)
	_detail.add_child(top)

	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 6)
	for i in PAGE_TABS.size():
		var b := UITheme.paper_button(PAGE_TABS[i])
		b.custom_minimum_size = Vector2(130, 30)
		b.pressed.connect(_on_tab.bind(i))
		tabs.add_child(b)
		_tab_buttons.append(b)
	_detail.add_child(tabs)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_content = VBoxContainer.new()
	_content.add_theme_constant_override("separation", 8)
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_content)
	_detail.add_child(scroll)


func _on_tab(index: int) -> void:
	_tab = index
	AudioDirector.play("ui_move", -16.0)
	_refresh_detail()


# ------------------------------------------------------------------- the list

func _refresh_list() -> void:
	for child in _list_box.get_children():
		child.queue_free()
	var total := SpeciesLibrary.total_count()
	var found := Codex.discovered_count()
	_progress.text = "%d of %d species recorded" % [found, total]

	# Group the list by family so it reads like a real field guide.
	var by_family: Dictionary = {}
	for s: Species in SpeciesLibrary.all():
		if not by_family.has(s.family):
			by_family[s.family] = []
		by_family[s.family].append(s)

	var families: Array = by_family.keys()
	families.sort()
	for family: String in families:
		var header := UITheme.label(family.to_upper(), 12, UITheme.PAPER_INK_DIM)
		_list_box.add_child(header)
		for s: Species in by_family[family]:
			_list_box.add_child(_list_entry(s))
		_list_box.add_child(UITheme.spacer(6))


func _list_entry(s: Species) -> Control:
	var discovered := Codex.is_discovered(s.id)
	var button := Button.new()
	button.custom_minimum_size = Vector2(0, 52)
	button.flat = true
	button.focus_mode = Control.FOCUS_NONE
	button.toggle_mode = false
	button.add_theme_stylebox_override("normal", UITheme.panel_style(
		Color(0.86, 0.82, 0.73) if s.id == selected_id else Color(0, 0, 0, 0), 3,
		Color(0.35, 0.28, 0.18, 0.25) if s.id == selected_id else Color(0, 0, 0, 0)))
	button.add_theme_stylebox_override("hover", UITheme.panel_style(
		Color(0.88, 0.84, 0.76), 3, Color(0.35, 0.28, 0.18, 0.3)))
	button.add_theme_stylebox_override("pressed", UITheme.panel_style(
		Color(0.80, 0.75, 0.65), 3, Color(0.35, 0.28, 0.18, 0.4)))
	button.pressed.connect(func() -> void:
		selected_id = s.id
		AudioDirector.play("ui_move", -18.0)
		_refresh_list()
		_refresh_detail())

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 6
	row.offset_right = -6

	var thumb := TextureRect.new()
	thumb.custom_minimum_size = Vector2(72, 40)
	thumb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	thumb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	if discovered:
		var tex := _load_texture(Codex.entry(s.id).get("cover_thumb", ""))
		if tex != null:
			thumb.texture = tex
	row.add_child(thumb)

	var text_box := VBoxContainer.new()
	text_box.add_theme_constant_override("separation", 0)
	text_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if discovered:
		var e := Codex.entry(s.id)
		text_box.add_child(UITheme.label(s.name, 15, UITheme.PAPER_INK))
		text_box.add_child(UITheme.label("%d photo%s  ·  best %d  ·  %d%% complete" % [
			int(e.get("photo_count", 0)),
			"" if int(e.get("photo_count", 0)) == 1 else "s",
			int(e.get("best_score", 0.0)),
			int(Codex.completion(s.id) * 100.0)], 11, UITheme.PAPER_INK_DIM))
	else:
		var hint := "unrecorded"
		var entry := Codex.entry(s.id)
		if int(entry.get("tracks_found", 0)) + int(entry.get("sign_found", 0)) > 0:
			hint = "sign found, never photographed"
		elif int(entry.get("calls_heard", 0)) > 0:
			hint = "heard but not seen"
		text_box.add_child(UITheme.label("- - - - -", 15, UITheme.PAPER_INK_DIM))
		text_box.add_child(UITheme.label(hint, 11, UITheme.PAPER_INK_DIM))
	row.add_child(text_box)
	button.add_child(row)
	return button


# ----------------------------------------------------------------- the detail

func _refresh_detail() -> void:
	for child in _content.get_children():
		child.queue_free()
	if selected_id == "":
		return
	var s := SpeciesLibrary.get_species(selected_id)
	if s == null:
		return
	var discovered := Codex.is_discovered(selected_id)
	var e := Codex.entry(selected_id)

	for i in _tab_buttons.size():
		_tab_buttons[i].disabled = not discovered
		_tab_buttons[i].modulate = Color(1, 1, 1, 1.0 if i == _tab else 0.7)

	if discovered:
		var tex := _load_texture(e.get("cover_photo", ""))
		_cover_rect.texture = tex
		var when := Time.get_datetime_dict_from_unix_time(int(e.get("first_seen_unix", 0)))
		_cover_caption.text = "%s\n%s\n\nFirst recorded %04d-%02d-%02d at %02d:00 in the %s.\nThis photograph is the cover of the page." % [
			s.name, s.latin,
			when.get("year", 0), when.get("month", 1), when.get("day", 1),
			int(float(e.get("first_seen_hour", 12.0))),
			BiomeLibrary.display_name(e.get("first_seen_biome", ""))]
	else:
		_cover_rect.texture = null
		_cover_caption.text = "%s\n\nNot yet recorded.\n\nA species only enters this book when you photograph it. Track it, listen for it, and get one clean frame." % s.name
		_content.add_child(_unrecorded_hints(s, e))
		return

	match _tab:
		1:
			_build_gallery(s)
		2:
			_build_range(s, e)
		_:
			_build_notes(s, e)


func _unrecorded_hints(s: Species, e: Dictionary) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	box.add_child(UITheme.label("What you know so far", 17, UITheme.PAPER_INK))
	var lines: Array[String] = []
	if int(e.get("calls_heard", 0)) > 0:
		lines.append("You have heard it call %d time(s)." % int(e.get("calls_heard", 0)))
	if int(e.get("tracks_found", 0)) > 0:
		lines.append("You have found its prints %d time(s) - a %s track." % [
			int(e.get("tracks_found", 0)), s.track_shape])
	if int(e.get("sign_found", 0)) > 0:
		lines.append("You have found its sign %d time(s)." % int(e.get("sign_found", 0)))
	var biome := Codex.most_common_biome(s.id)
	if biome != "":
		lines.append("Sign has turned up in the %s." % BiomeLibrary.display_name(biome))
	if lines.is_empty():
		lines.append("Nothing at all. Scan the ground and listen at dawn.")
	for line: String in lines:
		box.add_child(UITheme.label("· %s" % line, 14, UITheme.PAPER_INK_DIM))
	return box


func _build_notes(s: Species, e: Dictionary) -> void:
	var stats := HBoxContainer.new()
	stats.add_theme_constant_override("separation", 22)
	stats.add_child(_stat("Rarity", s.rarity_label()))
	stats.add_child(_stat("Size", s.size_label()))
	stats.add_child(_stat("Photos", str(int(e.get("photo_count", 0)))))
	stats.add_child(_stat("Best score", "%d" % int(e.get("best_score", 0.0))))
	if int(e.get("harvested", 0)) > 0:
		stats.add_child(_stat("Harvested", str(int(e.get("harvested", 0)))))
	_content.add_child(stats)

	_content.add_child(_field("Habitat", s.habitat_note, Codex.FIELD_HABITAT,
		"Sight it in two different places to learn where it lives."))

	var activity := s.activity_label()
	var peak := Codex.peak_hours(s.id)
	if peak.x >= 0:
		activity += "\nYour own sightings cluster between %02d:00 and %02d:00." % [peak.x, peak.y]
	_content.add_child(_field("When it is out", activity, Codex.FIELD_ACTIVITY,
		"Observe it at three different hours to chart its activity."))

	_content.add_child(_field("Diet", s.diet, Codex.FIELD_DIET,
		"Watch it feed to learn what it eats."))
	_content.add_child(_field("Tendencies", s.behaviour_note, Codex.FIELD_BEHAVIOUR,
		"Keep observing. Behaviour unlocks after you have seen it do several things."))

	var features := s.features_note
	var measurements: Dictionary = e.get("measurements", {})
	if not measurements.is_empty():
		var bits: Array[String] = []
		if measurements.has("weight"):
			bits.append("heaviest recorded %.1f kg" % float(measurements["weight"]))
		if measurements.has("points"):
			bits.append("best antlers %d points" % int(measurements["points"]))
		if not bits.is_empty():
			features += "\nYour records: " + ", ".join(bits) + "."
	_content.add_child(_field("Features", features, Codex.FIELD_FEATURES,
		"Three good photographs, or a harvest, will fill this in."))

	_content.add_child(_field("Tracks and sign", s.track_note, Codex.FIELD_TRACKS,
		"Find its prints or sign three times to record them."))

	var behaviours: Dictionary = e.get("behaviours", {})
	if not behaviours.is_empty():
		var seen: Array[String] = []
		for b: String in behaviours:
			seen.append("%s (x%d)" % [b, int(behaviours[b])])
		_content.add_child(UITheme.label("Observed behaviour", 16, UITheme.PAPER_INK))
		var l := UITheme.label(", ".join(seen), 13, UITheme.PAPER_INK_DIM)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_content.add_child(l)


func _stat(title: String, value: String) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	box.add_child(UITheme.label(title.to_upper(), 10, UITheme.PAPER_INK_DIM))
	box.add_child(UITheme.label(value, 16, UITheme.PAPER_INK))
	return box


func _field(title: String, body: String, gate: String, locked_hint: String) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 1)
	var revealed := Codex.is_revealed(selected_id, gate)
	box.add_child(UITheme.label(title, 16, UITheme.PAPER_INK))
	var text := body if revealed else locked_hint
	var l := UITheme.label(text, 13,
		UITheme.PAPER_INK_DIM if revealed else Color(0.55, 0.48, 0.38))
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(420, 0)
	box.add_child(l)
	return box


func _build_gallery(s: Species) -> void:
	var photos := SaveSystem.photos_for_species(s.id)
	if photos.is_empty():
		_content.add_child(UITheme.label("No photographs in the gallery yet.", 14,
			UITheme.PAPER_INK_DIM))
		return
	photos.reverse()
	_content.add_child(UITheme.label(
		"%d photograph%s. Click one to make it the cover." % [photos.size(),
		"" if photos.size() == 1 else "s"], 13, UITheme.PAPER_INK_DIM))
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	for record: Dictionary in photos:
		grid.add_child(_gallery_card(s, record))
	_content.add_child(grid)


func _gallery_card(s: Species, record: Dictionary) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	var button := Button.new()
	button.custom_minimum_size = Vector2(190, 107)
	button.flat = true
	button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.expand_icon = true
	var tex := _load_texture(record.get("thumb", record.get("path", "")))
	if tex != null:
		button.icon = tex
	button.pressed.connect(func() -> void:
		Codex.set_cover(s.id, record)
		SaveSystem.save_profile()
		AudioDirector.play("ui_click", -14.0)
		Game.notify("Cover updated for %s" % s.name, "info")
		_refresh_list()
		_refresh_detail())
	box.add_child(button)
	var grade: String = record.get("grade", "-")
	box.add_child(UITheme.label("%s  %d  ·  %s" % [grade, int(float(record.get("score", 0.0))),
		record.get("genre_label", "")], 11, UITheme.PAPER_INK))
	box.add_child(UITheme.label("%s  ·  %s" % [record.get("clock", ""),
		record.get("light_phase", "")], 10, UITheme.PAPER_INK_DIM))
	return box


func _build_range(s: Species, e: Dictionary) -> void:
	var sightings: Array = e.get("sightings", [])
	if sightings.is_empty():
		_content.add_child(UITheme.label(
			"No sightings plotted yet. The map fills in as you find it in the field.",
			14, UITheme.PAPER_INK_DIM))
		return
	if _map == null:
		_map = MapView.new()
		_map.setup(gen)
	if _map.get_parent() != null:
		_map.get_parent().remove_child(_map)
	_map.custom_minimum_size = Vector2(380, 380)
	_map.show_player = false
	_map.set_markers_from_sightings(sightings, Color(0.93, 0.60, 0.25, 0.95))
	_map.frame_markers()
	_content.add_child(_map)
	_map.refresh(true)

	var biomes: Dictionary = e.get("biomes", {})
	var lines: Array[String] = []
	for id: String in biomes:
		lines.append("%s (%d)" % [BiomeLibrary.display_name(id), int(biomes[id])])
	if not lines.is_empty():
		_content.add_child(UITheme.label("Seen in: " + ", ".join(lines), 13,
			UITheme.PAPER_INK_DIM))
	_content.add_child(UITheme.label(
		"%d plotted sighting%s in this world." % [sightings.size(),
		"" if sightings.size() == 1 else "s"], 12, UITheme.PAPER_INK_DIM))


func _load_texture(path: String) -> Texture2D:
	if path == "" or not FileAccess.file_exists(path):
		return null
	var img := Image.new()
	if img.load(path) != OK:
		return null
	return ImageTexture.create_from_image(img)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("book") or event.is_action_pressed("pause"):
		_close()
		get_viewport().set_input_as_handled()


func _close() -> void:
	AudioDirector.play("ui_back", -14.0)
	closed.emit()
	queue_free()
