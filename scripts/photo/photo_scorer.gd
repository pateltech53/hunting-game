class_name PhotoScorer
extends Node
## Looks at the frame the player just shot and judges it.
##
## Everything here is measured from the real scene at the moment of capture:
## where the subject actually landed in the frame, whether the lens was focused
## on it, whether the sun was on it or behind it, whether a branch was in the
## way. The genre is inferred from what is in shot, then scored against what
## that genre is supposed to care about.

signal scored(record: Dictionary)

const GENRES := {
	"wildlife": {"label": "Wildlife", "ideal_size": 0.30, "weights":
		{"composition": 0.16, "subject": 0.26, "focus": 0.20, "exposure": 0.12,
		"light": 0.14, "moment": 0.12}},
	"portrait": {"label": "Portrait", "ideal_size": 0.52, "weights":
		{"composition": 0.20, "subject": 0.20, "focus": 0.22, "exposure": 0.10,
		"light": 0.16, "moment": 0.12}},
	"group": {"label": "Group Photo", "ideal_size": 0.34, "weights":
		{"composition": 0.24, "subject": 0.24, "focus": 0.16, "exposure": 0.10,
		"light": 0.14, "moment": 0.12}},
	"landscape": {"label": "Landscape", "ideal_size": 0.0, "weights":
		{"composition": 0.30, "subject": 0.10, "focus": 0.10, "exposure": 0.14,
		"light": 0.30, "moment": 0.06}},
	"street": {"label": "Street", "ideal_size": 0.22, "weights":
		{"composition": 0.26, "subject": 0.18, "focus": 0.14, "exposure": 0.12,
		"light": 0.16, "moment": 0.14}},
	"interior": {"label": "Interior", "ideal_size": 0.0, "weights":
		{"composition": 0.28, "subject": 0.10, "focus": 0.14, "exposure": 0.20,
		"light": 0.22, "moment": 0.06}},
	"wedding": {"label": "Wedding", "ideal_size": 0.40, "weights":
		{"composition": 0.24, "subject": 0.22, "focus": 0.18, "exposure": 0.10,
		"light": 0.14, "moment": 0.12}},
	"detail": {"label": "Detail", "ideal_size": 0.45, "weights":
		{"composition": 0.20, "subject": 0.18, "focus": 0.28, "exposure": 0.12,
		"light": 0.16, "moment": 0.06}},
}

## Terrain and buildings hide a subject outright; foliage only veils it.
const HARD_OCCLUSION_MASK := 1
const SOFT_OCCLUSION_MASK := 1 << 3
const OCCLUSION_MASK := HARD_OCCLUSION_MASK | SOFT_OCCLUSION_MASK

## Behaviour states grouped by how much of a moment they make.
const ACTION_STATES := ["fleeing", "sprinting", "flying", "hunting", "pouncing",
	"clashing", "sparring", "bugling", "howling", "calling", "standing", "sliding",
	"fishing", "hopping", "scraping"]
const TENSE_STATES := ["alert", "freezing"]
const BUSY_STATES := ["grazing", "browsing", "feeding", "rooting", "dabbling",
	"foraging", "preening", "wading", "swimming", "prowling", "stalking", "climbing",
	"wallowing", "rubbing", "eating", "scavenging", "walking"]
const CALM_STATES := ["resting", "perching", "posing", "idle"]

var player: Player
var sky: SkySystem
var world: VoxelWorld
var weather: WeatherSystem
## Returns the array of things worth photographing near the player.
var subject_provider: Callable = Callable()
var contract_board: Node = null
## Set by WorldRoot. A frame shot during a rare event is worth more, which is
## the reason to abandon what you were doing and go and photograph it.
var events: Node = null


func setup(p: Player, sky_system: SkySystem, voxel_world: VoxelWorld,
		weather_system: WeatherSystem) -> void:
	player = p
	sky = sky_system
	world = voxel_world
	weather = weather_system


# ------------------------------------------------------------------- analysis

func analyse(camera: PhotoCamera) -> Dictionary:
	var cam := player.camera()
	var viewport_size := cam.get_viewport().get_visible_rect().size
	var eye := cam.global_position
	var subjects: Array = []

	var candidates: Array = []
	if subject_provider.is_valid():
		candidates = subject_provider.call()

	for node: Node3D in candidates:
		if not is_instance_valid(node) or not node.has_method("subject_info"):
			continue
		var info: Dictionary = node.subject_info()
		var pos: Vector3 = info["position"]
		var distance := eye.distance_to(pos)
		if distance > 420.0:
			continue
		if not cam.is_position_in_frustum(pos):
			continue
		var screen := cam.unproject_position(pos)
		var uv := Vector2(screen.x / maxf(viewport_size.x, 1.0),
			screen.y / maxf(viewport_size.y, 1.0))
		var radius: float = info.get("radius", 0.6)
		# Apparent height as a fraction of frame height.
		var apparent := _apparent_size(cam, radius, distance, viewport_size)
		var visibility := _visibility(eye, pos, radius, node)
		if visibility <= 0.05:
			continue
		var to_subject := (pos - eye).normalized()
		var facing: Vector3 = info.get("forward", Vector3.FORWARD)
		# 1 when the subject looks straight down the lens.
		var head_on := clampf(-facing.dot(to_subject), -1.0, 1.0)
		subjects.append({
			"node": node,
			"kind": info.get("kind", "animal"),
			"species": info.get("species", ""),
			"name": info.get("name", ""),
			"state": info.get("state", ""),
			"rarity": info.get("rarity", 0.2),
			"value": info.get("value", 30),
			"position": pos,
			"distance": distance,
			"uv": uv,
			"size": apparent,
			"visibility": visibility,
			"head_on": head_on,
			"alert": info.get("alert", false),
			"lit": _sun_on(pos),
			"backlit": _backlit(to_subject),
			"eyes_visible": head_on > 0.25 and apparent > 0.08,
		})

	subjects.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return _subject_weight(a) > _subject_weight(b))

	var interior := _is_interior(eye)
	return {
		"subjects": subjects,
		"interior": interior,
		"horizon_uv": _horizon_position(cam),
		"sky_fraction": _sky_fraction(cam),
		"water_in_frame": _water_in_frame(cam, eye),
		"landmark": _landmark_in_frame(cam, eye),
		"eye": eye,
		"viewport": viewport_size,
	}


func _subject_weight(s: Dictionary) -> float:
	# Big, sharp, central and rare all make something the "main" subject.
	var centrality := 1.0 - clampf((s["uv"] as Vector2).distance_to(Vector2(0.5, 0.5)), 0.0, 1.0)
	return float(s["size"]) * 2.0 + centrality * 0.6 + float(s["rarity"]) * 0.4


func _apparent_size(cam: Camera3D, radius: float, distance: float,
		viewport: Vector2) -> float:
	var fov_rad := deg_to_rad(cam.fov)
	var frame_height_at_distance := 2.0 * distance * tan(fov_rad * 0.5)
	return clampf((radius * 2.0) / maxf(frame_height_at_distance, 0.001), 0.0, 1.5)


## How much of the subject the camera can actually see.
##
## Ground and buildings are hard occluders - a deer behind a ridge is simply
## not in the photograph. Foliage is soft: shooting through a screen of leaves
## costs you, but it does not erase the subject the way a hillside does.
func _visibility(eye: Vector3, pos: Vector3, radius: float, node: Node3D) -> float:
	var space := player.get_world_3d().direct_space_state
	var offsets := [
		Vector3.ZERO,
		Vector3(radius * 0.6, 0.0, 0.0), Vector3(-radius * 0.6, 0.0, 0.0),
		Vector3(0.0, radius * 0.9, 0.0), Vector3(0.0, -radius * 0.35, 0.0),
	]
	var exclude: Array[RID] = [player.get_rid()]
	if node is CollisionObject3D:
		exclude.append((node as CollisionObject3D).get_rid())
	var hard_clear := 0
	var soft_clear := 0
	for offset: Vector3 in offsets:
		var target := pos + offset
		var hard := PhysicsRayQueryParameters3D.create(eye, target)
		hard.collision_mask = HARD_OCCLUSION_MASK
		hard.exclude = exclude
		if space.intersect_ray(hard).is_empty():
			hard_clear += 1
		var soft := PhysicsRayQueryParameters3D.create(eye, target)
		soft.collision_mask = SOFT_OCCLUSION_MASK
		soft.exclude = exclude
		if space.intersect_ray(soft).is_empty():
			soft_clear += 1
	var n := float(offsets.size())
	var hard_fraction := float(hard_clear) / n
	var soft_fraction := float(soft_clear) / n
	return hard_fraction * (0.45 + 0.55 * soft_fraction)


## Is the sun actually falling on this point, or is it in shade?
func _sun_on(pos: Vector3) -> float:
	if sky == null or sky.is_night():
		return 0.0
	var space := player.get_world_3d().direct_space_state
	var towards_sun := -sky.sun_direction()
	var params := PhysicsRayQueryParameters3D.create(pos + Vector3.UP * 0.2,
		pos + towards_sun * 70.0)
	params.collision_mask = OCCLUSION_MASK
	return 0.0 if not space.intersect_ray(params).is_empty() else 1.0


## 1 when you are shooting into the light and the subject gets a rim.
func _backlit(to_subject: Vector3) -> float:
	if sky == null:
		return 0.0
	var sun_travel := sky.sun_direction()
	return clampf(to_subject.dot(sun_travel.normalized()) * -1.0, 0.0, 1.0)


func _is_interior(eye: Vector3) -> bool:
	var space := player.get_world_3d().direct_space_state
	var params := PhysicsRayQueryParameters3D.create(eye, eye + Vector3.UP * 6.0)
	params.collision_mask = 1
	params.exclude = [player.get_rid()]
	if space.intersect_ray(params).is_empty():
		return false
	# A roof overhead is only an interior if there are walls too.
	var walls := 0
	for dir: Vector3 in [Vector3.RIGHT, Vector3.LEFT, Vector3.FORWARD, Vector3.BACK]:
		var p := PhysicsRayQueryParameters3D.create(eye, eye + dir * 7.0)
		p.collision_mask = 1
		p.exclude = [player.get_rid()]
		if not space.intersect_ray(p).is_empty():
			walls += 1
	return walls >= 3


## Where the horizon falls in the frame, 0 top .. 1 bottom.
func _horizon_position(cam: Camera3D) -> float:
	var pitch := cam.global_rotation.x
	var half_fov := deg_to_rad(cam.fov) * 0.5
	return clampf(0.5 + (tan(pitch) / maxf(tan(half_fov), 0.001)) * 0.5, -1.0, 2.0)


func _sky_fraction(cam: Camera3D) -> float:
	return clampf(_horizon_position(cam), 0.0, 1.0)


func _water_in_frame(cam: Camera3D, eye: Vector3) -> bool:
	if world == null:
		return false
	var forward := -cam.global_transform.basis.z
	for d: float in [12.0, 28.0, 55.0, 90.0]:
		var p := eye + forward * d
		if world.is_water_at(p.x, p.z):
			return true
	return false


func _landmark_in_frame(cam: Camera3D, eye: Vector3) -> Dictionary:
	if world == null:
		return {}
	for m: Dictionary in world.markers:
		var pos: Vector3 = m["position"]
		if eye.distance_to(pos) > 90.0:
			continue
		if cam.is_position_in_frustum(pos):
			return m
	return {}


# -------------------------------------------------------------------- scoring

func score(camera: PhotoCamera, analysis: Dictionary) -> Dictionary:
	var subjects: Array = analysis.get("subjects", [])
	var genre := _detect_genre(camera, analysis)
	var spec: Dictionary = GENRES[genre]
	var main: Dictionary = subjects[0] if not subjects.is_empty() else {}
	var notes: Array = []

	var composition := _score_composition(genre, analysis, main, notes)
	var subject := _score_subject(genre, spec, subjects, main, notes)
	var focus := _score_focus(camera, main, analysis, notes)
	var exposure := _score_exposure(camera, notes)
	var light := _score_light(main, notes)
	var moment := _score_moment(genre, subjects, main, notes)

	var weights: Dictionary = spec["weights"]
	var total := 0.0
	total += composition * float(weights["composition"])
	total += subject * float(weights["subject"])
	total += focus * float(weights["focus"])
	total += exposure * float(weights["exposure"])
	total += light * float(weights["light"])
	total += moment * float(weights["moment"])

	# Rarity is a bonus on top rather than part of the craft score.
	var rarity_bonus := 0.0
	if not main.is_empty():
		rarity_bonus = float(main.get("rarity", 0.0)) * 8.0

	# So is a rare event. Being in the right place while the aurora is out is
	# not craft, but it is worth photographing, and this is what says so.
	var event_bonus := 0.0
	var event_name := ""
	if events != null and events.active != "":
		event_bonus = float(events.photo_bonus())
		event_name = String(events.display_name())
		notes.append("Shot during the %s." % event_name.to_lower())

	var final := clampf(total * 100.0 + rarity_bonus + event_bonus, 0.0, 100.0)

	var record := {
		"genre": genre,
		"genre_label": spec["label"],
		"score": snappedf(final, 0.1),
		"grade": grade_for(final),
		"event": event_name,
		"species": main.get("species", ""),
		"subject_name": main.get("name", ""),
		"subject_state": main.get("state", ""),
		"subject_count": subjects.size(),
		"subject_distance": snappedf(float(main.get("distance", 0.0)), 0.1),
		"breakdown": {
			"composition": snappedf(composition * 100.0, 0.1),
			"subject": snappedf(subject * 100.0, 0.1),
			"focus": snappedf(focus * 100.0, 0.1),
			"exposure": snappedf(exposure * 100.0, 0.1),
			"light": snappedf(light * 100.0, 0.1),
			"moment": snappedf(moment * 100.0, 0.1),
		},
		"notes": notes,
		"lens": camera.lens.id,
		"lens_name": camera.lens.name,
		"settings": camera.settings_summary(),
		"focal": camera.focal_length,
		"aperture": camera.aperture,
		"shutter": camera.shutter_denominator(),
		"iso": camera.iso(),
		"hour": sky.time_of_day if sky != null else 12.0,
		"clock": sky.clock_string() if sky != null else "12:00",
		"light_phase": sky.light_phase() if sky != null else "",
		"weather": weather.current if weather != null else "fair",
		"biome": player.current_biome() if player != null else "",
		"position": [player.global_position.x, player.global_position.y,
			player.global_position.z],
	}
	scored.emit(record)
	return record


func _detect_genre(camera: PhotoCamera, analysis: Dictionary) -> String:
	var subjects: Array = analysis.get("subjects", [])
	var people: Array = []
	var animals: Array = []
	for s: Dictionary in subjects:
		if s["kind"] == "person":
			people.append(s)
		else:
			animals.append(s)

	var landmark: Dictionary = analysis.get("landmark", {})
	if landmark.get("kind", "") == "wedding" and people.size() >= 1:
		return "wedding"
	if analysis.get("interior", false):
		return "interior"
	if people.size() >= 3:
		return "group"
	if people.size() >= 1:
		var biggest := 0.0
		for p: Dictionary in people:
			biggest = maxf(biggest, float(p["size"]))
		if biggest > 0.34:
			return "portrait"
		if landmark.get("kind", "") in ["street", "landmark"]:
			return "street"
		return "street"
	if animals.size() >= 3:
		return "group"
	if animals.size() >= 1:
		var main: Dictionary = animals[0]
		if camera.lens.macro and float(main["distance"]) < 3.0:
			return "detail"
		if float(main["size"]) > 0.42:
			return "portrait"
		return "wildlife"
	if camera.lens.macro:
		return "detail"
	return "landscape"


func _score_composition(genre: String, analysis: Dictionary, main: Dictionary,
		notes: Array) -> float:
	var score := 0.5
	if genre == "landscape" or genre == "interior":
		var horizon: float = analysis.get("horizon_uv", 0.5)
		# Reward a horizon near a third, punish one straight through the middle.
		var best := minf(absf(horizon - 0.333), absf(horizon - 0.667))
		score = clampf(1.0 - best * 3.4, 0.0, 1.0)
		if absf(horizon - 0.5) < 0.045:
			notes.append("Horizon cuts the frame in half.")
		elif best < 0.06:
			notes.append("Horizon sits on a third - clean.")
		if genre == "landscape":
			if analysis.get("water_in_frame", false):
				score = minf(1.0, score + 0.12)
				notes.append("Water gives the frame a resting point.")
			if not analysis.get("landmark", {}).is_empty():
				score = minf(1.0, score + 0.08)
		if horizon <= 0.02 or horizon >= 0.98:
			score *= 0.55
			notes.append("No horizon in frame at all.")
	else:
		if main.is_empty():
			return 0.35
		var uv: Vector2 = main["uv"]
		# Distance to the nearest rule-of-thirds intersection.
		var best := INF
		for tx: float in [0.333, 0.667]:
			for ty: float in [0.333, 0.667]:
				best = minf(best, uv.distance_to(Vector2(tx, ty)))
		var thirds := clampf(1.0 - best * 3.0, 0.0, 1.0)
		# Dead centre is not wrong, just less interesting.
		var centred := clampf(1.0 - uv.distance_to(Vector2(0.5, 0.5)) * 2.4, 0.0, 1.0) * 0.75
		score = maxf(thirds, centred)
		if best < 0.08:
			notes.append("Subject lands on a third.")
		# Clipping at the frame edge is the classic miss.
		var margin: float = float(main["size"]) * 0.5
		if uv.x - margin < 0.0 or uv.x + margin > 1.0 or uv.y - margin < 0.0 \
				or uv.y + margin > 1.0:
			score *= 0.6
			notes.append("Subject is clipped by the frame edge.")
		# Give a moving or looking subject room in front of it.
		if genre in ["portrait", "wildlife", "wedding"]:
			var head_on: float = main.get("head_on", 0.0)
			if head_on < 0.2 and uv.y < 0.25:
				score *= 0.9
				notes.append("Not much headroom.")
	return clampf(score, 0.0, 1.0)


func _score_subject(genre: String, spec: Dictionary, subjects: Array, main: Dictionary,
		notes: Array) -> float:
	if genre == "landscape" or genre == "interior":
		# Judged on depth and content rather than a single subject.
		var base := 0.62
		if not subjects.is_empty():
			base += 0.18
			notes.append("A living subject in the scene lifts it.")
		return clampf(base, 0.0, 1.0)
	if main.is_empty():
		notes.append("Nothing recognisable to photograph.")
		return 0.1

	var ideal: float = spec["ideal_size"]
	var size: float = main["size"]
	var fit: float = 1.0 - clampf(absf(size - ideal) / maxf(ideal, 0.05), 0.0, 1.0)
	fit = clampf(fit, 0.0, 1.0)
	if size < ideal * 0.35:
		notes.append("Subject is small in the frame - get closer or reach for longer glass.")
	elif size > ideal * 1.9:
		notes.append("Cropped in tight. Some breathing room would help.")

	var visibility: float = main["visibility"]
	if visibility < 0.7:
		notes.append("Something is in the way of the subject.")

	var count_bonus := 0.0
	if genre == "group" or genre == "wedding":
		var n := subjects.size()
		count_bonus = clampf(float(n - 2) / 5.0, 0.0, 1.0) * 0.35
		if n < 3:
			notes.append("A group photo wants at least three in frame.")
	return clampf(fit * 0.7 * visibility + count_bonus + 0.25 * visibility, 0.0, 1.0)


func _score_focus(camera: PhotoCamera, main: Dictionary, analysis: Dictionary,
		notes: Array) -> float:
	var quality := 1.0
	if main.is_empty():
		# Landscapes want depth of field that reaches the far ground.
		var dof := camera.depth_of_field_range()
		quality = clampf(dof.y / 120.0, 0.15, 1.0)
		if dof.y < 40.0:
			notes.append("Stopping down would have carried focus into the distance.")
	else:
		quality = camera.focus_quality(float(main["distance"]))
		if quality < 0.55:
			notes.append("Focus missed the subject.")
	var shake := camera.shake_risk()
	if shake > 0.35:
		quality *= clampf(1.0 - shake * 0.45, 0.15, 1.0)
		notes.append("Shutter was too slow to hold that lens steady.")
	var grain := camera.noise_level()
	if grain > 0.35:
		quality *= clampf(1.0 - (grain - 0.35) * 0.7, 0.4, 1.0)
		notes.append("Heavy grain from the ISO you pushed.")
	return clampf(quality, 0.0, 1.0)


func _score_exposure(camera: PhotoCamera, notes: Array) -> float:
	var error: float = camera.exposure_error()
	var magnitude := absf(error)
	var score := clampf(1.0 - pow(magnitude / 3.2, 1.5), 0.0, 1.0)
	if magnitude < 0.4:
		notes.append("Exposure is bang on.")
	elif error > 1.2:
		notes.append("Blown out by %.1f stops." % error)
	elif error < -1.2:
		notes.append("Under by %.1f stops." % absf(error))
	return score


func _score_light(main: Dictionary, notes: Array) -> float:
	if sky == null:
		return 0.6
	var quality := sky.light_quality()
	var phase := sky.light_phase()
	if phase == "golden hour":
		notes.append("Golden hour light - the best you will get.")
	elif phase == "blue hour":
		notes.append("Blue hour. Cold, quiet, and hard to expose.")
	elif phase == "hard light":
		notes.append("Overhead sun is flattening everything.")

	if not main.is_empty():
		var lit: float = main.get("lit", 0.0)
		var backlit: float = main.get("backlit", 0.0)
		if lit > 0.5:
			quality = minf(1.0, quality + 0.10)
		else:
			quality *= 0.82
			notes.append("Subject is sitting in shade.")
		if backlit > 0.6 and lit > 0.5:
			quality = minf(1.0, quality + 0.12)
			notes.append("Rim light around the subject.")
	if weather != null and weather.current == "mist":
		quality = minf(1.0, quality + 0.10)
		notes.append("Mist is separating the layers nicely.")
	return clampf(quality, 0.0, 1.0)


func _score_moment(genre: String, subjects: Array, main: Dictionary, notes: Array) -> float:
	if main.is_empty():
		return 0.55
	var score := 0.45
	var state: String = main.get("state", "")
	if state in ACTION_STATES:
		score = 0.95
		notes.append("Caught it mid-action.")
	elif state in TENSE_STATES:
		score = 0.78
		notes.append("It had you. That tension reads.")
	elif state in BUSY_STATES:
		score = 0.68
	elif state in CALM_STATES:
		score = 0.55
	else:
		score = 0.5
	if main.get("eyes_visible", false):
		score = minf(1.0, score + 0.18)
		if genre in ["portrait", "wedding", "wildlife"]:
			notes.append("Eye contact down the lens.")
	elif genre == "portrait":
		score *= 0.8
		notes.append("Turned away - a portrait wants the eyes.")
	if subjects.size() > 1 and genre in ["group", "wedding"]:
		var looking := 0
		for s: Dictionary in subjects:
			if s.get("eyes_visible", false):
				looking += 1
		score = minf(1.0, score + float(looking) / float(subjects.size()) * 0.15)
	return clampf(score, 0.0, 1.0)


static func grade_for(score: float) -> String:
	if score >= 92.0:
		return "S"
	if score >= 84.0:
		return "A"
	if score >= 72.0:
		return "B"
	if score >= 58.0:
		return "C"
	if score >= 42.0:
		return "D"
	return "E"


static func grade_color(grade: String) -> Color:
	match grade:
		"S":
			return Color(1.0, 0.82, 0.35)
		"A":
			return Color(0.62, 0.88, 0.52)
		"B":
			return Color(0.55, 0.78, 0.90)
		"C":
			return Color(0.86, 0.86, 0.86)
		"D":
			return Color(0.90, 0.68, 0.45)
		_:
			return Color(0.85, 0.48, 0.45)


# ------------------------------------------------------------------- committing

## Applies the consequences of a photograph: the Discovery Book, reputation,
## and any contract it satisfies.
func commit(record: Dictionary) -> void:
	var species: String = record.get("species", "")
	var newly_discovered := false
	if species != "":
		newly_discovered = Codex.record_photo(species, record)

	var value := int(round(float(record.get("score", 0.0)) * 0.4))
	if newly_discovered:
		value += 60
		AudioDirector.play("discovery", -4.0)
		Game.notify("New species recorded: %s" % record.get("subject_name", species),
			"discovery")
		AudioDirector.set_mood(AudioDirector.Mood.WONDER)
	elif float(record.get("score", 0.0)) >= 92.0:
		# A frame this good gets the orchestra, not just a chime.
		AudioDirector.play("flourish", -7.0)
	elif float(record.get("score", 0.0)) >= 84.0:
		AudioDirector.play("score_great", -8.0)
	elif float(record.get("score", 0.0)) >= 68.0:
		AudioDirector.play("score_good", -10.0)

	var progress: Dictionary = SaveSystem.profile.get("progress", {})
	progress["reputation"] = int(progress.get("reputation", 0)) + value
	SaveSystem.profile["progress"] = progress

	# What the frame is worth. Held rather than paid out here: you carry the
	# picture to the wildlife centre and sell it there.
	var subject_species := SpeciesLibrary.get_species(species)
	var price := Economy.photo_price(record, subject_species, newly_discovered)
	record["stars"] = Economy.stars(float(record.get("score", 0.0)))
	record["price"] = price
	if price > 0:
		SaveSystem.register_unsold(String(record.get("id", "")), price)

	# Flags for the achievements that ask about circumstance rather than totals.
	if sky != null and sky.time_of_day < 6.0 and not String(species).is_empty():
		Achievements.set_flag("sunrise_photo")
	if String(record.get("event", "")) != "":
		Achievements.set_flag("event_photo")
	Achievements.check_all()
	var newly_unlocked := LensLibrary.refresh_unlocks(int(progress["reputation"]))
	for l: Lens in newly_unlocked:
		Game.notify("New lens unlocked: %s" % l.name, "unlock")

	if contract_board != null and contract_board.has_method("on_photo"):
		contract_board.on_photo(record)
	SaveSystem.save_profile()
