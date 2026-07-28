extends Node
## Global settings + the runtime input map.
##
## Input actions are registered in code rather than in project.godot so that
## rebinding, gamepad support and the touch fallback all live in one place.

signal settings_changed
signal input_scheme_changed(scheme: int)

const CONFIG_PATH := "user://wildlight_settings.cfg"

enum Scheme { KEYBOARD, GAMEPAD, TOUCH }

## Quality tiers scale view distance, shadows and volumetrics.
enum Quality { POTATO, LOW, MEDIUM, HIGH, ULTRA }

var quality: Quality = Quality.HIGH
var view_distance_chunks: int = 6
var mouse_sensitivity: float = 0.0022
var touch_look_sensitivity: float = 0.0042
var gamepad_sensitivity: float = 2.6
var invert_y: bool = false
var fov: float = 74.0
var master_volume: float = 0.9
var music_volume: float = 0.55
var sfx_volume: float = 0.9
var ambience_volume: float = 0.8
var show_viewfinder_grid: bool = true
var show_histogram: bool = true
var motion_blur_hint: bool = true
var volumetric_fog: bool = true
var photo_resolution: int = 1600
var touch_controls_enabled: bool = false
var scheme: Scheme = Scheme.KEYBOARD

## action -> [physical keycodes]
const KEY_BINDINGS := {
	"move_forward": [KEY_W, KEY_UP],
	"move_back": [KEY_S, KEY_DOWN],
	"move_left": [KEY_A, KEY_LEFT],
	"move_right": [KEY_D, KEY_RIGHT],
	"jump": [KEY_SPACE],
	"sprint": [KEY_SHIFT],
	"crouch": [KEY_CTRL, KEY_C],
	"toggle_view": [KEY_V],
	"raise_camera": [],           # mouse right, added below
	"capture": [],                # mouse left, added below
	"swap_tool": [KEY_X],
	"scan": [KEY_Q],
	"listen": [KEY_E],
	"book": [KEY_TAB],
	"map": [KEY_M],
	"journal_contracts": [KEY_J],
	"pause": [KEY_ESCAPE],
	"interact": [KEY_F],
	"sandbox_panel": [KEY_G],
	"lens_next": [KEY_BRACKETRIGHT],
	"lens_prev": [KEY_BRACKETLEFT],
	"focus_near": [KEY_COMMA],
	"focus_far": [KEY_PERIOD],
	"aperture_open": [KEY_1],
	"aperture_close": [KEY_2],
	"shutter_slower": [KEY_3],
	"shutter_faster": [KEY_4],
	"iso_down": [KEY_5],
	"iso_up": [KEY_6],
	"autofocus": [KEY_R],
	"time_forward": [KEY_PAGEUP],
	"time_back": [KEY_PAGEDOWN],
	"reload": [KEY_T],
}

const MOUSE_BINDINGS := {
	"capture": MOUSE_BUTTON_LEFT,
	"raise_camera": MOUSE_BUTTON_RIGHT,
}

const PAD_BINDINGS := {
	"jump": JOY_BUTTON_A,
	"sprint": JOY_BUTTON_LEFT_STICK,
	"crouch": JOY_BUTTON_B,
	"toggle_view": JOY_BUTTON_RIGHT_STICK,
	"swap_tool": JOY_BUTTON_Y,
	"scan": JOY_BUTTON_LEFT_SHOULDER,
	"listen": JOY_BUTTON_RIGHT_SHOULDER,
	"book": JOY_BUTTON_BACK,
	"pause": JOY_BUTTON_START,
	"interact": JOY_BUTTON_X,
	"lens_next": JOY_BUTTON_DPAD_RIGHT,
	"lens_prev": JOY_BUTTON_DPAD_LEFT,
	"aperture_open": JOY_BUTTON_DPAD_UP,
	"aperture_close": JOY_BUTTON_DPAD_DOWN,
}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_register_actions()
	_apply_platform_defaults()
	load_settings()
	touch_controls_enabled = DisplayServer.is_touchscreen_available()
	if touch_controls_enabled:
		scheme = Scheme.TOUCH
	_apply_audio_buses()


## The web build runs on WebGL2 through WebAssembly, which is a good deal
## slower than a native Forward+ build, so it starts from a lighter preset.
## Anything the player later saves in Settings overrides this.
func _apply_platform_defaults() -> void:
	if not OS.has_feature("web"):
		return
	quality = Quality.LOW
	view_distance_chunks = 4
	volumetric_fog = false
	photo_resolution = 1280
	show_histogram = false


func is_web() -> bool:
	return OS.has_feature("web")


## Builds the whole InputMap from the tables above.
func _register_actions() -> void:
	var actions: Array = KEY_BINDINGS.keys()
	for action: String in actions:
		if not InputMap.has_action(action):
			InputMap.add_action(action, 0.2)
		InputMap.action_erase_events(action)
		for keycode: int in KEY_BINDINGS[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = keycode
			InputMap.action_add_event(action, ev)

	for action: String in MOUSE_BINDINGS:
		var mb := InputEventMouseButton.new()
		mb.button_index = MOUSE_BINDINGS[action]
		InputMap.action_add_event(action, mb)

	for action: String in PAD_BINDINGS:
		var jb := InputEventJoypadButton.new()
		jb.button_index = PAD_BINDINGS[action]
		InputMap.action_add_event(action, jb)

	# Analogue triggers double as capture / aim on a gamepad.
	_add_axis("capture", JOY_AXIS_TRIGGER_RIGHT, 1.0)
	_add_axis("raise_camera", JOY_AXIS_TRIGGER_LEFT, 1.0)
	# Left stick movement.
	_add_axis("move_left", JOY_AXIS_LEFT_X, -1.0)
	_add_axis("move_right", JOY_AXIS_LEFT_X, 1.0)
	_add_axis("move_forward", JOY_AXIS_LEFT_Y, -1.0)
	_add_axis("move_back", JOY_AXIS_LEFT_Y, 1.0)


func _add_axis(action: String, axis: int, value: float) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action, 0.2)
	var ev := InputEventJoypadMotion.new()
	ev.axis = axis
	ev.axis_value = value
	InputMap.action_add_event(action, ev)


func _input(event: InputEvent) -> void:
	var new_scheme := scheme
	if event is InputEventScreenTouch or event is InputEventScreenDrag:
		new_scheme = Scheme.TOUCH
	elif event is InputEventJoypadButton or event is InputEventJoypadMotion:
		if event is InputEventJoypadMotion and absf(event.axis_value) < 0.4:
			return
		new_scheme = Scheme.GAMEPAD
	elif event is InputEventKey or event is InputEventMouseButton:
		new_scheme = Scheme.KEYBOARD
	if new_scheme != scheme:
		scheme = new_scheme
		input_scheme_changed.emit(scheme)


func look_sensitivity() -> float:
	return touch_look_sensitivity if scheme == Scheme.TOUCH else mouse_sensitivity


## How many chunks of terrain to keep resident, folded together with quality.
func effective_view_distance() -> int:
	match quality:
		Quality.POTATO:
			return mini(view_distance_chunks, 3)
		Quality.LOW:
			return mini(view_distance_chunks, 4)
		Quality.MEDIUM:
			return mini(view_distance_chunks, 5)
		Quality.HIGH:
			return view_distance_chunks
		_:
			return view_distance_chunks + 2


func grass_density() -> float:
	match quality:
		Quality.POTATO:
			return 0.0
		Quality.LOW:
			return 0.25
		Quality.MEDIUM:
			return 0.55
		Quality.HIGH:
			return 1.0
		_:
			return 1.6


## True only on the Forward+ / Mobile renderers. The web build runs on
## Compatibility (WebGL2), which has no rendering device and therefore no
## depth of field, SSAO or volumetric fog.
func supports_advanced_rendering() -> bool:
	return RenderingServer.get_rendering_device() != null


func wants_volumetric_fog() -> bool:
	return volumetric_fog and quality >= Quality.MEDIUM and supports_advanced_rendering()


func shadow_distance() -> float:
	match quality:
		Quality.POTATO:
			return 45.0
		Quality.LOW:
			return 70.0
		Quality.MEDIUM:
			return 110.0
		Quality.HIGH:
			return 160.0
		_:
			return 220.0


func _apply_audio_buses() -> void:
	_ensure_bus("Music")
	_ensure_bus("SFX")
	_ensure_bus("Ambience")
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(master_volume, 0.0001)))
	_set_bus_volume("Music", music_volume)
	_set_bus_volume("SFX", sfx_volume)
	_set_bus_volume("Ambience", ambience_volume)


func _ensure_bus(bus_name: String) -> void:
	if AudioServer.get_bus_index(bus_name) != -1:
		return
	var idx := AudioServer.bus_count
	AudioServer.add_bus(idx)
	AudioServer.set_bus_name(idx, bus_name)
	AudioServer.set_bus_send(idx, "Master")


func _set_bus_volume(bus_name: String, linear: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx == -1:
		return
	AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(linear, 0.0001)))
	AudioServer.set_bus_mute(idx, linear <= 0.001)


func apply() -> void:
	_apply_audio_buses()
	settings_changed.emit()
	save_settings()


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("video", "quality", int(quality))
	cfg.set_value("video", "view_distance", view_distance_chunks)
	cfg.set_value("video", "fov", fov)
	cfg.set_value("video", "volumetric_fog", volumetric_fog)
	cfg.set_value("video", "photo_resolution", photo_resolution)
	cfg.set_value("audio", "master", master_volume)
	cfg.set_value("audio", "music", music_volume)
	cfg.set_value("audio", "sfx", sfx_volume)
	cfg.set_value("audio", "ambience", ambience_volume)
	cfg.set_value("input", "mouse_sensitivity", mouse_sensitivity)
	cfg.set_value("input", "touch_sensitivity", touch_look_sensitivity)
	cfg.set_value("input", "invert_y", invert_y)
	cfg.set_value("camera", "grid", show_viewfinder_grid)
	cfg.set_value("camera", "histogram", show_histogram)
	cfg.save(CONFIG_PATH)


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(CONFIG_PATH) != OK:
		return
	quality = cfg.get_value("video", "quality", int(quality)) as Quality
	view_distance_chunks = cfg.get_value("video", "view_distance", view_distance_chunks)
	fov = cfg.get_value("video", "fov", fov)
	volumetric_fog = cfg.get_value("video", "volumetric_fog", volumetric_fog)
	photo_resolution = cfg.get_value("video", "photo_resolution", photo_resolution)
	master_volume = cfg.get_value("audio", "master", master_volume)
	music_volume = cfg.get_value("audio", "music", music_volume)
	sfx_volume = cfg.get_value("audio", "sfx", sfx_volume)
	ambience_volume = cfg.get_value("audio", "ambience", ambience_volume)
	mouse_sensitivity = cfg.get_value("input", "mouse_sensitivity", mouse_sensitivity)
	touch_look_sensitivity = cfg.get_value("input", "touch_sensitivity", touch_look_sensitivity)
	invert_y = cfg.get_value("input", "invert_y", invert_y)
	show_viewfinder_grid = cfg.get_value("camera", "grid", show_viewfinder_grid)
	show_histogram = cfg.get_value("camera", "histogram", show_histogram)
