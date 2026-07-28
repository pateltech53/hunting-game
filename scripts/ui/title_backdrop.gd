class_name TitleBackdrop
extends Control
## The living background behind the title.
##
## Painted rather than rendered: a full 3D scene behind the menu would cost
## more than the menu is worth, and this holds the same feeling - a valley at
## first light, fog moving through it, ridges receding into haze, birds
## crossing now and then. The clock runs slowly, so the light is different
## every time you look up.

const RIDGES := 5
const BIRD_COUNT := 7

## Dawn, morning, afternoon, dusk, night. Each entry is [top, horizon, sun].
const SKIES := [
	[Color(0.208, 0.239, 0.353), Color(0.867, 0.639, 0.478), Color(0.980, 0.784, 0.549)],
	[Color(0.443, 0.588, 0.706), Color(0.792, 0.855, 0.878), Color(1.000, 0.960, 0.878)],
	[Color(0.373, 0.541, 0.694), Color(0.749, 0.812, 0.831), Color(1.000, 0.973, 0.914)],
	[Color(0.259, 0.243, 0.318), Color(0.851, 0.529, 0.361), Color(0.965, 0.702, 0.451)],
	[Color(0.071, 0.086, 0.133), Color(0.176, 0.208, 0.278), Color(0.463, 0.510, 0.588)],
]

var _t := 0.0
var _phase := 0.0                  ## 0..5, wraps; fractional part blends
var _ridge_seeds: Array = []
var _birds: Array = []
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	UITheme.full_screen(self)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rng.randomize()
	# Start somewhere in the first half of the day more often than not, so the
	# menu usually greets you with light rather than darkness.
	_phase = _rng.randf_range(0.0, 3.4)
	for i in RIDGES:
		_ridge_seeds.append(_rng.randf_range(0.0, 100.0))
	for i in BIRD_COUNT:
		_birds.append({
			"t": _rng.randf_range(0.0, 1.0),
			"y": _rng.randf_range(0.12, 0.42),
			"speed": _rng.randf_range(0.010, 0.024),
			"scale": _rng.randf_range(0.6, 1.3),
			"flap": _rng.randf_range(0.0, TAU),
		})


func _process(delta: float) -> void:
	_t += delta
	# A full day every four minutes: slow enough to feel still, fast enough
	# that lingering on the menu is rewarded.
	_phase = fposmod(_phase + delta * (5.0 / 240.0), 5.0)
	for bird: Dictionary in _birds:
		bird["t"] = fposmod(float(bird["t"]) + delta * float(bird["speed"]), 1.25)
		bird["flap"] = float(bird["flap"]) + delta * 7.0
	queue_redraw()


func _sky() -> Array:
	var a: int = int(floorf(_phase)) % SKIES.size()
	var b: int = (a + 1) % SKIES.size()
	var f: float = smoothstep(0.0, 1.0, _phase - floorf(_phase))
	var out: Array = []
	for i in 3:
		out.append((SKIES[a][i] as Color).lerp(SKIES[b][i] as Color, f))
	return out


func _draw() -> void:
	var r := get_rect().size
	var sky := _sky()
	var top: Color = sky[0]
	var horizon: Color = sky[1]
	var sun: Color = sky[2]
	var skyline := r.y * 0.62

	# --- sky, as horizontal bands --------------------------------------------
	var bands := 44
	for i in bands:
		var f := float(i) / float(bands - 1)
		var y := f * skyline
		var h := skyline / float(bands) + 1.0
		# Squared blend keeps the warmth low and near the horizon.
		draw_rect(Rect2(0.0, y, r.x, h), top.lerp(horizon, f * f))

	# --- the sun, low and hazy ------------------------------------------------
	var sun_x := r.x * (0.24 + 0.52 * clampf(_phase / 5.0, 0.0, 1.0))
	var sun_y := skyline - r.y * (0.06 + 0.20 * sin(clampf(_phase / 5.0, 0.0, 1.0) * PI))
	for i in 7:
		var rad := r.y * (0.020 + float(i) * 0.026)
		draw_circle(Vector2(sun_x, sun_y), rad,
			Color(sun.r, sun.g, sun.b, 0.15 / (1.0 + float(i) * 0.85)))

	# --- ridges, furthest first ----------------------------------------------
	for layer in RIDGES:
		var depth := float(layer) / float(RIDGES - 1)
		var base := skyline - r.y * 0.06 + depth * r.y * 0.30
		# Distant ridges wash out toward the horizon colour: aerial perspective.
		var col: Color = UITheme.PINE.lerp(horizon, 0.74 - depth * 0.62)
		col.a = 1.0
		_draw_ridge(base, r, float(_ridge_seeds[layer]), 0.0016 + depth * 0.0022,
			r.y * (0.16 - depth * 0.085), col, depth)

	# --- fog banks drifting through the valley -------------------------------
	for i in 3:
		var speed := 0.006 + float(i) * 0.004
		var offset := fposmod(_t * speed + float(i) * 0.37, 1.4) - 0.2
		var y := skyline - r.y * (0.02 + float(i) * 0.055)
		var height := r.y * (0.05 + float(i) * 0.02)
		var alpha := 0.10 + 0.05 * sin(_t * 0.15 + float(i))
		var fog: Color = Color(0.898, 0.910, 0.898, alpha)
		# Soft-edged band: a few stacked rects with falling alpha.
		for s in 5:
			var sf := float(s) / 4.0
			var band := Color(fog.r, fog.g, fog.b, fog.a * (1.0 - absf(sf - 0.5) * 1.7))
			draw_rect(Rect2(r.x * (offset - 0.25), y + sf * height,
				r.x * 1.5, height * 0.3), band)

	# --- birds ----------------------------------------------------------------
	for bird: Dictionary in _birds:
		var bx := r.x * (float(bird["t"]) * 1.2 - 0.1)
		var by := r.y * float(bird["y"]) + sin(_t * 0.4 + float(bird["flap"]) * 0.1) * 6.0
		if bx < -20.0 or bx > r.x + 20.0:
			continue
		var w: float = 7.0 * float(bird["scale"])
		var flap: float = sin(float(bird["flap"])) * 0.5
		var ink := Color(0.14, 0.14, 0.16, 0.42)
		draw_line(Vector2(bx - w, by + flap * w), Vector2(bx, by), ink, 1.6)
		draw_line(Vector2(bx, by), Vector2(bx + w, by + flap * w), ink, 1.6)

	# --- ground ---------------------------------------------------------------
	var ground_top: Color = UITheme.PINE.lerp(Color(0.086, 0.098, 0.086), 0.5)
	draw_rect(Rect2(0.0, skyline + r.y * 0.30, r.x, r.y), ground_top)

	# --- vignette, to hold the eye on the menu --------------------------------
	for i in 9:
		var f := float(i) / 8.0
		var inset := f * r.x * 0.10
		var a := 0.055 * (1.0 - f)
		draw_rect(Rect2(0.0, 0.0, inset, r.y), Color(0.02, 0.02, 0.025, a))
		draw_rect(Rect2(r.x - inset, 0.0, inset, r.y), Color(0.02, 0.02, 0.025, a))


## One ridge line, as a filled polygon under a value-noise silhouette.
func _draw_ridge(base: float, r: Vector2, seed_offset: float, frequency: float,
		amplitude: float, col: Color, depth: float) -> void:
	var points := PackedVector2Array()
	var step := 6.0
	var drift := _t * (0.8 + depth * 2.4)          # nearer ridges slide faster
	var x := -step
	while x <= r.x + step:
		var n := _fbm((x + drift) * frequency + seed_offset)
		points.append(Vector2(x, base - n * amplitude))
		x += step
	points.append(Vector2(r.x + step, r.y))
	points.append(Vector2(-step, r.y))
	draw_colored_polygon(points, col)


## Cheap 1D value noise, two octaves. Enough for a skyline.
func _fbm(x: float) -> float:
	return _noise(x) * 0.65 + _noise(x * 2.3 + 11.0) * 0.35


func _noise(x: float) -> float:
	var i: float = floorf(x)
	var f: float = x - i
	var a := _hash(i)
	var b := _hash(i + 1.0)
	var u: float = f * f * (3.0 - 2.0 * f)
	return a + (b - a) * u


func _hash(n: float) -> float:
	return fposmod(sin(n * 127.1) * 43758.5453, 1.0)
