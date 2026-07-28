class_name Species
extends RefCounted
## Static description of one animal. Built from the raw tables in
## [SpeciesLibrary]; the Discovery Book reads its prose fields, the AI reads
## its senses and the spawner reads its habitat weights.

var id: String = ""
var name: String = ""
var latin: String = ""
var family: String = ""
var size_class: String = "medium"     ## small | medium | large
var rarity: float = 0.3               ## 0 common .. 1 legendary
var shape: String = "deer"            ## which voxel body to build
var palette: Dictionary = {}
var body_scale: float = 1.0
var shoulder_height: float = 1.1
var body_length: float = 1.9

var speed_walk: float = 1.6
var speed_run: float = 8.0
var turn_rate: float = 3.0
var can_fly: bool = false
var swims: bool = false

## Senses. Detection radius scales with the player's noise and the wind.
var vision_range: float = 55.0
var vision_angle: float = 120.0
var hearing_range: float = 40.0
var scent_range: float = 70.0
var wariness: float = 0.5             ## 0 tame .. 1 skittish
var flee_distance: float = 28.0
var curiosity: float = 0.2

var biomes: Dictionary = {}           ## biome id -> spawn weight
var active_hours: Array = []          ## [[start, end], ...] in 0..24
var herd_min: int = 1
var herd_max: int = 1
var altitude_pref: Vector2 = Vector2(-999.0, 999.0)
var near_water: float = 0.0           ## 0 indifferent .. 1 needs water

var diet: String = ""
var habitat_note: String = ""
var behaviour_note: String = ""
var features_note: String = ""
var track_note: String = ""
var track_shape: String = "cloven"    ## cloven | pad | claw | bird | round
var track_size: float = 0.32

var has_antlers: bool = false
var antler_points: Vector2i = Vector2i(0, 0)
var weight_range: Vector2 = Vector2(40.0, 90.0)
var photo_value: int = 40
var call_cooldown: Vector2 = Vector2(9.0, 26.0)
var call_chance: float = 0.5

var behaviours: Array = ["grazing", "alert", "walking", "resting", "fleeing"]


static func from_dict(data: Dictionary) -> Species:
	var s := Species.new()
	for key: String in data:
		if key in s:
			s.set(key, data[key])
	return s


func is_active_at(hour: float) -> bool:
	if active_hours.is_empty():
		return true
	for window: Array in active_hours:
		var a := float(window[0])
		var b := float(window[1])
		if a <= b:
			if hour >= a and hour <= b:
				return true
		elif hour >= a or hour <= b:
			return true
	return false


## How strongly this species prefers the given hour, 0.15 .. 1.0.
func activity_at(hour: float) -> float:
	if is_active_at(hour):
		return 1.0
	return 0.15 if size_class == "large" else 0.25


func biome_weight(biome_id: String) -> float:
	return float(biomes.get(biome_id, 0.0))


func herd_size(rng: RandomNumberGenerator) -> int:
	return rng.randi_range(herd_min, maxi(herd_min, herd_max))


func rarity_label() -> String:
	if rarity >= 0.85:
		return "Legendary"
	if rarity >= 0.65:
		return "Rare"
	if rarity >= 0.4:
		return "Uncommon"
	return "Common"


func size_label() -> String:
	match size_class:
		"small":
			return "Small"
		"large":
			return "Large"
		_:
			return "Medium"


func activity_label() -> String:
	if active_hours.is_empty():
		return "Active around the clock"
	var labels: Array[String] = []
	for window: Array in active_hours:
		labels.append("%02d:00-%02d:00" % [int(window[0]), int(window[1])])
	return ", ".join(labels)
