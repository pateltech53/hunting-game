class_name TouchControls
extends Control
## Landscape touch layout: a thumbstick on the left, look-drag on the right,
## and the buttons you actually need in the field along the edges.
##
## Drag anywhere on the right half to look; the same gesture taps through to
## the shutter if you barely move.

const STICK_RADIUS := 92.0
const TAP_SLOP := 14.0
const TAP_TIME := 0.28

var player: Player
var camera: PhotoCamera

var _stick_touch := -1
var _stick_origin := Vector2.ZERO
var _stick_pos := Vector2.ZERO
var _look_touch := -1
var _look_last := Vector2.ZERO
var _look_start := Vector2.ZERO
var _look_time := 0.0
var _buttons: Array[Dictionary] = []


func _ready() -> void:
	UITheme.full_screen(self)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_buttons()


func bind(p: Player, photo_camera: PhotoCamera) -> void:
	player = p
	camera = photo_camera


func _build_buttons() -> void:
	var right := VBoxContainer.new()
	right.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	right.offset_left = -110
	right.offset_right = -16
	right.offset_top = -150
	right.offset_bottom = 150
	right.add_theme_constant_override("separation", 8)
	add_child(right)

	_add_hold(right, "AIM", "raise_camera")
	_add_hold(right, "SHOOT", "capture")
	_add_tap(right, "SWAP", func() -> void: player.toggle_tool())

	var left := VBoxContainer.new()
	left.set_anchors_preset(Control.PRESET_TOP_LEFT)
	left.offset_left = 16
	left.offset_top = 96
	left.add_theme_constant_override("separation", 8)
	add_child(left)
	_add_hold(left, "SCAN", "scan")
	_add_hold(left, "LISTEN", "listen")
	_add_hold(left, "CROUCH", "crouch")

	var top := HBoxContainer.new()
	top.set_anchors_preset(Control.PRESET_CENTER_TOP)
	top.offset_left = -160
	top.offset_right = 160
	top.offset_top = 74
	top.add_theme_constant_override("separation", 8)
	add_child(top)
	_add_tap(top, "VIEW", func() -> void: player.rig.toggle_view())
	_add_tap(top, "BOOK", func() -> void: _emit_action("book"))
	_add_tap(top, "MENU", func() -> void: _emit_action("pause"))

	var hint := UITheme.label("Drag the right half to look  ·  tap to shoot", 12,
		UITheme.INK_FAINT)
	hint.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	hint.offset_left = -330
	hint.offset_right = -18
	hint.offset_top = -30
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(hint)


func _make_button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(94, 52)
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 13)
	b.add_theme_color_override("font_color", UITheme.INK)
	b.add_theme_stylebox_override("normal", UITheme.panel_style(
		Color(0.06, 0.07, 0.08, 0.62), 26, Color(1, 1, 1, 0.18)))
	b.add_theme_stylebox_override("hover", UITheme.panel_style(
		Color(0.10, 0.11, 0.12, 0.72), 26, Color(1, 1, 1, 0.24)))
	b.add_theme_stylebox_override("pressed", UITheme.panel_style(
		Color(0.24, 0.19, 0.09, 0.85), 26, UITheme.ACCENT))
	return b


## Buttons that behave like a held key, so they work with the same actions the
## keyboard uses.
func _add_hold(parent: Control, text: String, action: String) -> void:
	var b := _make_button(text)
	b.button_down.connect(func() -> void: _press_action(action, true))
	b.button_up.connect(func() -> void: _press_action(action, false))
	parent.add_child(b)
	_buttons.append({"node": b, "action": action})


func _add_tap(parent: Control, text: String, on_press: Callable) -> void:
	var b := _make_button(text)
	b.custom_minimum_size = Vector2(94, 42)
	b.pressed.connect(func() -> void:
		AudioDirector.play("ui_click", -16.0)
		on_press.call())
	parent.add_child(b)


func _press_action(action: String, pressed: bool) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = pressed
	ev.strength = 1.0 if pressed else 0.0
	Input.parse_input_event(ev)


func _emit_action(action: String) -> void:
	_press_action(action, true)
	_press_action(action, false)


func _input(event: InputEvent) -> void:
	if player == null:
		return
	var half := size.x * 0.5

	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			if touch.position.x < half and _stick_touch == -1:
				_stick_touch = touch.index
				_stick_origin = touch.position
				_stick_pos = touch.position
			elif touch.position.x >= half and _look_touch == -1:
				_look_touch = touch.index
				_look_last = touch.position
				_look_start = touch.position
				_look_time = 0.0
		else:
			if touch.index == _stick_touch:
				_stick_touch = -1
				player.touch_move = Vector2.ZERO
			elif touch.index == _look_touch:
				# A quick tap that did not drag is a shutter press.
				if _look_time < TAP_TIME and \
						touch.position.distance_to(_look_start) < TAP_SLOP:
					_emit_action("capture")
				_look_touch = -1
		queue_redraw()

	elif event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		if drag.index == _stick_touch:
			_stick_pos = drag.position
			var offset := (_stick_pos - _stick_origin) / STICK_RADIUS
			player.touch_move = Vector2(offset.x, offset.y).limit_length(1.0)
			queue_redraw()
		elif drag.index == _look_touch:
			player.touch_look += drag.position - _look_last
			_look_last = drag.position


func _process(delta: float) -> void:
	if _look_touch != -1:
		_look_time += delta
	visible = Settings.touch_controls_enabled and not Game.is_paused


func _draw() -> void:
	if _stick_touch == -1:
		return
	draw_arc(_stick_origin, STICK_RADIUS, 0.0, TAU, 48, Color(1, 1, 1, 0.20), 2.0)
	var knob := _stick_origin + (_stick_pos - _stick_origin).limit_length(STICK_RADIUS)
	draw_circle(knob, 26.0, Color(0.93, 0.72, 0.32, 0.35))
	draw_arc(knob, 26.0, 0.0, TAU, 24, Color(1, 1, 1, 0.45), 2.0)
