class_name UITheme
extends RefCounted
## The shared look: a field journal rather than a dashboard.
##
## Two surfaces, and the rule is which one the world is behind. Anything drawn
## over live gameplay is a warm, nearly transparent charcoal so the forest
## stays the subject; anything modal - the book, the menus, the shop - is
## parchment, because those are the moments you are meant to linger on.
##
## Nothing here is fully saturated. Every colour is a pigment that has been
## somewhere: moss, clay, rust, brass, weathered slate.

# ------------------------------------------------------------------- surfaces
## Warm charcoal, not blue-black. Low alpha: the HUD should almost disappear.
const PANEL := Color(0.086, 0.082, 0.074, 0.62)
const PANEL_SOLID := Color(0.105, 0.099, 0.090, 0.97)

## Parchment. Ivory with the warmth left in.
const PAPER := Color(0.945, 0.925, 0.878)
const PAPER_DARK := Color(0.878, 0.851, 0.792)
const PAPER_EDGE := Color(0.796, 0.761, 0.690)
const PAPER_INK := Color(0.145, 0.129, 0.106)
const PAPER_INK_DIM := Color(0.376, 0.345, 0.294)

# ----------------------------------------------------------------------- ink
const INK := Color(0.937, 0.925, 0.898)
const INK_DIM := Color(0.729, 0.714, 0.682)
const INK_FAINT := Color(0.541, 0.529, 0.502)

# -------------------------------------------------------------------- pigment
const COPPER := Color(0.780, 0.510, 0.310)
const BRASS := Color(0.839, 0.702, 0.408)
const RUST := Color(0.647, 0.361, 0.243)
const PINE := Color(0.196, 0.290, 0.243)
const MOSS := Color(0.416, 0.494, 0.353)
const SAGE := Color(0.639, 0.678, 0.588)
const CLAY := Color(0.616, 0.451, 0.337)
const SAND := Color(0.812, 0.749, 0.624)
const SLATE_BLUE := Color(0.451, 0.529, 0.588)
const FOG_BLUE := Color(0.678, 0.722, 0.749)

## Brass is the interface's one bright note, used sparingly.
const ACCENT := BRASS
const ACCENT_DIM := Color(0.573, 0.478, 0.290)
const GOOD := Color(0.514, 0.643, 0.451)
const WARN := Color(0.816, 0.616, 0.325)
const BAD := Color(0.714, 0.388, 0.325)

# --------------------------------------------------------------------- shape
## 12-18px. Cards and panels are soft-cornered; nothing is a sharp box.
const RADIUS := 14
const RADIUS_TIGHT := 10

## Nothing in this interface moves faster than a quarter of a second.
const EASE_FAST := 0.16
const EASE := 0.22
const EASE_SLOW := 0.25

const DISPLAY_FONT := "res://fonts/PlayfairDisplay.ttf"
const TEXT_FONT := "res://fonts/Inter.ttf"

static var _display: FontFile = null
static var _text: FontFile = null
static var _variations: Dictionary = {}


## Playfair, for the title, headings, place names and species names - and for
## nothing else. Long copy in a display face is unreadable.
static func display_font(weight: int = 600) -> Font:
	if _display == null and ResourceLoader.exists(DISPLAY_FONT):
		_display = load(DISPLAY_FONT)
	return _weighted(_display, weight, "d")


## Inter, for everything else.
static func text_font(weight: int = 400) -> Font:
	if _text == null and ResourceLoader.exists(TEXT_FONT):
		_text = load(TEXT_FONT)
	return _weighted(_text, weight, "t")


## Both faces are variable, so a weight is an axis value rather than a
## separate file. Cached because a FontVariation per label would be wasteful.
static func _weighted(base: FontFile, weight: int, tag: String) -> Font:
	if base == null:
		return null
	var key := "%s%d" % [tag, weight]
	if _variations.has(key):
		return _variations[key]
	var v := FontVariation.new()
	v.base_font = base
	v.variation_opentype = {"wght": weight}
	_variations[key] = v
	return v


# -------------------------------------------------------------------- panels

static func panel_style(color: Color = PANEL, radius: int = RADIUS,
		border: Color = Color(1, 1, 1, 0.055), shadow: bool = true) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.corner_radius_top_left = radius
	sb.corner_radius_top_right = radius
	sb.corner_radius_bottom_left = radius
	sb.corner_radius_bottom_right = radius
	sb.border_color = border
	sb.set_border_width_all(1)
	# Generous padding is most of what separates a considered panel from a
	# cramped one.
	sb.content_margin_left = 18
	sb.content_margin_right = 18
	sb.content_margin_top = 14
	sb.content_margin_bottom = 14
	# A soft drop shadow rather than an outline. Off for controls: a shadow
	# around every button reads as a grey slab, especially on parchment.
	if shadow:
		sb.shadow_color = Color(0.0, 0.0, 0.0, 0.28)
		sb.shadow_size = 10
		sb.shadow_offset = Vector2(0, 3)
	return sb


## Padding suited to a control rather than a panel.
static func control_style(color: Color, border: Color) -> StyleBoxFlat:
	var sb := panel_style(color, RADIUS_TIGHT, border, false)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	return sb


static func panel(color: Color = PANEL, radius: int = RADIUS) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", panel_style(color, radius))
	return p


## Parchment card, for modal surfaces and anything that should read as paper.
static func paper_panel(radius: int = RADIUS) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel",
		panel_style(PAPER, radius, PAPER_EDGE))
	return p


# --------------------------------------------------------------------- text

static func label(text: String, size: int = 15, color: Color = INK) -> Label:
	var l := Label.new()
	l.text = text
	var f := text_font(400)
	if f != null:
		l.add_theme_font_override("font", f)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	# A whisper of shadow, only enough to hold the text off a bright sky.
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.38))
	l.add_theme_constant_override("shadow_offset_x", 0)
	l.add_theme_constant_override("shadow_offset_y", 1)
	return l


## Small, letterspaced, quiet. For the little all-caps section markers.
static func eyebrow(text: String, color: Color = ACCENT_DIM) -> Label:
	var l := label(text.to_upper(), 10, color)
	var f := text_font(600)
	if f != null:
		l.add_theme_font_override("font", f)
	return l


static func rich(text: String, size: int = 15, color: Color = INK) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.text = text
	r.fit_content = true
	r.scroll_active = false
	var f := text_font(400)
	if f != null:
		r.add_theme_font_override("normal_font", f)
		r.add_theme_font_override("bold_font", text_font(650))
	r.add_theme_font_size_override("normal_font_size", size)
	r.add_theme_color_override("default_color", color)
	return r


static func heading(text: String, size: int = 26, color: Color = INK) -> Label:
	var l := label(text, size, color)
	var f := display_font(600)
	if f != null:
		l.add_theme_font_override("font", f)
	return l


# ------------------------------------------------------------------ controls

static func button(text: String, wide: bool = true) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_ALL
	var f := text_font(500)
	if f != null:
		b.add_theme_font_override("font", f)
	b.add_theme_font_size_override("font_size", 15)
	b.add_theme_color_override("font_color", INK_DIM)
	b.add_theme_color_override("font_hover_color", INK)
	b.add_theme_color_override("font_pressed_color", ACCENT)
	b.add_theme_color_override("font_focus_color", ACCENT)
	b.add_theme_color_override("font_disabled_color", INK_FAINT)
	# Buttons are almost invisible until you touch them: hover brightens
	# rather than announcing itself with a border.
	b.add_theme_stylebox_override("normal",
		control_style(Color(1, 1, 1, 0.030), Color(1, 1, 1, 0.05)))
	b.add_theme_stylebox_override("hover",
		control_style(Color(1, 1, 1, 0.075), Color(0.839, 0.702, 0.408, 0.34)))
	b.add_theme_stylebox_override("pressed",
		control_style(Color(0.839, 0.702, 0.408, 0.16), Color(0.839, 0.702, 0.408, 0.6)))
	b.add_theme_stylebox_override("focus",
		control_style(Color(0, 0, 0, 0), Color(0.839, 0.702, 0.408, 0.45)))
	b.add_theme_stylebox_override("disabled",
		control_style(Color(1, 1, 1, 0.012), Color(1, 1, 1, 0.03)))
	b.custom_minimum_size = Vector2(240, 40) if wide else Vector2(0, 32)
	return b


static func paper_button(text: String) -> Button:
	var b := button(text, false)
	b.add_theme_color_override("font_color", PAPER_INK)
	b.add_theme_color_override("font_hover_color", PAPER_INK)
	b.add_theme_color_override("font_pressed_color", RUST)
	b.add_theme_color_override("font_focus_color", RUST)
	# Almost nothing until you touch it: on paper, a filled button reads as a
	# grey slab, so the resting state is just a hairline on the parchment.
	b.add_theme_stylebox_override("normal",
		control_style(Color(1, 1, 1, 0.0), Color(0.35, 0.30, 0.22, 0.30)))
	b.add_theme_stylebox_override("hover",
		control_style(Color(0.647, 0.361, 0.243, 0.075), Color(0.35, 0.30, 0.22, 0.62)))
	b.add_theme_stylebox_override("pressed",
		control_style(Color(0.647, 0.361, 0.243, 0.16), Color(0.647, 0.361, 0.243, 0.7)))
	return b


static func paper_field(text: String) -> LineEdit:
	var e := LineEdit.new()
	e.text = text
	var f := text_font(400)
	if f != null:
		e.add_theme_font_override("font", f)
	e.add_theme_font_size_override("font_size", 14)
	e.add_theme_color_override("font_color", PAPER_INK)
	e.add_theme_color_override("caret_color", RUST)
	e.add_theme_stylebox_override("normal",
		control_style(Color(0.16, 0.14, 0.11, 0.05), Color(0.35, 0.30, 0.22, 0.35)))
	e.add_theme_stylebox_override("focus",
		control_style(Color(0.16, 0.14, 0.11, 0.05), Color(0.647, 0.361, 0.243, 0.65)))
	return e


static func separator(color: Color = Color(1, 1, 1, 0.075)) -> Panel:
	var p := Panel.new()
	p.custom_minimum_size = Vector2(0, 1)
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	p.add_theme_stylebox_override("panel", sb)
	return p


## The hairline rule used inside the journal, in ink rather than light.
static func paper_separator() -> Panel:
	return separator(Color(0.35, 0.30, 0.22, 0.30))


static func spacer(height: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, height)
	return c


static func slider(min_value: float, max_value: float, step: float,
		value: float) -> HSlider:
	var s := HSlider.new()
	s.min_value = min_value
	s.max_value = max_value
	s.step = step
	s.value = value
	s.custom_minimum_size = Vector2(220, 20)
	var grabber := StyleBoxFlat.new()
	grabber.bg_color = ACCENT
	grabber.set_corner_radius_all(7)
	grabber.content_margin_left = 7
	grabber.content_margin_right = 7
	grabber.content_margin_top = 7
	grabber.content_margin_bottom = 7
	var track := StyleBoxFlat.new()
	track.bg_color = Color(1, 1, 1, 0.10)
	track.set_corner_radius_all(2)
	track.content_margin_top = 2
	track.content_margin_bottom = 2
	var filled := StyleBoxFlat.new()
	filled.bg_color = Color(0.839, 0.702, 0.408, 0.55)
	filled.set_corner_radius_all(2)
	filled.content_margin_top = 2
	filled.content_margin_bottom = 2
	s.add_theme_stylebox_override("slider", track)
	s.add_theme_stylebox_override("grabber_area", filled)
	s.add_theme_stylebox_override("grabber_area_highlight", filled)
	return s


static func full_screen(control: Control) -> void:
	control.set_anchors_preset(Control.PRESET_FULL_RECT)
	control.offset_left = 0
	control.offset_top = 0
	control.offset_right = 0
	control.offset_bottom = 0


## Dim backdrop behind a modal panel. Warm, so it reads as dusk rather than
## as a grey overlay.
static func scrim(alpha: float = 0.72) -> ColorRect:
	var c := ColorRect.new()
	c.color = Color(0.055, 0.047, 0.039, alpha)
	full_screen(c)
	c.mouse_filter = Control.MOUSE_FILTER_STOP
	return c


## Fades a control in over the house easing time. Used instead of popping
## panels into existence.
static func fade_in(control: Control, duration: float = EASE) -> void:
	control.modulate.a = 0.0
	var tween := control.create_tween()
	tween.tween_property(control, "modulate:a", 1.0, duration) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


static func grade_text(grade: String) -> String:
	return "[b]%s[/b]" % grade
