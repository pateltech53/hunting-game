class_name Economy
extends Node
## Money, and the things worth spending it on.
##
## Photographs are the income: a frame is worth what it is good, how rare the
## animal was, and whether it is the first of its kind. Meat is a smaller,
## steadier second line for anything you shoot. Everything you buy changes how
## you play rather than just raising a number - longer glass, a steadier
## platform, quieter boots, eyes that work after dark.

signal funds_changed(amount: int)
signal gear_changed(id: String)
signal sold(text: String)

## Gear the outfitter stocks. `effect` is read by the systems it touches, so
## adding an entry here is most of the work of adding an upgrade.
const CATALOGUE := [
	{
		"id": "lens_telephoto_200", "name": "200mm Telephoto", "price": 900,
		"kind": "lens", "value": "telephoto_200",
		"blurb": "Reach. Fills the frame with a deer at forty metres, which is as close as most will let you get.",
	},
	{
		"id": "lens_wide_24", "name": "24mm Wide", "price": 620,
		"kind": "lens", "value": "wide_24",
		"blurb": "For landscapes and interiors, where the subject is the place rather than the animal.",
	},
	{
		"id": "lens_macro_100", "name": "100mm Macro", "price": 780,
		"kind": "lens", "value": "macro_100",
		"blurb": "Tracks, feathers and the small things. Close focus where nothing else will.",
	},
	{
		"id": "tripod", "name": "Carbon Tripod", "price": 480,
		"kind": "steady", "value": 0.62,
		"blurb": "Kills most of the sway. The difference between a sharp frame at dusk and a smeared one.",
	},
	{
		"id": "binoculars", "name": "10x42 Binoculars", "price": 350,
		"kind": "spot", "value": 2.1,
		"blurb": "Doubles the range you can identify an animal from, so you know what you are stalking before you commit.",
	},
	{
		"id": "camo", "name": "Camouflage Layer", "price": 400,
		"kind": "stealth", "value": 0.62,
		"blurb": "Animals notice you later and from closer. Nothing else buys you as much time.",
	},
	{
		"id": "boots", "name": "Soft-Soled Boots", "price": 260,
		"kind": "quiet", "value": 0.55,
		"blurb": "Halves the noise you make walking. Bark and leaf litter stop giving you away.",
	},
	{
		"id": "nightvision", "name": "Night Vision", "price": 1400,
		"kind": "night", "value": 1.0,
		"blurb": "Opens up the hours when most of the forest is actually awake.",
	},
	{
		"id": "gps", "name": "GPS Tracker", "price": 300,
		"kind": "gps", "value": 1.0,
		"blurb": "Marks where you found each species, and puts them on the map for good.",
	},
	{
		"id": "backpack", "name": "Expedition Pack", "price": 340,
		"kind": "carry", "value": 2.0,
		"blurb": "Carry more meat out in one trip instead of leaving it behind.",
	},
]


func _ready() -> void:
	_ensure_keys()


func _ensure_keys() -> void:
	var progress: Dictionary = SaveSystem.profile.get("progress", {})
	if not progress.has("funds"):
		progress["funds"] = 250
	if not progress.has("gear"):
		progress["gear"] = []
	if not progress.has("larder"):
		progress["larder"] = 0.0
	SaveSystem.profile["progress"] = progress


func funds() -> int:
	return int(SaveSystem.profile.get("progress", {}).get("funds", 0))


func owns(gear_id: String) -> bool:
	var list: Array = SaveSystem.profile.get("progress", {}).get("gear", [])
	return gear_id in list


## Reads an owned upgrade's effect value, or `fallback` when it is not owned.
## Every system that an upgrade touches asks through here.
func effect(kind: String, fallback: float) -> float:
	for item: Dictionary in CATALOGUE:
		if item["kind"] != kind:
			continue
		if owns(String(item["id"])) and typeof(item["value"]) != TYPE_STRING:
			return float(item["value"])
	return fallback


func add_funds(amount: int) -> void:
	var progress: Dictionary = SaveSystem.profile.get("progress", {})
	progress["funds"] = maxi(0, int(progress.get("funds", 0)) + amount)
	SaveSystem.profile["progress"] = progress
	funds_changed.emit(funds())


func can_afford(price: int) -> bool:
	return funds() >= price


func buy(gear_id: String) -> bool:
	var item := catalogue_entry(gear_id)
	if item.is_empty() or owns(gear_id):
		return false
	if not can_afford(int(item["price"])):
		Game.notify("Not enough for the %s." % item["name"], "warn")
		return false
	add_funds(-int(item["price"]))
	var progress: Dictionary = SaveSystem.profile.get("progress", {})
	var list: Array = progress.get("gear", [])
	list.append(gear_id)
	progress["gear"] = list
	SaveSystem.profile["progress"] = progress
	# A lens is the one kind of gear that also has to reach the camera bag.
	if item["kind"] == "lens":
		var unlocked: Array = progress.get("unlocked_lenses", [])
		if String(item["value"]) not in unlocked:
			unlocked.append(String(item["value"]))
			progress["unlocked_lenses"] = unlocked
			SaveSystem.profile["progress"] = progress
	AudioDirector.play("score_good", -10.0)
	Game.notify("Bought the %s." % item["name"], "info")
	gear_changed.emit(gear_id)
	SaveSystem.save_profile()
	return true


func catalogue_entry(gear_id: String) -> Dictionary:
	for item: Dictionary in CATALOGUE:
		if item["id"] == gear_id:
			return item
	return {}


# ---------------------------------------------------------------- valuation

## Five stars, from the same 0-100 the scorer already produces. The thresholds
## are deliberately mean at the top: five stars should be rare enough to mean
## something when it happens.
static func stars(score: float) -> int:
	if score >= 92.0:
		return 5
	if score >= 82.0:
		return 4
	if score >= 68.0:
		return 3
	if score >= 50.0:
		return 2
	return 1


static func star_text(score: float) -> String:
	var n := stars(score)
	return "★".repeat(n) + "☆".repeat(5 - n)


## What the wildlife centre pays for a frame. Quality is the dominant term -
## a five-star common rabbit beats a one-star wolf - but rarity multiplies,
## which is what makes the legendaries worth hunting for.
static func photo_price(record: Dictionary, species: Species,
		first_of_species: bool) -> int:
	var score := float(record.get("score", 0.0))
	if score < 40.0:
		return 0                                    # nobody buys a bad frame
	var base: float = species.photo_value if species != null else 40.0
	# 40 -> 0.1, 100 -> 1.0, curving so the top of the range pays properly.
	var quality: float = pow(clampf((score - 40.0) / 60.0, 0.0, 1.0), 1.6)
	var value := base * (0.25 + quality * 2.4)
	if first_of_species:
		value *= 1.8
	return int(round(value))


## Meat, sold to the butcher. Big animals are worth more but you are limited
## by what you can carry.
static func meat_price(kilos: float) -> int:
	return int(round(kilos * 3.4))
