extends Node
## Global game context: which mode we are in, which world is loaded, and the
## routing between the menu and the field.

signal toast(text: String, kind: String)
signal game_started
signal game_ended
signal pause_toggled(paused: bool)
signal photo_captured(record: Dictionary)

enum Mode { EXPEDITION, SANDBOX, FREE_ROAM }

var mode: Mode = Mode.EXPEDITION
var world_seed: int = 0
var world_name: String = ""
var is_paused: bool = false
var in_game: bool = false

var world: Node3D = null
var player: Node3D = null

var _menu: Control = null
var _session_time := 0.0

const WORLD_SYLLABLES_A := ["Hol", "Bram", "Fen", "Ash", "Cair", "Dun", "Thorn", "Wester",
	"Gled", "Mar", "Ryn", "Cald", "Silv", "Oak", "Wynd", "Har"]
const WORLD_SYLLABLES_B := ["mere", "wood", "fell", "hollow", "reach", "moor", "vale",
	"crag", "burn", "shaw", "haven", "march", "combe", "stead"]


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _process(delta: float) -> void:
	if in_game and not is_paused:
		_session_time += delta
		SaveSystem.bump_stat("time_played", delta)


func boot() -> void:
	show_menu()


func show_menu() -> void:
	_teardown_world()
	if _menu != null and is_instance_valid(_menu):
		return
	var MenuScript := load("res://scripts/ui/main_menu.gd")
	var menu: Control = MenuScript.new()
	# Deferred: the tree root is still setting up children on the first frame.
	get_tree().root.add_child.call_deferred(menu)
	_menu = menu
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	AudioDirector.set_mood(AudioDirector.Mood.CALM)
	AudioDirector.stop_all_ambience()


func _teardown_world() -> void:
	if world != null and is_instance_valid(world):
		world.queue_free()
	world = null
	player = null
	in_game = false
	is_paused = false
	get_tree().paused = false


func random_world_name(seed_value: int) -> String:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var a: String = WORLD_SYLLABLES_A[rng.randi_range(0, WORLD_SYLLABLES_A.size() - 1)]
	var b: String = WORLD_SYLLABLES_B[rng.randi_range(0, WORLD_SYLLABLES_B.size() - 1)]
	return a + b


func start_game(new_mode: Mode, seed_value: int) -> void:
	mode = new_mode
	world_seed = seed_value if seed_value != 0 else int(Time.get_unix_time_from_system()) & 0x7FFFFFFF
	world_name = random_world_name(world_seed)

	if _menu != null and is_instance_valid(_menu):
		_menu.queue_free()
	_menu = null
	_teardown_world()

	var WorldScript := load("res://scripts/world/world_root.gd")
	var w: Node3D = WorldScript.new()
	w.name = "World"
	get_tree().root.add_child.call_deferred(w)
	world = w
	in_game = true
	_session_time = 0.0

	var state := SaveSystem.world_state(world_seed)
	state["visits"] = int(state.get("visits", 0)) + 1
	state["name"] = world_name
	SaveSystem.remember_world(world_seed, state)
	SaveSystem.save_profile()

	game_started.emit()
	notify("Welcome to %s" % world_name, "info")


func quit_to_menu() -> void:
	SaveSystem.save_profile()
	game_ended.emit()
	show_menu()


func set_paused(paused: bool) -> void:
	if is_paused == paused:
		return
	is_paused = paused
	get_tree().paused = paused
	pause_toggled.emit(paused)
	Settings.apply_mouse_mode()


func notify(text: String, kind: String = "info") -> void:
	toast.emit(text, kind)


func is_sandbox() -> bool:
	return mode == Mode.SANDBOX


func mode_label() -> String:
	match mode:
		Mode.SANDBOX:
			return "Sandbox"
		Mode.FREE_ROAM:
			return "Free Roam"
		_:
			return "Expedition"


func session_time() -> float:
	return _session_time


func quit_game() -> void:
	SaveSystem.save_profile()
	get_tree().quit()
