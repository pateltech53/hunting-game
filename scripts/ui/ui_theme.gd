class_name UITheme
extends RefCounted
## Shared look for every panel in the game: a dark field instrument for the
## HUD, warm paper for the Discovery Book.

const INK := Color(0.90, 0.89, 0.85)
const INK_DIM := Color(0.68, 0.67, 0.63)
const INK_FAINT := Color(0.48, 0.48, 0.46)
const PANEL := Color(0.055, 0.065, 0.070, 0.88)
const PANEL_SOLID := Color(0.075, 0.085, 0.090, 1.0)
const ACCENT := Color(0.93, 0.72, 0.32)
const ACCENT_DIM := Color(0.62, 0.50, 0.26)
const GOOD := Color(0.55, 0.82, 0.50)
const WARN := Color(0.92, 0.66, 0.32)
const BAD := Color(0.88, 0.44, 0.40)
const PAPER := Color(0.92, 0.88, 0.80)
const PAPER_DARK := Color(0.83, 0.78, 0.68)
const PAPER_INK := Color(0.16, 0.14, 0.11)
const PAPER_INK_DIM := Color(0.38, 0.34, 0.28)


static func panel_style(color: Color = PANEL, radius: int = 6,
		border: Color = Color(1, 1, 1, 0.08)) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.corner_radius_top_left = radius
	sb.corner_radius_top_right = radius
	sb.corner_radius_bottom_left = radius
	sb.corner_radius_bottom_right = radius
	sb.border_color = border
	sb.set_border_width_all(1)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 9
	sb.content_margin_bottom = 9
	return sb


static func panel(color: Color = PANEL, radius: int = 6) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", panel_style(color, radius))
	return p


static func label(text: String, size: int = 15, color: Color = INK) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.55))
	l.add_theme_constant_override("shadow_offset_x", 1)
	l.add_theme_constant_override("shadow_offset_y", 1)
	return l


static func rich(text: String, size: int = 15, color: Color = INK) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.text = text
	r.fit_content = true
	r.scroll_active = false
	r.add_theme_font_size_override("normal_font_size", size)
	r.add_theme_color_override("default_color", color)
	return r


static func heading(text: String, size: int = 26, color: Color = ACCENT) -> Label:
	var l := label(text, size, color)
	return l


static func button(text: String, wide: bool = true) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_ALL
	b.add_theme_font_size_override("font_size", 17)
	b.add_theme_color_override("font_color", INK)
	b.add_theme_color_override("font_hover_color", Color(1, 1, 1))
	b.add_theme_color_override("font_pressed_color", ACCENT)
	b.add_theme_color_override("font_focus_color", ACCENT)
	b.add_theme_stylebox_override("normal", panel_style(Color(0.10, 0.11, 0.12, 0.92), 4))
	b.add_theme_stylebox_override("hover", panel_style(Color(0.16, 0.17, 0.18, 0.96), 4,
		Color(0.93, 0.72, 0.32, 0.5)))
	b.add_theme_stylebox_override("pressed", panel_style(Color(0.20, 0.17, 0.10, 1.0), 4,
		ACCENT))
	b.add_theme_stylebox_override("focus", panel_style(Color(0, 0, 0, 0), 4,
		Color(0.93, 0.72, 0.32, 0.7)))
	b.add_theme_stylebox_override("disabled", panel_style(Color(0.08, 0.08, 0.09, 0.7), 4,
		Color(1, 1, 1, 0.04)))
	if wide:
		b.custom_minimum_size = Vector2(260, 44)
	else:
		b.custom_minimum_size = Vector2(0, 34)
	return b


static func paper_button(text: String) -> Button:
	var b := button(text, false)
	b.add_theme_color_override("font_color", PAPER_INK)
	b.add_theme_color_override("font_hover_color", Color(0.05, 0.04, 0.03))
	b.add_theme_color_override("font_pressed_color", Color(0.35, 0.24, 0.10))
	b.add_theme_stylebox_override("normal", panel_style(PAPER_DARK, 3,
		Color(0.35, 0.30, 0.22, 0.4)))
	b.add_theme_stylebox_override("hover", panel_style(Color(0.88, 0.83, 0.72), 3,
		Color(0.35, 0.30, 0.22, 0.8)))
	b.add_theme_stylebox_override("pressed", panel_style(Color(0.74, 0.68, 0.56), 3,
		Color(0.30, 0.24, 0.16, 1.0)))
	return b


static func separator(color: Color = Color(1, 1, 1, 0.10)) -> Panel:
	var p := Panel.new()
	p.custom_minimum_size = Vector2(0, 1)
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	p.add_theme_stylebox_override("panel", sb)
	return p


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
	s.custom_minimum_size = Vector2(220, 22)
	return s


static func full_screen(control: Control) -> void:
	control.set_anchors_preset(Control.PRESET_FULL_RECT)
	control.offset_left = 0
	control.offset_top = 0
	control.offset_right = 0
	control.offset_bottom = 0


## Dim backdrop behind a modal panel.
static func scrim(alpha: float = 0.72) -> ColorRect:
	var c := ColorRect.new()
	c.color = Color(0.02, 0.025, 0.03, alpha)
	full_screen(c)
	c.mouse_filter = Control.MOUSE_FILTER_STOP
	return c


static func grade_text(grade: String) -> String:
	return "[b]%s[/b]" % grade
