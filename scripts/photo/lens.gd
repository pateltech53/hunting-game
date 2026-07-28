class_name Lens
extends RefCounted
## One lens in the bag. Focal length drives field of view, maximum aperture
## drives how much light you can gather and how thin the depth of field gets.

const SENSOR_HEIGHT_MM := 24.0
const SENSOR_WIDTH_MM := 36.0
const CIRCLE_OF_CONFUSION_MM := 0.029

var id := ""
var name := ""
var short_name := ""
var focal_min := 50.0
var focal_max := 50.0
var aperture_min := 1.8      ## widest, i.e. smallest f-number
var aperture_max := 16.0
var min_focus := 0.45        ## metres
var stability := 1.0         ## 0..1, how well it damps hand shake
var macro := false
var blurb := ""
var unlock_reputation := 0
var favours: Array = []      ## genres this glass is made for


static func from_dict(d: Dictionary) -> Lens:
	var l := Lens.new()
	for key: String in d:
		if key in l:
			l.set(key, d[key])
	if l.short_name == "":
		l.short_name = "%dmm" % int(l.focal_min)
	return l


func is_zoom() -> bool:
	return focal_max > focal_min + 0.5


## Vertical field of view for a focal length on a full-frame sensor.
func fov_for(focal: float) -> float:
	return rad_to_deg(2.0 * atan(SENSOR_HEIGHT_MM * 0.5 / maxf(focal, 1.0)))


func horizontal_fov_for(focal: float) -> float:
	return rad_to_deg(2.0 * atan(SENSOR_WIDTH_MM * 0.5 / maxf(focal, 1.0)))


func clamp_focal(focal: float) -> float:
	return clampf(focal, focal_min, focal_max)


func clamp_aperture(f: float) -> float:
	return clampf(f, aperture_min, aperture_max)


## Hyperfocal distance in metres.
func hyperfocal(focal: float, aperture: float) -> float:
	var h_mm := (focal * focal) / (aperture * CIRCLE_OF_CONFUSION_MM) + focal
	return h_mm * 0.001


## Near and far limits of acceptable sharpness, in metres.
func depth_of_field(focal: float, aperture: float, subject_distance: float) -> Vector2:
	var s := maxf(subject_distance, min_focus)
	var h := hyperfocal(focal, aperture)
	var f := focal * 0.001
	var near_limit := s * (h - f) / maxf(h + s - 2.0 * f, 0.0001)
	var far_limit := INF
	if s < h:
		far_limit = s * (h - f) / maxf(h - s, 0.0001)
	return Vector2(maxf(near_limit, min_focus), far_limit if far_limit < 4000.0 else 4000.0)


func display_focal(focal: float) -> String:
	if is_zoom():
		return "%d-%dmm @ %dmm" % [int(focal_min), int(focal_max), int(focal)]
	return "%dmm" % int(focal)
