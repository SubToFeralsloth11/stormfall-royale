class_name UiStyle
extends RefCounted
## Shared fonts, colours and style boxes for the intro, lobby and HUD.
## Everything uses system / fallback fonts; nothing is imported.

const YELLOW := Color(1.0, 0.86, 0.12)
const YELLOW_DARK := Color(0.78, 0.6, 0.02)
const BLUE := Color(0.13, 0.42, 0.95)
const NAVY := Color(0.04, 0.09, 0.25)
const PANEL := Color(0.05, 0.1, 0.28, 0.82)
const SHIELD := Color(0.3, 0.68, 1.0)
const HEALTH := Color(0.38, 0.88, 0.3)
const STORM := Color(0.48, 0.22, 0.85)

static var _bold: Font
static var _heavy: Font


## Heavy condensed sans (Impact / Arial Black when present, fallback otherwise).
static func bold() -> Font:
	if _bold == null:
		var sf := SystemFont.new()
		sf.font_names = PackedStringArray(["Impact", "Arial Black", "Helvetica Neue", "Arial", "DejaVu Sans"])
		sf.font_weight = 900
		sf.font_stretch = 75
		sf.fallbacks = [ThemeDB.fallback_font]
		_bold = sf
	return _bold


## Same family, slanted forward a little for headlines.
static func heavy() -> Font:
	if _heavy == null:
		var fv := FontVariation.new()
		fv.base_font = bold()
		fv.variation_transform = Transform2D(Vector2(1, 0), Vector2(-0.18, 1), Vector2.ZERO)
		_heavy = fv
	return _heavy


static func box(bg: Color, radius := 6, border := 0, border_col := Color.WHITE) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(radius)
	if border > 0:
		sb.set_border_width_all(border)
		sb.border_color = border_col
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	return sb


## Styles a button with a flat colour and hover / pressed variants.
static func style_button(b: Button, bg: Color, fg: Color, size := 22, radius := 6) -> void:
	b.add_theme_font_override("font", heavy())
	b.add_theme_font_size_override("font_size", size)
	b.add_theme_color_override("font_color", fg)
	b.add_theme_color_override("font_hover_color", fg)
	b.add_theme_color_override("font_pressed_color", fg)
	b.add_theme_color_override("font_focus_color", fg)
	b.add_theme_stylebox_override("normal", box(bg, radius))
	b.add_theme_stylebox_override("hover", box(bg.lightened(0.15), radius, 3, Color.WHITE))
	b.add_theme_stylebox_override("pressed", box(bg.darkened(0.15), radius, 3, Color.WHITE))
	b.add_theme_stylebox_override("focus", box(Color(0, 0, 0, 0), radius))


static func label(text: String, size: int, col := Color.WHITE, outline := 6, font: Font = null) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font if font != null else heavy())
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	if outline > 0:
		l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
		l.add_theme_constant_override("outline_size", outline)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## Outlined text helper for _draw code.
static func text(ci: CanvasItem, pos: Vector2, s: String, size: int, col: Color, align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0, outline := 5, font: Font = null) -> void:
	var f := font if font != null else bold()
	if outline > 0:
		ci.draw_string_outline(f, pos, s, align, width, size, outline, Color(0, 0, 0, col.a * 0.85))
	ci.draw_string(f, pos, s, align, width, size, col)
