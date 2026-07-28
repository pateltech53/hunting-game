class_name LensLibrary
extends RefCounted
## The kit bag. Lenses beyond the standard 50 are earned with reputation, and
## unlocked immediately in sandbox.

const DATA := [
	{
		"id": "standard_50", "name": "Standard 50mm f/1.8", "short_name": "50mm",
		"focal_min": 50.0, "focal_max": 50.0, "aperture_min": 1.8, "aperture_max": 16.0,
		"min_focus": 0.45, "stability": 1.0, "unlock_reputation": 0,
		"blurb": "Sees roughly what you see. Hard to blame the lens with this one on.",
		"favours": ["street", "portrait", "documentary"],
	},
	{
		"id": "wide_24", "name": "Wide 24mm f/2.8", "short_name": "24mm",
		"focal_min": 24.0, "focal_max": 24.0, "aperture_min": 2.8, "aperture_max": 22.0,
		"min_focus": 0.25, "stability": 1.1, "unlock_reputation": 120,
		"blurb": "Takes in the whole clearing. Foreground becomes everything.",
		"favours": ["landscape", "interior", "street"],
	},
	{
		"id": "ultra_16", "name": "Ultrawide 16mm f/4", "short_name": "16mm",
		"focal_min": 16.0, "focal_max": 16.0, "aperture_min": 4.0, "aperture_max": 22.0,
		"min_focus": 0.20, "stability": 1.15, "unlock_reputation": 420,
		"blurb": "Fits a cabin's whole interior in one frame, and bends it a little.",
		"favours": ["interior", "landscape"],
	},
	{
		"id": "portrait_85", "name": "Portrait 85mm f/1.4", "short_name": "85mm",
		"focal_min": 85.0, "focal_max": 85.0, "aperture_min": 1.4, "aperture_max": 16.0,
		"min_focus": 0.85, "stability": 0.92, "unlock_reputation": 260,
		"blurb": "Flattering compression and a background that melts. Wide open it is unforgiving about focus.",
		"favours": ["portrait", "wedding", "group"],
	},
	{
		"id": "tele_200", "name": "Telephoto 70-200mm f/2.8", "short_name": "70-200",
		"focal_min": 70.0, "focal_max": 200.0, "aperture_min": 2.8, "aperture_max": 22.0,
		"min_focus": 1.2, "stability": 0.78, "unlock_reputation": 560,
		"blurb": "The working zoom. Reaches across a meadow without spooking anything.",
		"favours": ["wildlife", "portrait", "group", "wedding"],
	},
	{
		"id": "super_400", "name": "Super Telephoto 400mm f/5.6", "short_name": "400mm",
		"focal_min": 400.0, "focal_max": 400.0, "aperture_min": 5.6, "aperture_max": 32.0,
		"min_focus": 3.0, "stability": 0.52, "unlock_reputation": 900,
		"blurb": "Pulls a wolf off a distant ridge. Heavy, dim, and merciless if you rush the shot.",
		"favours": ["wildlife"],
	},
	{
		"id": "macro_100", "name": "Macro 100mm f/2.8", "short_name": "100mm macro",
		"focal_min": 100.0, "focal_max": 100.0, "aperture_min": 2.8, "aperture_max": 32.0,
		"min_focus": 0.12, "stability": 0.86, "macro": true, "unlock_reputation": 700,
		"blurb": "For tracks, feathers and frost. Depth of field measured in millimetres.",
		"favours": ["detail", "documentary"],
	},
]

const APERTURE_STOPS := [1.2, 1.4, 1.8, 2.0, 2.8, 4.0, 5.6, 8.0, 11.0, 16.0, 22.0, 32.0]
const SHUTTER_DENOMINATORS := [8000, 4000, 2000, 1000, 500, 250, 125, 60, 30, 15, 8, 4, 2, 1]
const ISO_STOPS := [50, 100, 200, 400, 800, 1600, 3200, 6400, 12800]

static var _cache: Dictionary = {}


static func _ensure() -> void:
	if not _cache.is_empty():
		return
	for d: Dictionary in DATA:
		var l := Lens.from_dict(d)
		_cache[l.id] = l


static func get_lens(id: String) -> Lens:
	_ensure()
	return _cache.get(id, _cache.get("standard_50"))


static func all() -> Array:
	_ensure()
	var out: Array = []
	for d: Dictionary in DATA:
		out.append(_cache[d["id"]])
	return out


static func ids() -> Array:
	var out: Array = []
	for d: Dictionary in DATA:
		out.append(d["id"])
	return out


## Lenses the player can currently put on the camera.
static func available() -> Array:
	if Game.is_sandbox():
		return all()
	var unlocked: Array = SaveSystem.profile.get("progress", {}).get("unlocked_lenses", [])
	var out: Array = []
	for l: Lens in all():
		if unlocked.has(l.id):
			out.append(l)
	if out.is_empty():
		out.append(get_lens("standard_50"))
	return out


## Grants any lens the player's reputation now reaches. Returns the new ones.
static func refresh_unlocks(reputation: int) -> Array:
	var progress: Dictionary = SaveSystem.profile.get("progress", {})
	var unlocked: Array = progress.get("unlocked_lenses", ["standard_50"])
	var newly: Array = []
	for l: Lens in all():
		if l.unlock_reputation <= reputation and not unlocked.has(l.id):
			unlocked.append(l.id)
			newly.append(l)
	progress["unlocked_lenses"] = unlocked
	SaveSystem.profile["progress"] = progress
	return newly


static func shutter_label(denominator: int) -> String:
	if denominator <= 1:
		return "1s"
	return "1/%d" % denominator


## EV100 the camera is metering for, from its own settings.
static func camera_ev(aperture: float, shutter_denominator: int, iso: int) -> float:
	var t := 1.0 / maxf(float(shutter_denominator), 0.0001)
	var ev := log(aperture * aperture / t) / log(2.0)
	return ev - log(float(iso) / 100.0) / log(2.0)
