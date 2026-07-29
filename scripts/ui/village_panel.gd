class_name VillagePanel
extends Control
## What a settlement is for: sell the pictures, sell the meat, buy the gear.
##
## One panel rather than three separate shopfronts, because walking between
## buildings to find the right counter is friction without interest.

signal closed

var _funds_label: Label
var _photo_button: Button
var _meat_button: Button
var _catalogue: VBoxContainer
var _village_name := "the village"


func setup(village_name: String) -> void:
	_village_name = village_name


func _ready() -> void:
	UITheme.full_screen(self)
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(UITheme.scrim(0.82))

	var panel := UITheme.panel(UITheme.PANEL_SOLID, 6)
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -380
	panel.offset_right = 380
	panel.offset_top = -280
	panel.offset_bottom = 280
	add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)

	box.add_child(UITheme.heading(_village_name, 26))
	_funds_label = UITheme.label("", 15, UITheme.ACCENT)
	box.add_child(_funds_label)
	box.add_child(UITheme.separator())

	box.add_child(UITheme.eyebrow("Wildlife Centre"))
	_photo_button = UITheme.button("")
	_photo_button.pressed.connect(_sell_photos)
	box.add_child(_photo_button)

	box.add_child(UITheme.eyebrow("Butcher"))
	_meat_button = UITheme.button("")
	_meat_button.pressed.connect(_sell_meat)
	box.add_child(_meat_button)

	box.add_child(UITheme.spacer(4))
	box.add_child(UITheme.eyebrow("Outfitter"))
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 230)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	_catalogue = VBoxContainer.new()
	_catalogue.add_theme_constant_override("separation", 6)
	_catalogue.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_catalogue)

	var close := UITheme.button("Back to the field")
	close.pressed.connect(_close)
	box.add_child(close)

	_refresh()


func _refresh() -> void:
	_funds_label.text = "$%d in hand" % Bank.funds()

	var count := SaveSystem.unsold_count()
	var worth := SaveSystem.unsold_total()
	if count > 0:
		_photo_button.text = "Sell %d photograph%s  ·  $%d" % [count,
			"" if count == 1 else "s", worth]
		_photo_button.disabled = false
	else:
		_photo_button.text = "No frames to sell yet"
		_photo_button.disabled = true

	var larder: float = float(SaveSystem.profile.get("progress", {}).get("larder", 0.0))
	if larder > 0.01:
		_meat_button.text = "Sell %.1f kg of meat  ·  $%d" % [larder,
			Economy.meat_price(larder)]
		_meat_button.disabled = false
	else:
		_meat_button.text = "Nothing in the pack"
		_meat_button.disabled = true

	for child in _catalogue.get_children():
		child.queue_free()
	for item: Dictionary in Economy.CATALOGUE:
		_catalogue.add_child(_gear_row(item))


func _gear_row(item: Dictionary) -> Control:
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 1)
	var owned: bool = Bank.owns(String(item["id"]))
	var button := UITheme.button("%s  ·  %s" % [item["name"],
		"owned" if owned else "$%d" % int(item["price"])])
	button.disabled = owned or not Bank.can_afford(int(item["price"]))
	button.pressed.connect(func() -> void:
		if Bank.buy(String(item["id"])):
			_refresh())
	row.add_child(button)
	var blurb := UITheme.label(String(item["blurb"]), 11, UITheme.INK_DIM)
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	blurb.custom_minimum_size = Vector2(690, 0)
	row.add_child(blurb)
	return row


func _sell_photos() -> void:
	var amount := SaveSystem.take_unsold()
	if amount <= 0:
		return
	Bank.add_funds(amount)
	var progress: Dictionary = SaveSystem.profile.get("progress", {})
	progress["earned_total"] = int(progress.get("earned_total", 0)) + amount
	SaveSystem.profile["progress"] = progress
	Achievements.check_all()
	AudioDirector.play("score_great", -9.0)
	Game.notify("The centre pays $%d for your frames." % amount, "info")
	SaveSystem.save_profile()
	_refresh()


func _sell_meat() -> void:
	var progress: Dictionary = SaveSystem.profile.get("progress", {})
	var larder := float(progress.get("larder", 0.0))
	if larder <= 0.01:
		return
	var amount := Economy.meat_price(larder)
	progress["larder"] = 0.0
	SaveSystem.profile["progress"] = progress
	Bank.add_funds(amount)
	AudioDirector.play("score_good", -10.0)
	Game.notify("The butcher takes the lot for $%d." % amount, "info")
	SaveSystem.save_profile()
	_refresh()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") or event.is_action_pressed("interact"):
		_close()
		get_viewport().set_input_as_handled()


func _close() -> void:
	AudioDirector.play("ui_back", -14.0)
	closed.emit()
	queue_free()
