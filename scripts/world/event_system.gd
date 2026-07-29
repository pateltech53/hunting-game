class_name EventSystem
extends Node
## Rare conditions worth stopping for.
##
## Weather is the everyday churn; these are the things you tell someone about
## afterwards. Each one is gated on the hour, the season and the weather, so
## they arrive when they would actually happen - fog at dawn, aurora on a clear
## winter night, a rainbow only while the rain is clearing. Each is also a
## photographic subject in its own right, worth a bonus on any frame taken
## while it is running.

signal event_started(id: String, display: String)
signal event_ended(id: String)

## `window` is [earliest hour, latest hour]; a window that wraps midnight is
## written with the larger number first. `seasons` empty means any.
const EVENTS := {
	"morning_fog": {
		"name": "Morning Fog",
		"blurb": "The valley has filled overnight. Everything past thirty metres is a rumour.",
		"window": [4.5, 8.5], "seasons": ["autumn", "spring"], "weather": ["fair", "overcast"],
		"minutes": [4.0, 8.0], "chance": 0.55, "bonus": 14.0,
	},
	"golden_hour": {
		"name": "Golden Hour",
		"blurb": "Low sun, long shadows, and every animal edged in light.",
		"window": [17.6, 19.4], "seasons": [], "weather": ["fair"],
		"minutes": [2.5, 4.0], "chance": 0.7, "bonus": 12.0,
	},
	"rainbow": {
		"name": "Rainbow",
		"blurb": "The rain is moving off and the sun has caught it.",
		"window": [8.0, 18.0], "seasons": [], "weather": ["showers", "storm"],
		"minutes": [1.5, 3.0], "chance": 0.4, "bonus": 20.0,
	},
	"aurora": {
		"name": "Northern Lights",
		"blurb": "Green light moving over the ridge, slow as breathing.",
		"window": [21.5, 3.5], "seasons": ["winter", "autumn"], "weather": ["fair"],
		"minutes": [5.0, 9.0], "chance": 0.35, "bonus": 30.0,
	},
	"meteor_shower": {
		"name": "Meteor Shower",
		"blurb": "One every few seconds, all out of the same patch of sky.",
		"window": [22.5, 4.0], "seasons": [], "weather": ["fair"],
		"minutes": [3.0, 6.0], "chance": 0.30, "bonus": 26.0,
	},
	"bloom": {
		"name": "Rare Bloom",
		"blurb": "The meadow has come out all at once. It will not last the week.",
		"window": [7.0, 19.0], "seasons": ["spring"], "weather": ["fair", "overcast"],
		"minutes": [6.0, 10.0], "chance": 0.45, "bonus": 16.0,
	},
	"first_snow": {
		"name": "First Snow",
		"blurb": "Coming down in earnest, and settling. Tracks will read like print.",
		"window": [0.0, 24.0], "seasons": ["winter"], "weather": ["snow", "overcast"],
		"minutes": [4.0, 8.0], "chance": 0.5, "bonus": 18.0,
	},
	"rut": {
		"name": "The Rut",
		"blurb": "Stags are roaring somewhere off the ridge and paying you no attention at all.",
		"window": [5.0, 10.0], "seasons": ["autumn"], "weather": [],
		"minutes": [5.0, 9.0], "chance": 0.5, "bonus": 22.0,
	},
}

var sky: SkySystem
var weather: WeatherSystem
var seasons: SeasonSystem

var active := ""
var _remaining := 0.0
var _cooldown := 45.0
var _seen_today: Array = []
var _last_hour := 0.0
var _rng := RandomNumberGenerator.new()


func setup(sky_system: SkySystem, weather_system: WeatherSystem,
		season_system: SeasonSystem, world_seed: int) -> void:
	sky = sky_system
	weather = weather_system
	seasons = season_system
	_rng.seed = world_seed ^ 0x5EED


func _process(delta: float) -> void:
	if Game.is_paused or sky == null:
		return

	# A fresh day makes everything eligible again.
	var hour: float = sky.time_of_day
	if hour < _last_hour:
		_seen_today.clear()
	_last_hour = hour

	if active != "":
		_remaining -= delta
		if _remaining <= 0.0:
			var ended := active
			active = ""
			event_ended.emit(ended)
		return

	_cooldown -= delta
	if _cooldown > 0.0:
		return
	# Check a few times a minute rather than every frame.
	_cooldown = 20.0
	_try_start(hour)


func _try_start(hour: float) -> void:
	var candidates: Array = []
	for id: String in EVENTS:
		if id in _seen_today:
			continue
		var e: Dictionary = EVENTS[id]
		if not _in_window(hour, e["window"]):
			continue
		var season_list: Array = e["seasons"]
		if not season_list.is_empty() and seasons != null \
				and seasons.id() not in season_list:
			continue
		var weather_list: Array = e["weather"]
		if not weather_list.is_empty() and weather != null \
				and weather.current not in weather_list:
			continue
		candidates.append(id)
	if candidates.is_empty():
		return

	var pick: String = candidates[_rng.randi_range(0, candidates.size() - 1)]
	var entry: Dictionary = EVENTS[pick]
	if _rng.randf() > float(entry["chance"]):
		return
	start(pick)


## Windows that wrap midnight are written with the larger number first.
func _in_window(hour: float, window: Array) -> bool:
	var from := float(window[0])
	var to := float(window[1])
	if from <= to:
		return hour >= from and hour <= to
	return hour >= from or hour <= to


func start(id: String) -> void:
	if not EVENTS.has(id):
		return
	var entry: Dictionary = EVENTS[id]
	active = id
	_seen_today.append(id)
	var span: Array = entry["minutes"]
	_remaining = _rng.randf_range(float(span[0]), float(span[1])) * 60.0
	AudioDirector.play("discovery", -10.0, 0.9)
	AudioDirector.set_mood(AudioDirector.Mood.WONDER)
	Game.notify("%s — %s" % [entry["name"], entry["blurb"]], "discovery")
	event_started.emit(id, String(entry["name"]))


func stop() -> void:
	if active == "":
		return
	var ended := active
	active = ""
	_remaining = 0.0
	event_ended.emit(ended)


func display_name() -> String:
	if active == "":
		return ""
	return String(EVENTS[active]["name"])


## Added to any photograph taken while the event is running. This is the whole
## incentive to drop what you are doing and go and shoot it.
func photo_bonus() -> float:
	if active == "":
		return 0.0
	return float(EVENTS[active]["bonus"])


func minutes_left() -> float:
	return _remaining / 60.0
