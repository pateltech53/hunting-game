class_name Tracker
extends Node
## The two field skills: scanning the ground for sign, and standing still to
## listen. Both are deliberately slow - they are the reason you stop moving.

signal scan_started
signal scan_report(lines: Array)
signal listening_changed(active: bool)
signal contacts_updated(contacts: Array)

const SCAN_RADIUS := 30.0
const SCAN_DURATION := 1.1
const SCAN_COOLDOWN := 2.4
const SCAN_REVEAL := 9.0
const LISTEN_RADIUS := 150.0

var player: Player
var track_manager: TrackManager
var wildlife: Node
var sky: SkySystem

var scanning := false
var listening := false
var scan_charge := 0.0
var cooldown := 0.0
var contacts: Array = []

var _listen_timer := 0.0
var _rng := RandomNumberGenerator.new()


func setup(p: Player, tracks: TrackManager, wildlife_director: Node,
		sky_system: SkySystem) -> void:
	player = p
	track_manager = tracks
	wildlife = wildlife_director
	sky = sky_system
	_rng.randomize()


func _process(delta: float) -> void:
	if player == null or Game.is_paused:
		return
	cooldown = maxf(0.0, cooldown - delta)
	_update_scan(delta)
	_update_listen(delta)


func _update_scan(delta: float) -> void:
	var held := Input.is_action_pressed("scan")
	if held and cooldown <= 0.0:
		if not scanning:
			scanning = true
			scan_charge = 0.0
			scan_started.emit()
		scan_charge += delta
		if scan_charge >= SCAN_DURATION:
			_do_scan()
			scanning = false
			cooldown = SCAN_COOLDOWN
	elif scanning:
		scanning = false
		scan_charge = 0.0


func _do_scan() -> void:
	AudioDirector.play("focus", -12.0, 0.7)
	var origin := player.global_position
	var lines: Array = []

	track_manager.highlight(SCAN_REVEAL)
	var found_tracks := track_manager.tracks_near(origin, SCAN_RADIUS)
	var by_species: Dictionary = {}
	for t: Dictionary in found_tracks:
		var id: String = t["species"]
		if not by_species.has(id) or track_manager.freshness(t) > track_manager.freshness(by_species[id]):
			by_species[id] = t

	for id: String in by_species:
		var track: Dictionary = by_species[id]
		var s := SpeciesLibrary.get_species(id)
		if s == null:
			continue
		Codex.record_track(id)
		var known := Codex.is_discovered(id)
		var label: String = s.name if known else "unfamiliar %s prints" % s.track_shape
		var bearing := _bearing_text(origin, track["position"])
		var heading := _heading_text(float(track["yaw"]))
		lines.append("%s - %s, %s, heading %s" % [
			label, track_manager.age_label(track), bearing, heading])

	for sign_entry: Dictionary in track_manager.sign_near(origin, SCAN_RADIUS):
		var s := SpeciesLibrary.get_species(sign_entry["species"])
		if s == null:
			continue
		if not sign_entry["found"]:
			sign_entry["found"] = true
			Codex.record_sign(s.id)
		var known := Codex.is_discovered(s.id)
		var who: String = s.name if known else "something"
		lines.append("%s left by %s, %s" % [
			_sign_label(sign_entry["kind"]), who, _bearing_text(origin, sign_entry["position"])])

	if lines.is_empty():
		lines.append("Nothing but leaf litter here.")
	scan_report.emit(lines)


func _sign_label(kind: String) -> String:
	match kind:
		"scat":
			return "Droppings"
		"rub":
			return "A rubbed sapling"
		"feather":
			return "A dropped feather"
		"bed":
			return "A flattened bed"
		_:
			return "Field sign"


func _bearing_text(from: Vector3, to: Vector3) -> String:
	var d := to - from
	var distance := Vector2(d.x, d.z).length()
	return "%s %dm away" % [_compass(atan2(d.x, -d.z)), int(round(distance))]


func _heading_text(yaw: float) -> String:
	return _compass(yaw + PI)


func _compass(angle: float) -> String:
	var deg := fposmod(rad_to_deg(angle), 360.0)
	var names := ["north", "north-east", "east", "south-east", "south", "south-west",
		"west", "north-west"]
	var idx := int(round(deg / 45.0)) % 8
	return names[idx]


# -------------------------------------------------------------------- listen

func _update_listen(delta: float) -> void:
	var held := Input.is_action_pressed("listen")
	if held != listening:
		listening = held
		listening_changed.emit(listening)
		if listening:
			AudioDirector.play("focus", -20.0, 0.5)
		else:
			contacts.clear()
			contacts_updated.emit(contacts)
	if not listening:
		return

	_listen_timer -= delta
	if _listen_timer > 0.0:
		return
	_listen_timer = 0.25
	contacts = _gather_contacts()
	contacts_updated.emit(contacts)

	# Listening carefully makes animals more likely to give themselves away.
	if _rng.randf() < 0.06 and not contacts.is_empty():
		var pick: Dictionary = contacts[_rng.randi_range(0, contacts.size() - 1)]
		if pick.has("node") and is_instance_valid(pick["node"]):
			var animal: Animal = pick["node"]
			AudioDirector.play_call(animal.species.id, animal.global_position, -4.0)
			Codex.record_call(animal.species.id)


func _gather_contacts() -> Array:
	var out: Array = []
	if wildlife == null or not wildlife.has_method("active_animals"):
		return out
	var origin := player.global_position
	for animal: Animal in wildlife.active_animals():
		if not is_instance_valid(animal) or animal.is_dead:
			continue
		var d := origin.distance_to(animal.global_position)
		if d > LISTEN_RADIUS:
			continue
		var delta_v := animal.global_position - origin
		# Louder if it is close, moving, or a big animal.
		var loudness := clampf(1.0 - d / LISTEN_RADIUS, 0.0, 1.0)
		loudness *= 0.5 + clampf(animal.velocity.length() * 0.1, 0.0, 0.5)
		loudness += 0.25 if animal.species.size_class == "large" else 0.0
		loudness = clampf(loudness, 0.0, 1.0)
		if loudness < 0.08:
			continue
		out.append({
			"node": animal,
			"species": animal.species.id,
			"known": Codex.is_discovered(animal.species.id),
			"name": animal.species.name,
			"bearing": atan2(delta_v.x, -delta_v.z),
			"distance": d,
			"band": _distance_band(d),
			"strength": loudness,
		})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["strength"]) > float(b["strength"]))
	return out.slice(0, 6)


func _distance_band(d: float) -> String:
	if d < 25.0:
		return "very close"
	if d < 60.0:
		return "close"
	if d < 110.0:
		return "some way off"
	return "distant"


func scan_progress() -> float:
	return clampf(scan_charge / SCAN_DURATION, 0.0, 1.0)
