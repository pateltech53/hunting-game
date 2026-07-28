extends Node
## Disk persistence: the profile (progression + codex), and the photo library.

signal profile_loaded
signal photo_saved(record: Dictionary)

const PROFILE_PATH := "user://profile.json"
const PHOTO_DIR := "user://photos"
const THUMB_DIR := "user://photos/thumbs"
const SAVE_VERSION := 1

var profile: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_dirs()
	load_profile()


func _ensure_dirs() -> void:
	DirAccess.make_dir_recursive_absolute(PHOTO_DIR)
	DirAccess.make_dir_recursive_absolute(THUMB_DIR)


func default_profile() -> Dictionary:
	return {
		"version": SAVE_VERSION,
		"created": Time.get_unix_time_from_system(),
		"codex": {},
		"photos": [],
		"worlds": {},
		"stats": {
			"photos_taken": 0,
			"shots_fired": 0,
			"harvests": 0,
			"distance_walked": 0.0,
			"time_played": 0.0,
			"best_photo_score": 0.0,
		},
		"progress": {
			"reputation": 0,
			"unlocked_lenses": ["standard_50"],
			"completed_contracts": [],
		},
		"last_seed": 0,
	}


func load_profile() -> void:
	if not FileAccess.file_exists(PROFILE_PATH):
		profile = default_profile()
		profile_loaded.emit()
		return
	var f := FileAccess.open(PROFILE_PATH, FileAccess.READ)
	if f == null:
		profile = default_profile()
		profile_loaded.emit()
		return
	var text := f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("Wildlight: profile.json unreadable, starting a fresh profile.")
		profile = default_profile()
	else:
		profile = _migrate(parsed)
	profile_loaded.emit()


func _migrate(data: Dictionary) -> Dictionary:
	var base := default_profile()
	for key: String in base:
		if not data.has(key):
			data[key] = base[key]
	# Fill in stat/progress keys added after the save was written.
	for group: String in ["stats", "progress"]:
		var defaults: Dictionary = base[group]
		var current: Dictionary = data.get(group, {})
		for key: String in defaults:
			if not current.has(key):
				current[key] = defaults[key]
		data[group] = current
	data["version"] = SAVE_VERSION
	return data


func save_profile() -> void:
	var f := FileAccess.open(PROFILE_PATH, FileAccess.WRITE)
	if f == null:
		push_warning("Wildlight: could not write profile.json")
		return
	f.store_string(JSON.stringify(profile, "\t"))
	f.close()


func bump_stat(key: String, amount: float) -> void:
	var stats: Dictionary = profile.get("stats", {})
	stats[key] = float(stats.get(key, 0.0)) + amount
	profile["stats"] = stats


func set_stat_max(key: String, value: float) -> void:
	var stats: Dictionary = profile.get("stats", {})
	stats[key] = maxf(float(stats.get(key, 0.0)), value)
	profile["stats"] = stats


## Writes the full-size photo plus a thumbnail and returns the filenames.
func store_photo_image(image: Image, id: String) -> Dictionary:
	_ensure_dirs()
	var full_path := "%s/%s.png" % [PHOTO_DIR, id]
	var thumb_path := "%s/%s.png" % [THUMB_DIR, id]
	var err := image.save_png(full_path)
	if err != OK:
		push_warning("Wildlight: failed to save photo (%d)" % err)
		return {}
	var thumb := image.duplicate() as Image
	var target_w := 384
	var target_h := int(round(float(target_w) * float(image.get_height()) / maxf(1.0, float(image.get_width()))))
	thumb.resize(target_w, maxi(target_h, 1), Image.INTERPOLATE_BILINEAR)
	thumb.save_png(thumb_path)
	return {"full": full_path, "thumb": thumb_path}


func register_photo(record: Dictionary) -> void:
	var photos: Array = profile.get("photos", [])
	photos.append(record)
	# Keep the library bounded so the profile file stays small.
	if photos.size() > 400:
		photos = photos.slice(photos.size() - 400)
	profile["photos"] = photos
	bump_stat("photos_taken", 1.0)
	set_stat_max("best_photo_score", float(record.get("score", 0.0)))
	photo_saved.emit(record)


func photos_for_species(species_id: String) -> Array:
	var out: Array = []
	for p: Dictionary in profile.get("photos", []):
		if p.get("species", "") == species_id:
			out.append(p)
	return out


func all_photos() -> Array:
	return profile.get("photos", [])


func delete_photo(record: Dictionary) -> void:
	var photos: Array = profile.get("photos", [])
	photos.erase(record)
	profile["photos"] = photos
	for key: String in ["path", "thumb"]:
		var p: String = record.get(key, "")
		if p != "" and FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)


## Remembers per-world state (spawn point, discovered village sites, time of day).
func world_state(seed_value: int) -> Dictionary:
	var worlds: Dictionary = profile.get("worlds", {})
	var key := str(seed_value)
	if not worlds.has(key):
		worlds[key] = {"seed": seed_value, "visits": 0, "hours": 0.0, "name": ""}
		profile["worlds"] = worlds
	return worlds[key]


func remember_world(seed_value: int, data: Dictionary) -> void:
	var worlds: Dictionary = profile.get("worlds", {})
	worlds[str(seed_value)] = data
	profile["worlds"] = worlds
	profile["last_seed"] = seed_value


func reset_profile() -> void:
	for p: Dictionary in profile.get("photos", []):
		for key: String in ["path", "thumb"]:
			var path: String = p.get(key, "")
			if path != "" and FileAccess.file_exists(path):
				DirAccess.remove_absolute(path)
	profile = default_profile()
	save_profile()
	profile_loaded.emit()


# ------------------------------------------------------------ unsold frames

## Photographs worth money that have not been taken to a buyer yet. Kept as a
## flat id -> price map so selling is a single lookup and the ledger survives
## a reload.
func register_unsold(photo_id: String, price: int) -> void:
	if photo_id == "" or price <= 0:
		return
	var progress: Dictionary = profile.get("progress", {})
	var pending: Dictionary = progress.get("unsold", {})
	pending[photo_id] = price
	progress["unsold"] = pending
	profile["progress"] = progress


func unsold_total() -> int:
	var pending: Dictionary = profile.get("progress", {}).get("unsold", {})
	var total := 0
	for key: String in pending:
		total += int(pending[key])
	return total


func unsold_count() -> int:
	return (profile.get("progress", {}).get("unsold", {}) as Dictionary).size()


## Clears the ledger and returns what it was worth.
func take_unsold() -> int:
	var total := unsold_total()
	var progress: Dictionary = profile.get("progress", {})
	progress["unsold"] = {}
	profile["progress"] = progress
	return total
