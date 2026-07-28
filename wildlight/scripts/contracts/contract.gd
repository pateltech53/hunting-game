class_name Contract
extends RefCounted
## One photographic assignment. Contracts are what turn "take pictures" into
## "be in the right place at the right hour with the right lens on".

enum Kind { GENRE, SPECIES, COLLECTION, CONDITION }

var id := ""
var kind: Kind = Kind.GENRE
var title := ""
var brief := ""
var genre := ""
var species_id := ""
var biome_id := ""
var required_score := 60.0
var required_count := 1
var light_phase := ""
var weather_id := ""
var reward := 80
var progress := 0
var complete := false
var seen_species: Array = []


func matches(record: Dictionary) -> bool:
	if float(record.get("score", 0.0)) < required_score:
		return false
	if genre != "" and record.get("genre", "") != genre:
		return false
	if species_id != "" and record.get("species", "") != species_id:
		return false
	if biome_id != "" and record.get("biome", "") != biome_id:
		return false
	if light_phase != "" and record.get("light_phase", "") != light_phase:
		return false
	if weather_id != "" and record.get("weather", "") != weather_id:
		return false
	return true


## Returns true when this photo finished the job.
func submit(record: Dictionary) -> bool:
	if complete or not matches(record):
		return false
	if kind == Kind.COLLECTION:
		var s: String = record.get("species", "")
		if s == "" or seen_species.has(s):
			return false
		seen_species.append(s)
		progress = seen_species.size()
	else:
		progress += 1
	if progress >= required_count:
		complete = true
	return complete


func progress_text() -> String:
	if complete:
		return "Complete"
	return "%d / %d" % [progress, required_count]


func requirement_text() -> String:
	var bits: Array[String] = []
	if genre != "":
		bits.append(PhotoScorer.GENRES.get(genre, {}).get("label", genre))
	if species_id != "":
		var s := SpeciesLibrary.get_species(species_id)
		if s != null:
			bits.append(s.name)
	if biome_id != "":
		bits.append("in the %s" % BiomeLibrary.display_name(biome_id))
	if light_phase != "":
		bits.append("during %s" % light_phase)
	if weather_id != "":
		bits.append("in %s" % WeatherSystem.PRESETS.get(weather_id, {}).get("name", weather_id))
	bits.append("scoring %d+" % int(required_score))
	return ", ".join(bits)


func to_dict() -> Dictionary:
	return {
		"id": id, "kind": int(kind), "title": title, "brief": brief, "genre": genre,
		"species_id": species_id, "biome_id": biome_id, "required_score": required_score,
		"required_count": required_count, "light_phase": light_phase,
		"weather_id": weather_id, "reward": reward, "progress": progress,
		"complete": complete, "seen_species": seen_species,
	}


static func from_dict(d: Dictionary) -> Contract:
	var c := Contract.new()
	for key: String in d:
		if key == "kind":
			c.kind = int(d[key]) as Kind
		elif key in c:
			c.set(key, d[key])
	return c
