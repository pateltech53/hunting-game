extends Node
## The Discovery Book's data model.
##
## Every species starts unknown. The first photograph you take of a species
## becomes the cover of its page; everything else on the page - the gallery,
## the range map, the tendencies - unlocks as you keep observing it.

signal species_discovered(species_id: String)
signal species_updated(species_id: String)
signal knowledge_gained(species_id: String, field: String)

## What a page can reveal, in the order it unlocks.
const FIELD_HABITAT := "habitat"
const FIELD_ACTIVITY := "activity"
const FIELD_DIET := "diet"
const FIELD_BEHAVIOUR := "behaviour"
const FIELD_FEATURES := "features"
const FIELD_TRACKS := "tracks"

var _entries: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	SaveSystem.profile_loaded.connect(_reload)
	_reload()


func _reload() -> void:
	_entries = SaveSystem.profile.get("codex", {})


func _flush() -> void:
	SaveSystem.profile["codex"] = _entries


func has_entry(species_id: String) -> bool:
	return _entries.has(species_id)


func is_discovered(species_id: String) -> bool:
	var e: Dictionary = _entries.get(species_id, {})
	return e.get("discovered", false)


func entry(species_id: String) -> Dictionary:
	if not _entries.has(species_id):
		_entries[species_id] = {
			"discovered": false,
			"cover_photo": "",
			"cover_thumb": "",
			"cover_score": 0.0,
			"first_seen_unix": 0,
			"first_seen_hour": -1.0,
			"first_seen_biome": "",
			"photo_count": 0,
			"best_score": 0.0,
			"best_photo": "",
			"sightings": [],
			"behaviours": {},
			"biomes": {},
			"hours": [],
			"harvested": 0,
			"measurements": {},
			"tracks_found": 0,
			"sign_found": 0,
			"calls_heard": 0,
			"revealed": [],
		}
		_flush()
	return _entries[species_id]


func discovered_ids() -> Array:
	var out: Array = []
	for id: String in _entries:
		if _entries[id].get("discovered", false):
			out.append(id)
	return out


func discovered_count() -> int:
	return discovered_ids().size()


## Called whenever the player has the animal on screen and close enough to
## resolve. Feeds the range map and the activity chart without granting the
## discovery itself - only a photograph does that.
func record_sighting(species_id: String, world_pos: Vector3, biome_id: String, hour: float) -> void:
	var e := entry(species_id)
	var sightings: Array = e["sightings"]
	# Cluster nearby sightings so the map does not fill up with dots.
	for s: Dictionary in sightings:
		var p := Vector3(s.get("x", 0.0), 0.0, s.get("z", 0.0))
		if p.distance_to(Vector3(world_pos.x, 0.0, world_pos.z)) < 40.0:
			s["count"] = int(s.get("count", 1)) + 1
			_note_hour(e, hour)
			_note_biome(e, biome_id)
			_flush()
			return
	sightings.append({
		"x": world_pos.x, "z": world_pos.z, "biome": biome_id,
		"hour": hour, "count": 1,
	})
	if sightings.size() > 120:
		sightings.remove_at(0)
	_note_hour(e, hour)
	_note_biome(e, biome_id)
	_evaluate_reveals(species_id, e)
	_flush()
	species_updated.emit(species_id)


func _note_hour(e: Dictionary, hour: float) -> void:
	var hours: Array = e["hours"]
	if hours.is_empty():
		hours.resize(24)
		hours.fill(0)
	var idx := clampi(int(floor(hour)) % 24, 0, 23)
	hours[idx] = int(hours[idx]) + 1
	e["hours"] = hours


func _note_biome(e: Dictionary, biome_id: String) -> void:
	if biome_id == "":
		return
	var biomes: Dictionary = e["biomes"]
	biomes[biome_id] = int(biomes.get(biome_id, 0)) + 1
	e["biomes"] = biomes


## The moment a species becomes "yours": the first photo is the cover.
func record_photo(species_id: String, record: Dictionary) -> bool:
	var e := entry(species_id)
	var newly_discovered: bool = not bool(e.get("discovered", false))
	if newly_discovered:
		e["discovered"] = true
		e["cover_photo"] = record.get("path", "")
		e["cover_thumb"] = record.get("thumb", "")
		e["cover_score"] = record.get("score", 0.0)
		e["first_seen_unix"] = int(Time.get_unix_time_from_system())
		e["first_seen_hour"] = record.get("hour", 12.0)
		e["first_seen_biome"] = record.get("biome", "")
	e["photo_count"] = int(e.get("photo_count", 0)) + 1
	var score := float(record.get("score", 0.0))
	if score > float(e.get("best_score", 0.0)):
		e["best_score"] = score
		e["best_photo"] = record.get("thumb", record.get("path", ""))
	_note_hour(e, float(record.get("hour", 12.0)))
	_note_biome(e, String(record.get("biome", "")))
	var behaviour := String(record.get("subject_state", ""))
	if behaviour != "":
		record_behaviour(species_id, behaviour)
	_evaluate_reveals(species_id, e)
	_flush()
	if newly_discovered:
		species_discovered.emit(species_id)
	species_updated.emit(species_id)
	return newly_discovered


## Replaces the cover with a different shot from the gallery.
func set_cover(species_id: String, record: Dictionary) -> void:
	var e := entry(species_id)
	e["cover_photo"] = record.get("path", "")
	e["cover_thumb"] = record.get("thumb", "")
	e["cover_score"] = record.get("score", 0.0)
	_flush()
	species_updated.emit(species_id)


func record_behaviour(species_id: String, behaviour: String) -> void:
	var e := entry(species_id)
	var b: Dictionary = e["behaviours"]
	b[behaviour] = int(b.get(behaviour, 0)) + 1
	e["behaviours"] = b
	_evaluate_reveals(species_id, e)
	_flush()


func record_track(species_id: String) -> void:
	var e := entry(species_id)
	e["tracks_found"] = int(e.get("tracks_found", 0)) + 1
	_evaluate_reveals(species_id, e)
	_flush()


func record_sign(species_id: String) -> void:
	var e := entry(species_id)
	e["sign_found"] = int(e.get("sign_found", 0)) + 1
	_evaluate_reveals(species_id, e)
	_flush()


func record_call(species_id: String) -> void:
	var e := entry(species_id)
	e["calls_heard"] = int(e.get("calls_heard", 0)) + 1
	_evaluate_reveals(species_id, e)
	_flush()


func record_harvest(species_id: String, measurements: Dictionary) -> void:
	var e := entry(species_id)
	e["harvested"] = int(e.get("harvested", 0)) + 1
	var m: Dictionary = e["measurements"]
	for key: String in measurements:
		m[key] = maxf(float(m.get(key, 0.0)), float(measurements[key]))
	e["measurements"] = m
	_reveal(species_id, e, FIELD_FEATURES)
	_flush()
	species_updated.emit(species_id)


func _evaluate_reveals(species_id: String, e: Dictionary) -> void:
	if int(e.get("sign_found", 0)) + int(e.get("tracks_found", 0)) >= 3:
		_reveal(species_id, e, FIELD_TRACKS)
	if e.get("sightings", []).size() >= 2 or int(e.get("photo_count", 0)) >= 1:
		_reveal(species_id, e, FIELD_HABITAT)
	if _distinct_hours(e) >= 3:
		_reveal(species_id, e, FIELD_ACTIVITY)
	if e.get("behaviours", {}).size() >= 2:
		_reveal(species_id, e, FIELD_DIET)
	if e.get("behaviours", {}).size() >= 4 or int(e.get("photo_count", 0)) >= 6:
		_reveal(species_id, e, FIELD_BEHAVIOUR)
	if int(e.get("photo_count", 0)) >= 3 or int(e.get("harvested", 0)) >= 1:
		_reveal(species_id, e, FIELD_FEATURES)


func _distinct_hours(e: Dictionary) -> int:
	var hours: Array = e.get("hours", [])
	var n := 0
	for v: int in hours:
		if v > 0:
			n += 1
	return n


func _reveal(species_id: String, e: Dictionary, field: String) -> void:
	var revealed: Array = e.get("revealed", [])
	if revealed.has(field):
		return
	revealed.append(field)
	e["revealed"] = revealed
	knowledge_gained.emit(species_id, field)


func is_revealed(species_id: String, field: String) -> bool:
	return entry(species_id).get("revealed", []).has(field)


## 0..1, how completely this page is filled in.
func completion(species_id: String) -> float:
	if not is_discovered(species_id):
		return 0.0
	var e := entry(species_id)
	var revealed: int = e.get("revealed", []).size()
	return clampf(float(revealed) / 6.0, 0.0, 1.0)


func most_common_biome(species_id: String) -> String:
	var biomes: Dictionary = entry(species_id).get("biomes", {})
	var best := ""
	var best_n := -1
	for id: String in biomes:
		if int(biomes[id]) > best_n:
			best_n = int(biomes[id])
			best = id
	return best


## Peak activity window, as a pair of hours, derived from observation only.
func peak_hours(species_id: String) -> Vector2i:
	var hours: Array = entry(species_id).get("hours", [])
	if hours.size() < 24:
		return Vector2i(-1, -1)
	var best_start := 0
	var best_sum := -1
	for start in 24:
		var s := 0
		for k in 4:
			s += int(hours[(start + k) % 24])
		if s > best_sum:
			best_sum = s
			best_start = start
	if best_sum <= 0:
		return Vector2i(-1, -1)
	return Vector2i(best_start, (best_start + 4) % 24)
