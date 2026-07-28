class_name ContractBoard
extends Node
## Generates and tracks photographic assignments. Three are live at a time; a
## finished one is replaced by something new the next morning.

signal contracts_changed
signal contract_completed(contract: Contract)

const ACTIVE_SLOTS := 3

var contracts: Array[Contract] = []
var world: VoxelWorld
var sky: SkySystem

var _rng := RandomNumberGenerator.new()
var _counter := 0
## Free Roam and Sandbox never call setup(). Without this the board would
## happily write its empty contract list over a saved Expedition.
var _active := false

const GENRE_BRIEFS := {
	"wildlife": ["The society wants a clean animal study - subject sharp, background quiet.",
		"Bring back an animal picture that does not look like a snapshot."],
	"portrait": ["Fill the frame with one subject and let the eyes carry it.",
		"A close study. Get the light on the face."],
	"group": ["Three or more in one frame, all readable. Harder than it sounds.",
		"A gathering, composed rather than crowded."],
	"landscape": ["The land itself, with a horizon that means something.",
		"No subject required. Just make the country look like somewhere."],
	"street": ["Village life as it happens. People in their place.",
		"A street frame - buildings, people, and a reason to look."],
	"interior": ["Inside a cabin. Mixed light is the whole problem here.",
		"An interior that keeps detail in both the window and the corner."],
	"wedding": ["They have asked for one photograph. Do not miss it.",
		"Cover the ceremony. Nobody gets a second attempt."],
	"detail": ["Something small and exact: a print, a feather, frost on bark.",
		"Close work. Depth of field is the enemy."],
}


func setup(voxel_world: VoxelWorld, sky_system: SkySystem) -> void:
	world = voxel_world
	sky = sky_system
	_active = true
	_rng.seed = Game.world_seed + 3313
	_load()
	_fill()


func _load() -> void:
	contracts.clear()
	if Game.is_sandbox():
		return
	var stored: Array = SaveSystem.profile.get("progress", {}).get("contracts", [])
	for d: Dictionary in stored:
		contracts.append(Contract.from_dict(d))


func _save() -> void:
	if not _active or Game.is_sandbox():
		return
	var progress: Dictionary = SaveSystem.profile.get("progress", {})
	var out: Array = []
	for c in contracts:
		out.append(c.to_dict())
	progress["contracts"] = out
	SaveSystem.profile["progress"] = progress


func _fill() -> void:
	var guard := 0
	while contracts.size() < ACTIVE_SLOTS and guard < 40:
		guard += 1
		var c := _generate()
		if c == null or _duplicates_active(c):
			continue
		contracts.append(c)
	_save()
	contracts_changed.emit()


## Two assignments for the same animal, or the same genre, read as a bug even
## when they are technically different jobs.
func _duplicates_active(candidate: Contract) -> bool:
	for c in contracts:
		if c.title == candidate.title:
			return true
		if candidate.species_id != "" and c.species_id == candidate.species_id:
			return true
		if candidate.species_id == "" and candidate.genre != "" \
				and c.species_id == "" and c.genre == candidate.genre:
			return true
	return false


func _generate() -> Contract:
	var c := Contract.new()
	_counter += 1
	c.id = "c%d_%d" % [Game.world_seed, _counter]
	var roll := _rng.randf()

	if roll < 0.34:
		c.kind = Contract.Kind.SPECIES
		var species := _pick_species()
		if species == null:
			return null
		c.species_id = species.id
		c.genre = "portrait" if species.size_class != "small" else "wildlife"
		c.required_score = 55.0 + species.rarity * 22.0
		c.title = "Study: %s" % species.name
		c.brief = "%s Look for it %s." % [
			species.behaviour_note.split(".")[0] + ".",
			species.activity_label().to_lower()]
		c.reward = 90 + int(species.rarity * 160.0)
		if _rng.randf() < 0.35:
			c.light_phase = "golden hour"
			c.title += " at golden hour"
	elif roll < 0.62:
		c.kind = Contract.Kind.GENRE
		var genres := ["landscape", "street", "interior", "group", "portrait", "wildlife"]
		c.genre = genres[_rng.randi_range(0, genres.size() - 1)]
		c.required_score = 58.0 + _rng.randf_range(0.0, 16.0)
		c.required_count = 1 if _rng.randf() < 0.7 else 2
		var spec: Dictionary = PhotoScorer.GENRES.get(c.genre, {})
		c.title = "Commission: %s" % spec.get("label", c.genre)
		var briefs: Array = GENRE_BRIEFS.get(c.genre, ["Bring back something worth printing."])
		c.brief = briefs[_rng.randi_range(0, briefs.size() - 1)]
		c.reward = 80 + int(c.required_score)
	elif roll < 0.82:
		c.kind = Contract.Kind.COLLECTION
		c.required_count = _rng.randi_range(3, 5)
		c.required_score = 45.0
		if world != null and _rng.randf() < 0.6:
			c.biome_id = world.biome_at(0.0, 0.0)
		c.title = "Survey of %d species" % c.required_count
		c.brief = "A working record. Different species, each one identifiable."
		c.reward = 120 + c.required_count * 30
	else:
		c.kind = Contract.Kind.CONDITION
		var phases := ["golden hour", "blue hour", "overcast", "soft light"]
		c.light_phase = phases[_rng.randi_range(0, phases.size() - 1)]
		if _rng.randf() < 0.4:
			c.weather_id = ["mist", "rain", "snow"][_rng.randi_range(0, 2)]
		c.required_score = 60.0
		c.title = "Conditions: %s" % c.light_phase
		c.brief = "The society is collecting frames made in difficult light. Any subject."
		c.reward = 110
	return c


func _pick_species() -> Species:
	var all := SpeciesLibrary.all()
	if all.is_empty():
		return null
	# Prefer something the player has at least a chance of finding nearby.
	var biome := world.biome_at(0.0, 0.0) if world != null else ""
	var candidates: Array = []
	for s: Species in all:
		if biome == "" or s.biome_weight(biome) > 0.0:
			candidates.append(s)
	if candidates.is_empty():
		candidates = all
	return candidates[_rng.randi_range(0, candidates.size() - 1)]


func on_photo(record: Dictionary) -> void:
	if not _active:
		return
	var finished: Array[Contract] = []
	for c in contracts:
		if c.submit(record):
			finished.append(c)
	if finished.is_empty():
		_save()
		return
	for c in finished:
		var progress: Dictionary = SaveSystem.profile.get("progress", {})
		progress["reputation"] = int(progress.get("reputation", 0)) + c.reward
		var done: Array = progress.get("completed_contracts", [])
		done.append(c.id)
		progress["completed_contracts"] = done
		SaveSystem.profile["progress"] = progress
		Game.notify("Assignment complete: %s (+%d)" % [c.title, c.reward], "contract")
		AudioDirector.play("score_great", -6.0)
		contract_completed.emit(c)
		contracts.erase(c)
	_fill()
	SaveSystem.save_profile()


func active() -> Array[Contract]:
	return contracts


func reroll() -> void:
	contracts.clear()
	_fill()
