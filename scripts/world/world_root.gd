class_name WorldRoot
extends Node3D
## Assembles a session: terrain, sky, weather, the player and their tools, the
## wildlife, and the interface. Also owns the loading screen and the top-level
## key handling that opens the book, the map and the pause menu.

var voxel_world: VoxelWorld
var sky: SkySystem
var weather: WeatherSystem
var player: Player
var photo_camera: PhotoCamera
var rifle: Rifle
var scorer: PhotoScorer
var tracker: Tracker
var wildlife: WildlifeDirector
var track_manager: TrackManager
var trail_guide: TrailGuide
var board: ContractBoard
var hud: HUD
var touch: TouchControls

var _ui_layer: CanvasLayer
var _loading: Control
var _loading_bar: ProgressBar
var _loading_label: Label
var _book: DiscoveryBook
var _pause: PauseMenu
var _village_panel: VillagePanel
var _sandbox: SandboxPanel
var _map_overlay: Control
var _ready_to_play := false
var _harvest_target: Animal = null
var _music_timer := 0.0
var _load_started_ms := 0
var load_seconds := 0.0


func _ready() -> void:
	name = "World"
	_build_loading_screen()
	_build_world()
	_build_player()
	_build_systems()
	_build_ui()
	_load_started_ms = Time.get_ticks_msec()
	voxel_world.begin_initial_load(player.global_position)


# -------------------------------------------------------------------- setup

func _build_world() -> void:
	voxel_world = VoxelWorld.new()
	voxel_world.name = "VoxelWorld"
	add_child(voxel_world)
	voxel_world.setup(Game.world_seed)
	voxel_world.initial_load_progress.connect(_on_load_progress)
	voxel_world.initial_load_finished.connect(_on_load_finished)

	sky = SkySystem.new()
	sky.name = "Sky"
	add_child(sky)
	sky.day_length_minutes = 26.0
	sky.set_time(6.4)

	weather = WeatherSystem.new()
	weather.name = "Weather"
	add_child(weather)
	weather.setup(sky, Game.world_seed)


func _build_player() -> void:
	player = Player.new()
	player.name = "Player"
	add_child(player)
	var spawn := voxel_world.find_spawn()
	player.global_position = spawn
	player.attach_systems(voxel_world, sky, weather)
	player.input_enabled = false
	weather.follow_target = player
	Game.player = player


func _build_systems() -> void:
	track_manager = TrackManager.new()
	track_manager.name = "Tracks"
	add_child(track_manager)
	track_manager.setup(sky, voxel_world)

	scorer = PhotoScorer.new()
	scorer.name = "Scorer"
	add_child(scorer)

	photo_camera = PhotoCamera.new()
	photo_camera.name = "PhotoCamera"
	add_child(photo_camera)
	photo_camera.setup(player, sky, voxel_world, scorer)
	player.photo_camera = photo_camera

	wildlife = WildlifeDirector.new()
	wildlife.name = "Wildlife"
	add_child(wildlife)
	wildlife.setup(voxel_world, sky, weather, player, track_manager)

	rifle = Rifle.new()
	rifle.name = "Rifle"
	add_child(rifle)
	rifle.setup(player, voxel_world, wildlife)
	rifle.set_active(false)
	player.rifle = rifle

	scorer.setup(player, sky, voxel_world, weather)
	scorer.subject_provider = wildlife.subjects

	trail_guide = TrailGuide.new()
	trail_guide.name = "TrailGuide"
	add_child(trail_guide)
	trail_guide.setup(track_manager, voxel_world)

	tracker = Tracker.new()
	tracker.name = "Tracker"
	add_child(tracker)
	tracker.setup(player, track_manager, wildlife, sky)
	tracker.trail_guide = trail_guide

	board = ContractBoard.new()
	board.name = "Contracts"
	add_child(board)
	if Game.mode == Game.Mode.EXPEDITION:
		board.setup(voxel_world, sky)
	scorer.contract_board = board

	photo_camera.photo_taken.connect(_on_photo_taken)
	wildlife.animal_died.connect(_on_animal_died)


func _build_ui() -> void:
	hud = HUD.new()
	hud.name = "HUD"
	add_child(hud)
	hud.bind(player, sky, weather, photo_camera, rifle, tracker, board, wildlife,
		voxel_world)
	hud.visible = false

	_ui_layer = CanvasLayer.new()
	_ui_layer.name = "Overlays"
	_ui_layer.layer = 8
	add_child(_ui_layer)

	touch = TouchControls.new()
	touch.name = "Touch"
	touch.bind(player, photo_camera)
	touch.visible = Settings.touch_controls_enabled
	_ui_layer.add_child(touch)


func _build_loading_screen() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 20
	layer.name = "Loading"
	add_child(layer)

	_loading = Control.new()
	UITheme.full_screen(_loading)
	layer.add_child(_loading)

	var bg := ColorRect.new()
	bg.color = Color(0.035, 0.045, 0.052)
	UITheme.full_screen(bg)
	_loading.add_child(bg)

	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.offset_left = -300
	box.offset_right = 300
	box.offset_top = -70
	box.offset_bottom = 70
	box.add_theme_constant_override("separation", 10)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	_loading.add_child(box)

	box.add_child(UITheme.label("WILDLIGHT", 40, UITheme.ACCENT))
	_loading_label = UITheme.label("Growing the forest...", 15, UITheme.INK_DIM)
	box.add_child(_loading_label)
	_loading_bar = ProgressBar.new()
	_loading_bar.max_value = 1.0
	_loading_bar.value = 0.0
	_loading_bar.show_percentage = false
	_loading_bar.custom_minimum_size = Vector2(0, 6)
	box.add_child(_loading_bar)
	box.add_child(UITheme.label(
		"Photograph an animal to record it. The first photo becomes its page.",
		13, UITheme.INK_FAINT))


func _on_load_progress(done: int, total: int) -> void:
	_loading_bar.value = float(done) / maxf(float(total), 1.0)
	_loading_label.text = "Growing the forest...  %d / %d" % [done, total]


func _on_load_finished() -> void:
	if _ready_to_play:
		return
	_ready_to_play = true
	load_seconds = float(Time.get_ticks_msec() - _load_started_ms) * 0.001
	# Drop the player onto the ground the mesher actually built.
	var p := player.global_position
	player.global_position = Vector3(p.x, float(voxel_world.surface_height(p.x, p.z)) + 1.2,
		p.z)
	player.input_enabled = true
	player.refresh_biome()
	hud.visible = true
	_loading.queue_free()
	if Settings.scheme != Settings.Scheme.TOUCH:
		Settings.apply_mouse_mode()
	AudioDirector.set_mood(AudioDirector.Mood.CALM)
	Game.notify("%s. %s" % [Game.world_name,
		BiomeLibrary.get_biome(player.current_biome()).blurb], "info")


# ------------------------------------------------------------------ per frame

func _process(delta: float) -> void:
	if not _ready_to_play:
		return
	voxel_world.update_centre(player.global_position)
	AudioDirector.set_listener_position(player.eye_position())
	var biome := BiomeLibrary.get_biome(player.current_biome())
	sky.set_biome(biome)
	weather.set_biome(player.current_biome())
	voxel_world.set_night_lights(sky.is_night())
	_update_music(delta)
	_update_interaction()


## Music follows the situation: tense while something has you pinned, wondering
## just after a discovery, calm the rest of the time.
func _update_music(delta: float) -> void:
	_music_timer -= delta
	if _music_timer > 0.0:
		return
	_music_timer = 2.0
	var mood := AudioDirector.Mood.CALM
	for animal: Animal in wildlife.active_animals():
		if animal.is_dead:
			continue
		var d := animal.distance_to_player()
		if d < 45.0 and animal.state == Animal.State.ALERT:
			mood = AudioDirector.Mood.TENSION
			break
		if d < 30.0 and animal.species.size_class == "large":
			mood = AudioDirector.Mood.TENSION
			break
	AudioDirector.set_mood(mood)


func _update_interaction() -> void:
	_harvest_target = null
	var best := 4.5
	for animal: Animal in wildlife.active_animals():
		if not animal.is_dead:
			continue
		var d := animal.distance_to_player()
		if d < best:
			best = d
			_harvest_target = animal
	if _harvest_target != null:
		var name := _harvest_target.species.name
		if Codex.is_discovered(_harvest_target.species.id):
			hud.show_prompt("F  ·  record and harvest the %s" % name)
		else:
			hud.show_prompt("F  ·  harvest — but it has no page until you photograph one")
	else:
		hud.show_prompt("")


# --------------------------------------------------------------------- input

func _unhandled_input(event: InputEvent) -> void:
	if not _ready_to_play:
		return
	if event.is_action_pressed("pause"):
		_toggle_pause()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("book"):
		_open_book()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("map"):
		_toggle_map()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("toggle_view"):
		player.rig.toggle_view()
	elif event.is_action_pressed("swap_tool"):
		player.toggle_tool()
	elif event.is_action_pressed("interact"):
		_interact()
	elif event.is_action_pressed("sandbox_panel") and Game.is_sandbox():
		_toggle_sandbox()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("time_forward") and Game.is_sandbox():
		sky.advance_time(0.5)
	elif event.is_action_pressed("time_back") and Game.is_sandbox():
		sky.advance_time(-0.5)


func _interact() -> void:
	if _harvest_target == null:
		# Nothing to harvest: if you are standing in a settlement, this is the
		# door to its counters instead.
		_open_village_services()
		return
	var species := _harvest_target.species
	var data := _harvest_target.harvest()
	var bits: Array[String] = ["%.1f kg" % float(data.get("weight", 0.0))]
	if data.has("points"):
		bits.append("%d points" % int(data["points"]))
	# Meat goes into the pack, limited by what you can carry in one trip.
	var progress: Dictionary = SaveSystem.profile.get("progress", {})
	var capacity: float = 90.0 * Bank.effect("carry", 1.0)
	var carried := float(progress.get("larder", 0.0))
	var taken: float = minf(float(data.get("weight", 0.0)), maxf(0.0, capacity - carried))
	progress["larder"] = carried + taken
	SaveSystem.profile["progress"] = progress
	if taken < float(data.get("weight", 0.0)) - 0.05:
		Game.notify("Pack is full - %.1f kg left behind." % [
			float(data.get("weight", 0.0)) - taken], "warn")
	Game.notify("%s recorded: %s" % [species.name, ", ".join(bits)], "hunt")
	if not Codex.is_discovered(species.id):
		Game.notify("No page opened - the book only records a species from a photograph.",
			"warn")
	_harvest_target.queue_free()
	_harvest_target = null
	SaveSystem.save_profile()


## Opens the settlement counters when the player is inside one. Radius is
## generous: hunting for the exact doorway is not interesting.
func _open_village_services() -> void:
	if is_instance_valid(_village_panel):
		return
	var best := {}
	var best_d := 92.0
	for key: String in voxel_world.villages:
		var site: Dictionary = voxel_world.villages[key]
		var d: float = player.global_position.distance_to(site["position"])
		if d < best_d:
			best_d = d
			best = site
	if best.is_empty():
		return
	Game.set_paused(true)
	_village_panel = VillagePanel.new()
	_village_panel.setup(String(best.get("name", "the village")))
	add_child(_village_panel)
	_village_panel.closed.connect(func() -> void:
		Game.set_paused(false))


func _toggle_pause() -> void:
	if is_instance_valid(_pause):
		_pause.queue_free()
		Game.set_paused(false)
		return
	Game.set_paused(true)
	_pause = PauseMenu.new()
	_pause.resumed.connect(func() -> void: Game.set_paused(false))
	_pause.open_book_requested.connect(func() -> void:
		_pause.queue_free()
		_open_book())
	_pause.open_sandbox_requested.connect(func() -> void:
		_pause.queue_free()
		_toggle_sandbox())
	_ui_layer.add_child(_pause)


func _open_book() -> void:
	if is_instance_valid(_book):
		_book.queue_free()
		return
	Game.set_paused(true)
	_book = DiscoveryBook.new()
	_book.setup(voxel_world.gen)
	_book.closed.connect(func() -> void: Game.set_paused(false))
	_ui_layer.add_child(_book)


func _toggle_sandbox() -> void:
	if is_instance_valid(_sandbox):
		_sandbox.queue_free()
		Game.set_paused(false)
		return
	Game.set_paused(true)
	_sandbox = SandboxPanel.new()
	_sandbox.setup(sky, weather, wildlife, player, voxel_world)
	_sandbox.closed.connect(func() -> void: Game.set_paused(false))
	_ui_layer.add_child(_sandbox)


func _toggle_map() -> void:
	if is_instance_valid(_map_overlay):
		_map_overlay.queue_free()
		Game.set_paused(false)
		return
	Game.set_paused(true)
	_map_overlay = Control.new()
	UITheme.full_screen(_map_overlay)
	_map_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_map_overlay.add_child(UITheme.scrim(0.85))

	var panel := UITheme.panel(UITheme.PANEL_SOLID, 6)
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -330
	panel.offset_right = 330
	panel.offset_top = -370
	panel.offset_bottom = 370
	_map_overlay.add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)
	box.add_child(UITheme.heading(Game.world_name, 24))

	var map := MapView.new()
	map.setup(voxel_world.gen)
	map.custom_minimum_size = Vector2(600, 600)
	map.centre = Vector2(player.global_position.x, player.global_position.z)
	map.span = 1400.0
	map.player_position = map.centre
	map.player_yaw = player.rig.yaw
	for name_key: String in voxel_world.villages:
		var site: Dictionary = voxel_world.villages[name_key]
		var pos: Vector3 = site["position"]
		map.markers.append({"position": Vector2(pos.x, pos.z),
			"color": Color(0.95, 0.88, 0.70), "size": 5.0})
	box.add_child(map)
	map.refresh(true)

	box.add_child(UITheme.label(
		"%s  ·  %s  ·  %s  ·  %d, %d" % [
			BiomeLibrary.display_name(player.current_biome()), sky.clock_string(),
			weather.display_name(), int(player.global_position.x),
			int(player.global_position.z)], 13, UITheme.INK_DIM))
	var close := UITheme.button("Close  (M)")
	close.pressed.connect(_toggle_map)
	box.add_child(close)
	_ui_layer.add_child(_map_overlay)


# -------------------------------------------------------------------- events

func _on_photo_taken(record: Dictionary) -> void:
	var review := PhotoReview.new()
	review.setup(record, true)
	_ui_layer.add_child(review)


func _on_animal_died(animal: Animal) -> void:
	AudioDirector.set_mood(AudioDirector.Mood.CALM)


func _exit_tree() -> void:
	SaveSystem.save_profile()
	Game.player = null
