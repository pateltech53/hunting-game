class_name GameBootstrap
extends Node
## Entry point. Everything else is built at runtime.


## Seconds a `--smoke` run stays in the world before quitting. Override with
## `--smoke-seconds=N`; the drive system needs a couple of minutes before
## animals start acting on hunger and thirst, so short runs under-report it.
const SMOKE_SECONDS := 25.0

var _smoke_seconds := SMOKE_SECONDS

var _smoke := false
var _smoke_elapsed := 0.0
var _shots := false
var _shot_dir := "user://shots"
var _shot_queue: Array = []
var _shot_timer := 0.0


func _ready() -> void:
	get_window().title = "Wildlight"
	# Landscape is the only sensible orientation for a viewfinder.
	if DisplayServer.is_touchscreen_available():
		DisplayServer.screen_set_orientation(DisplayServer.SCREEN_LANDSCAPE)

	_smoke = OS.get_cmdline_user_args().has("--smoke")
	_shots = OS.get_cmdline_user_args().has("--shots")
	if _shots:
		_run_shot_test()
		return
	if _smoke:
		_run_smoke_test()
		return
	Game.boot()


# ------------------------------------------------------------------- shot mode

## Boots a world and writes PNGs of a scripted camera tour, so the look of the
## game can be checked without a person at the keyboard. Run it under a virtual
## display: `xvfb-run -a ./Godot... --path . --rendering-driver opengl3 -- --shots`
func _run_shot_test() -> void:
	var seed_value := 20240719
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--seed="):
			seed_value = int(arg.trim_prefix("--seed="))
		elif arg.begins_with("--out="):
			_shot_dir = arg.trim_prefix("--out=")
	DirAccess.make_dir_recursive_absolute(_shot_dir)
	if OS.get_cmdline_user_args().has("--menu"):
		Game.boot()
		_shot_queue = [{"t": 3.5, "name": "00_main_menu", "do": "none"}]
		return
	Game.start_game(Game.Mode.EXPEDITION, seed_value)
	_shot_queue = [
		{"t": 12.0, "name": "01_first_person", "do": "none"},
		{"t": 2.0, "name": "02_third_person", "do": "third"},
		{"t": 2.0, "name": "03_rifle_hip", "do": "rifle"},
		{"t": 2.0, "name": "04_rifle_aimed", "do": "rifle_aim"},
		{"t": 2.0, "name": "05_pause_menu", "do": "pause"},
	]


func _process_shots(delta: float) -> void:
	if _shot_queue.is_empty():
		return
	_shot_timer += delta
	var step: Dictionary = _shot_queue[0]
	if _shot_timer < float(step["t"]):
		return
	_shot_timer = 0.0
	_shot_queue.pop_front()
	_apply_shot_action(String(step["do"]))
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var path := "%s/%s.png" % [_shot_dir, step["name"]]
	image.save_png(path)
	print("[shots] wrote %s" % path)
	if _shot_queue.is_empty():
		print("[shots] done")
		get_tree().quit(0)


func _apply_shot_action(action: String) -> void:
	var world: Node = Game.world
	if world == null:
		return
	if action == "none":
		return
	var player: Player = world.get("player")
	var camera: PhotoCamera = world.get("photo_camera")
	match action:
		"third":
			player.rig.set_third_person(true)
		"third_aim":
			player.rig.set_third_person(true)
			camera.set_raised(true)
		"first_aim":
			player.rig.set_third_person(false)
			camera.set_raised(true)
		"rifle":
			player.rig.set_third_person(false)
			camera.set_raised(false)
			player.set_tool(Player.Tool.RIFLE)
		"rifle_aim":
			var r: Rifle = world.get("rifle")
			r.set_aimed(true)
		"pause":
			# The menu is built by world_root, not by Game.set_paused.
			world.call("_toggle_pause")
	print("[shots] action %s -> third_person=%s" % [action, player.rig.third_person])


## Boots straight into a world and reports on it, so a headless run exercises
## terrain generation, wildlife and the photo pipeline end to end.
func _run_smoke_test() -> void:
	var seed_value := 20240719
	var mode := Game.Mode.EXPEDITION
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--seed="):
			seed_value = int(arg.trim_prefix("--seed="))
		elif arg == "--sandbox":
			mode = Game.Mode.SANDBOX
		elif arg.begins_with("--smoke-seconds="):
			_smoke_seconds = float(arg.trim_prefix("--smoke-seconds="))
	print("[smoke] starting %s, seed %d" % ["sandbox" if mode == Game.Mode.SANDBOX
		else "expedition", seed_value])
	Game.start_game(mode, seed_value)


var _smoke_stage := 0


func _process(delta: float) -> void:
	if _shots:
		_process_shots(delta)
		return
	if not _smoke:
		return
	_smoke_elapsed += delta
	if _smoke_stage == 0 and _smoke_elapsed > _smoke_seconds * 0.55:
		_smoke_stage = 1
		_smoke_photo()
	elif _smoke_stage == 1 and _smoke_elapsed > _smoke_seconds * 0.80:
		_smoke_stage = 2
		_smoke_village()
	if _smoke_elapsed < _smoke_seconds:
		return
	set_process(false)
	_report_smoke()
	get_tree().quit(0)


## Stands the player in front of the nearest animal and raises the camera, so
## the next stage can score a real frame.
func _smoke_aim() -> Animal:
	var world: Node = Game.world
	if world == null:
		return null
	var wildlife: WildlifeDirector = world.get("wildlife")
	var player: Player = world.get("player")
	var camera: PhotoCamera = world.get("photo_camera")
	var voxel_world: VoxelWorld = world.get("voxel_world")

	# Look for somewhere with an actual clear sightline, the way a player
	# hunting for a shot would. How many tries this takes is itself a useful
	# reading on whether the forests are too thick to photograph through.
	var space := player.get_world_3d().direct_space_state
	var origin := player.global_position
	var stand := origin
	var spot := Vector3.ZERO
	var tries := 0
	for attempt in 220:
		tries += 1
		var ring := 6.0 + float(attempt % 5) * 7.0
		var a := TAU * float(attempt) * 0.61803399
		var candidate := origin + Vector3(cos(a), 0.0, sin(a)) * ring
		candidate.y = float(voxel_world.surface_height(candidate.x, candidate.z))
		if candidate.y <= float(TerrainGenerator.SEA_LEVEL):
			continue
		var dir := Vector3(cos(a + PI * 0.5), 0.0, sin(a + PI * 0.5))
		var subject := candidate + dir * 13.0
		subject.y = float(voxel_world.surface_height(subject.x, subject.z))
		if subject.y <= float(TerrainGenerator.SEA_LEVEL):
			continue
		var eye := candidate + Vector3.UP * (Player.STAND_HEIGHT - 0.18)
		var q := PhysicsRayQueryParameters3D.create(eye, subject + Vector3.UP * 0.79)
		q.collision_mask = PhotoScorer.OCCLUSION_MASK
		q.exclude = [player.get_rid()]
		if not space.intersect_ray(q).is_empty():
			continue
		stand = candidate
		spot = subject
		break
	if spot == Vector3.ZERO:
		print("[smoke] WARNING: no clear sightline found in %d tries" % tries)
		stand = origin
		stand.y = float(voxel_world.surface_height(stand.x, stand.z))
		spot = stand + Vector3(13.0, 0.0, 0.0)
		spot.y = float(voxel_world.surface_height(spot.x, spot.z))
	else:
		print("[smoke] clear sightline found after %d tries" % tries)
	player.teleport(stand)
	var spawned := wildlife.spawn_herd(SpeciesLibrary.get_species("whitetail_deer"), spot)
	var animal: Animal = spawned[0] if not spawned.is_empty() else \
		wildlife.nearest_animal(player.global_position)
	if animal == null:
		print("[smoke] no animal to photograph")
		return null
	var target := animal.global_position + Vector3.UP * animal.species.shoulder_height * 0.75
	var eye := stand + Vector3.UP * (Player.STAND_HEIGHT - 0.18)
	var to_target := target - eye
	player.rig.yaw = atan2(-to_target.x, -to_target.z)
	player.rig.pitch = asin(clampf(to_target.normalized().y, -1.0, 1.0))
	camera.select_lens("standard_50")
	camera.set_raised(true)
	return animal


## Runs analysis, scoring and the commit path without a real framebuffer.
func _smoke_photo() -> void:
	var world: Node = Game.world
	if world == null:
		return
	var camera: PhotoCamera = world.get("photo_camera")
	var scorer: PhotoScorer = world.get("scorer")
	var player: Player = world.get("player")
	# Re-aim, then let the rig and the camera transform settle before scoring.
	var animal := _smoke_aim()
	await get_tree().process_frame
	await get_tree().process_frame
	if animal != null and is_instance_valid(animal):
		var subject_pos := animal.global_position \
			+ Vector3.UP * animal.species.shoulder_height * 0.75
		camera.focus_distance = player.eye_position().distance_to(subject_pos)
		camera.autofocus = false
		print("[smoke] aiming at %s at %.1fm, in frustum: %s" % [
			animal.species.name,
			player.eye_position().distance_to(subject_pos),
			player.camera().is_position_in_frustum(subject_pos)])
		var voxel_world2: VoxelWorld = world.get("voxel_world")
		print("[smoke]   eye %s (ground %d), subject %s (ground %d)" % [
			player.eye_position().round(),
			voxel_world2.surface_height(player.global_position.x, player.global_position.z),
			subject_pos.round(),
			voxel_world2.surface_height(subject_pos.x, subject_pos.z)])
		var space := player.get_world_3d().direct_space_state
		for mask: int in [1, 1 << 3, PhotoScorer.OCCLUSION_MASK]:
			var q := PhysicsRayQueryParameters3D.create(player.eye_position(), subject_pos)
			q.collision_mask = mask
			q.exclude = [player.get_rid(), animal.get_rid()]
			var hit := space.intersect_ray(q)
			print("[smoke]   mask %d -> %s" % [mask,
				"clear" if hit.is_empty() else "%s at %s" % [hit["collider"],
					(hit["position"] as Vector3).snapped(Vector3(0.1, 0.1, 0.1))]])
	var analysis := scorer.analyse(camera)
	print("[smoke] subjects in frame: %d" % analysis["subjects"].size())
	var record := scorer.score(camera, analysis)
	print("[smoke] genre %s, grade %s, score %.1f, subject '%s'" % [
		record["genre"], record["grade"], record["score"], record["subject_name"]])
	print("[smoke] breakdown %s" % record["breakdown"])
	for note: String in record["notes"]:
		print("[smoke]   note: %s" % note)

	# Exercise the storage + codex + contract path with a stand-in image.
	var image := Image.create(320, 180, false, Image.FORMAT_RGB8)
	image.fill(Color(0.3, 0.4, 0.3))
	var paths := SaveSystem.store_photo_image(image, "smoke_test")
	record["path"] = paths.get("full", "")
	record["thumb"] = paths.get("thumb", "")
	record["id"] = "smoke_test"
	SaveSystem.register_photo(record)
	scorer.commit(record)


## Walks into the nearest settlement so the street / interior / wedding side of
## the game gets exercised too.
func _smoke_village() -> void:
	var world: Node = Game.world
	if world == null:
		return
	var voxel_world: VoxelWorld = world.get("voxel_world")
	var player: Player = world.get("player")
	if voxel_world.villages.is_empty():
		print("[smoke] no village registered near the player")
		return
	var best: Dictionary = {}
	var best_d := INF
	for key: String in voxel_world.villages:
		var site: Dictionary = voxel_world.villages[key]
		var d: float = player.global_position.distance_to(site["position"])
		if d < best_d:
			best_d = d
			best = site
	var pos: Vector3 = best["position"]
	player.teleport(Vector3(pos.x, pos.y + 1.5, pos.z))
	print("[smoke] walked into %s (%s) %dm away" % [best["name"], best["kind"], int(best_d)])


func _report_smoke() -> void:
	var world: Node = Game.world
	if world == null:
		print("[smoke] FAILED: no world")
		return
	var voxel_world: VoxelWorld = world.get("voxel_world")
	var wildlife: WildlifeDirector = world.get("wildlife")
	var sky: SkySystem = world.get("sky")
	var player: Player = world.get("player")
	print("[smoke] chunks loaded: %d" % voxel_world.loaded_chunk_count())
	print("[smoke] player at %s in %s" % [player.global_position.round(),
		player.current_biome()])
	print("[smoke] wildlife: %s" % wildlife.population_summary())
	# What the animals are actually doing, so "they just wander" is testable.
	var intents := {}
	var hunger := 0.0
	var thirst := 0.0
	var fatigue := 0.0
	var live := wildlife.active_animals()
	for a: Animal in live:
		intents[a.intent] = int(intents.get(a.intent, 0)) + 1
		hunger += a.hunger
		thirst += a.thirst
		fatigue += a.fatigue
	var n: float = maxf(float(live.size()), 1.0)
	print("[smoke] intents: %s" % intents)
	print("[smoke] mean needs: hunger %.2f, thirst %.2f, fatigue %.2f" % [
		hunger / n, thirst / n, fatigue / n])
	print("[smoke] clock %s, phase %s, EV %.1f, weather %s" % [sky.clock_string(),
		sky.light_phase(), sky.scene_ev(), world.get("weather").display_name()])
	print("[smoke] villages known: %d, markers: %d" % [voxel_world.villages.size(),
		voxel_world.markers.size()])
	var wide := Structures.village_sites_near(voxel_world.gen, 0.0, 0.0, 2000.0)
	var kinds := {}
	for site: Dictionary in wide:
		kinds[site["kind"]] = int(kinds.get(site["kind"], 0)) + 1
	print("[smoke] village sites within 2km: %d %s" % [wide.size(), kinds])
	print("[smoke] initial load took %.1fs for %d chunks" % [
		float(world.get("load_seconds")), voxel_world.loaded_chunk_count()])
	var tracks: TrackManager = world.get("track_manager")
	print("[smoke] tracks laid down: %d" % tracks.tracks_near(player.global_position,
		100000.0).size())
	print("[smoke] photos on disk: %d, codex entries: %d" % [
		SaveSystem.all_photos().size(), Codex.discovered_count()])
	var scorer: PhotoScorer = world.get("scorer")
	var near_people := 0
	for v: Villager in wildlife.villagers:
		if is_instance_valid(v) and v.global_position.distance_to(player.global_position) < 45.0:
			near_people += 1
	print("[smoke] villagers within 45m: %d, interiors mapped: %d" % [near_people,
		voxel_world.markers_of_kind("interior").size()])
	var board: ContractBoard = world.get("board")
	for c in board.active():
		print("[smoke] assignment: %s — %s [%s]" % [c.title, c.requirement_text(),
			c.progress_text()])
	print("[smoke] audio bank ready: sfx=%s music=%s" % [AudioDirector.ready_sfx,
		AudioDirector.ready_music])
	print("[smoke] funds $%d, unsold %d frames worth $%d, larder %.1f kg" % [
		Bank.funds(), SaveSystem.unsold_count(), SaveSystem.unsold_total(),
		float(SaveSystem.profile.get("progress", {}).get("larder", 0.0))])
	print("[smoke] done")
