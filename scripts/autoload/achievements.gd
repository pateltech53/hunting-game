extends Node
## Things worth chasing once the game has stopped telling you what to do.
##
## Every entry is checked against the same save data the rest of the game
## already keeps, so nothing here needs its own bookkeeping - an achievement is
## a question asked of the profile, not a counter maintained alongside it.

signal unlocked(id: String, title: String)

## `check` is the name of a method on this node returning [have, need].
const LIST := [
	{"id": "first_photo", "icon": "📸", "title": "First Light",
		"blurb": "Take your first photograph.", "check": "_photos", "need": 1},
	{"id": "hundred_photos", "icon": "🎞", "title": "Working Photographer",
		"blurb": "Take a hundred photographs.", "check": "_photos", "need": 100},
	{"id": "five_star", "icon": "⭐", "title": "Perfect Frame",
		"blurb": "Score 92 or better on a single photograph.",
		"check": "_best_score", "need": 92},
	{"id": "ten_species", "icon": "🦌", "title": "Field Naturalist",
		"blurb": "Record ten species in the Discovery Book.",
		"check": "_species", "need": 10},
	{"id": "full_book", "icon": "🏆", "title": "Complete Journal",
		"blurb": "Record every species in the Discovery Book.",
		"check": "_species", "need": 18},
	{"id": "legendary", "icon": "👻", "title": "Ghost Story",
		"blurb": "Photograph one of the three legendary animals.",
		"check": "_legendaries", "need": 1},
	{"id": "all_legendary", "icon": "🌟", "title": "All Three",
		"blurb": "Photograph the White Doe, the Black Wolf and the golden eagle.",
		"check": "_legendaries", "need": 3},
	{"id": "sunrise", "icon": "🌅", "title": "Sunrise Hunter",
		"blurb": "Photograph an animal before six in the morning.",
		"check": "_flag_sunrise", "need": 1},
	{"id": "event_photo", "icon": "🌌", "title": "Right Place, Right Time",
		"blurb": "Photograph anything during a rare event.",
		"check": "_flag_event", "need": 1},
	{"id": "walker", "icon": "🥾", "title": "Long Walk",
		"blurb": "Cover fifty kilometres on foot.", "check": "_distance", "need": 50},
	{"id": "outfitted", "icon": "🎒", "title": "Properly Equipped",
		"blurb": "Own five pieces of gear.", "check": "_gear", "need": 5},
	{"id": "thousand", "icon": "💰", "title": "Turning Professional",
		"blurb": "Earn a thousand in total from photographs.",
		"check": "_earned", "need": 1000},
]


func _ready() -> void:
	_ensure_keys()


func _ensure_keys() -> void:
	var progress: Dictionary = SaveSystem.profile.get("progress", {})
	if not progress.has("achievements"):
		progress["achievements"] = []
	if not progress.has("flags"):
		progress["flags"] = {}
	if not progress.has("earned_total"):
		progress["earned_total"] = 0
	SaveSystem.profile["progress"] = progress


func is_unlocked(id: String) -> bool:
	return id in (SaveSystem.profile.get("progress", {}).get("achievements", []) as Array)


## Records a one-off thing that happened, for the achievements that ask about
## events rather than totals.
func set_flag(flag: String) -> void:
	var progress: Dictionary = SaveSystem.profile.get("progress", {})
	var flags: Dictionary = progress.get("flags", {})
	flags[flag] = true
	progress["flags"] = flags
	SaveSystem.profile["progress"] = progress
	check_all()


## Re-tests everything. Cheap enough to call whenever something happens.
func check_all() -> void:
	for entry: Dictionary in LIST:
		var id: String = entry["id"]
		if is_unlocked(id):
			continue
		var have: float = float(call(String(entry["check"])))
		if have < float(entry["need"]):
			continue
		_award(entry)


func _award(entry: Dictionary) -> void:
	var progress: Dictionary = SaveSystem.profile.get("progress", {})
	var list: Array = progress.get("achievements", [])
	list.append(String(entry["id"]))
	progress["achievements"] = list
	SaveSystem.profile["progress"] = progress
	AudioDirector.play("flourish", -9.0)
	Game.notify("%s  %s — %s" % [entry["icon"], entry["title"], entry["blurb"]],
		"discovery")
	unlocked.emit(String(entry["id"]), String(entry["title"]))
	SaveSystem.save_profile()


func progress_text(entry: Dictionary) -> String:
	var have: float = float(call(String(entry["check"])))
	var need: float = float(entry["need"])
	if need <= 1.0:
		return "done" if have >= need else "not yet"
	return "%d / %d" % [int(minf(have, need)), int(need)]


func unlocked_count() -> int:
	return (SaveSystem.profile.get("progress", {}).get("achievements", []) as Array).size()


# ------------------------------------------------------------------- queries

func _photos() -> float:
	return float(SaveSystem.profile.get("stats", {}).get("photos_taken", 0.0))


func _best_score() -> float:
	return float(SaveSystem.profile.get("stats", {}).get("best_photo_score", 0.0))


func _species() -> float:
	return float(Codex.discovered_count())


func _legendaries() -> float:
	var n := 0
	for id: String in ["albino_deer", "black_wolf", "golden_eagle"]:
		if Codex.is_discovered(id):
			n += 1
	return float(n)


func _distance() -> float:
	return float(SaveSystem.profile.get("stats", {}).get("distance_walked", 0.0)) * 0.001


func _gear() -> float:
	return float((SaveSystem.profile.get("progress", {}).get("gear", []) as Array).size())


func _earned() -> float:
	return float(SaveSystem.profile.get("progress", {}).get("earned_total", 0))


func _flag_sunrise() -> float:
	return 1.0 if _flag("sunrise_photo") else 0.0


func _flag_event() -> float:
	return 1.0 if _flag("event_photo") else 0.0


func _flag(name: String) -> bool:
	return bool((SaveSystem.profile.get("progress", {}).get("flags", {}) as Dictionary)
		.get(name, false))
