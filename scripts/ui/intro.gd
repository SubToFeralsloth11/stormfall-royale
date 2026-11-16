class_name IntroScreen
extends CanvasLayer
## Launch intro: a bold FORTNITE wordmark, then a red rubber stamp reading
## TEMU EDITION slams onto it (scale 3x -> 1x, rotated, screen shake, thud).
## Any key / click skips. Emits `finished` once and frees itself.

signal finished

const SLAM_AT := 1.2
const SLAM_TIME := 0.16
const HOLD := 1.5
const FADE := 0.3
const STAMP_RED := Color(0.96, 0.12, 0.12)
const STAMP_ANGLE := -12.0

const INK_SHADER := """
shader_type canvas_item;
uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear;
uniform sampler2D grain : repeat_enable, filter_linear;
uniform sampler2D blotch : repeat_enable, filter_linear;
void fragment() {
	vec4 c = textureLod(screen_texture, SCREEN_UV, 0.0);
	if (c.a > 0.0001) { c.rgb /= c.a; }
	vec2 p = SCREEN_UV * vec2(1.7778, 1.0);
	float g = texture(grain, p * 3.0).r;
	float b = texture(blotch, p * 0.9).r;
	float ink = mix(0.72, 1.0, smoothstep(0.25, 0.65, b));
	ink *= smoothstep(0.18, 0.34, g);
	COLOR = vec4(c.rgb, c.a * ink * 0.92);
}
"""

var _t := 0.0
var _done := false
var _emitted := false
var _slammed := false
var _shake := 0.0
var _root: Control
var _bg: Control
var _stamp_group: CanvasGroup
var _stamp: Control
var _splats := []


func _ready() -> void:
	layer = 60
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)
	_bg = Control.new()
	_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bg.draw.connect(_draw_bg)
	_root.add_child(_bg)
	_stamp_group = CanvasGroup.new()
	_stamp_group.fit_margin = 24.0
	var sm := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = INK_SHADER
	sm.shader = sh
	sm.set_shader_parameter("grain", _noise_tex(41, 0.09, 256))
	sm.set_shader_parameter("blotch", _noise_tex(7, 0.02, 256))
	_stamp_group.material = sm
	_stamp_group.visible = false
	_root.add_child(_stamp_group)
	_stamp = Control.new()
	_stamp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stamp.draw.connect(_draw_stamp)
	# CanvasGroup sizes its buffer from child rects, so the stamp needs a real
	# rect around the origin it draws at
	_stamp.size = Vector2(1100, 420)
	_stamp.position = -_stamp.size * 0.5
	_stamp_group.add_child(_stamp)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for i in 14:
		var a := rng.randf() * TAU
		_splats.append([Vector2(cos(a) * rng.randf_range(260, 420), sin(a) * rng.randf_range(90, 170)), rng.randf_range(2.0, 7.0)])


## Generated synchronously so the ink mask exists the moment the stamp lands.
static func _noise_tex(seed_v: int, freq: float, size: int) -> ImageTexture:
	var n := FastNoiseLite.new()
	n.seed = seed_v
	n.frequency = freq
	n.fractal_octaves = 3
	return ImageTexture.create_from_image(n.get_seamless_image(size, size))


func _input(event: InputEvent) -> void:
	if _emitted:
		return
	var skip: bool = (event is InputEventKey and event.pressed and not event.echo) \
		or (event is InputEventMouseButton and event.pressed) \
		or (event is InputEventJoypadButton and event.pressed)
	if skip:
		get_viewport().set_input_as_handled()
		_t = maxf(_t, SLAM_AT + SLAM_TIME + HOLD)
		_slammed = true


func _process(delta: float) -> void:
	if _done:
		return
	_t += delta
	if not _slammed and _t >= SLAM_AT + SLAM_TIME:
		_slammed = true
		_shake = 1.0
		Sfx.play("explosion", 1.35, -2.0)
		Sfx.play("pickaxe_crit", 0.6)
	_shake = maxf(0.0, _shake - delta * 2.6)
	var amp := 26.0 * _shake * _shake
	offset = Vector2(randf_range(-amp, amp), randf_range(-amp, amp))
	_layout()
	if _t >= SLAM_AT + SLAM_TIME + HOLD and not _emitted:
		_emitted = true
		_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
		finished.emit()       # lobby builds underneath while we fade out
	_root.modulate.a = _fade()
	if _t >= SLAM_AT + SLAM_TIME + HOLD + FADE:
		_finish()


func _layout() -> void:
	var s := _root.size
	_bg.queue_redraw()
	var st := _t - SLAM_AT
	_stamp_group.visible = st > 0.0
	if st <= 0.0:
		return
	var p := clampf(st / SLAM_TIME, 0.0, 1.0)
	var k := lerpf(3.0, 1.0, p * p)
	if p >= 1.0:
		# tiny overshoot bounce after impact
		var b := st - SLAM_TIME
		k = 1.0 + sin(minf(b, 0.25) / 0.25 * PI) * 0.04 * maxf(0.0, 1.0 - b * 4.0)
	var unit := s.y / 900.0
	_stamp_group.position = Vector2(s.x * 0.5 + 40.0 * unit, s.y * 0.5 + 70.0 * unit)
	_stamp_group.rotation = deg_to_rad(STAMP_ANGLE)
	_stamp_group.scale = Vector2.ONE * k * unit
	_stamp_group.self_modulate.a = 1.0
	_stamp.modulate.a = clampf(p * 1.6, 0.0, 1.0)
	_stamp.queue_redraw()


func _fade() -> float:
	return clampf(1.0 - (_t - (SLAM_AT + SLAM_TIME + HOLD)) / FADE, 0.0, 1.0)


func _draw_bg() -> void:
	var s := _bg.size
	var c := s * 0.5
	var unit := s.y / 900.0
	# deep blue -> purple backdrop with slow rotating rays
	_bg.draw_rect(Rect2(Vector2.ZERO, s), Color(0.05, 0.08, 0.3))
	var rays := 18
	for i in rays:
		var a0 := _t * 0.12 + i * TAU / rays
		var a1 := a0 + TAU / rays * 0.5
		var r := s.length()
		_bg.draw_colored_polygon(PackedVector2Array([c, c + Vector2(cos(a0), sin(a0)) * r, c + Vector2(cos(a1), sin(a1)) * r]),
			Color(0.25, 0.2, 0.7, 0.35))
	for i in 6:
		var rr := s.y * (0.9 - i * 0.14)
		_bg.draw_circle(c, rr, Color(0.35, 0.3, 0.95, 0.06))
	# wordmark: pops in over the first half second
	var a := clampf(_t / 0.45, 0.0, 1.0)
	var pop := 1.0 + (1.0 - a) * (1.0 - a) * -0.5 + sin(a * PI) * 0.06
	var size := int(200 * unit)
	var font := UiStyle.heavy()
	var txt := "FORTNITE"
	var w := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	_bg.draw_set_transform(c + Vector2(0, -20 * unit), 0.0, Vector2.ONE * pop)
	var base := Vector2(-w * 0.5, size * 0.33)
	var alpha := a
	for d in 6:
		_bg.draw_string(font, base + Vector2(d * 2, d * 3) * unit, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(0.02, 0.02, 0.12, alpha))
	_bg.draw_string_outline(font, base, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, size, int(14 * unit), Color(0.06, 0.1, 0.4, alpha))
	_bg.draw_string(font, base, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(1, 1, 1, alpha))
	# subtle lower highlight band
	_bg.draw_string(font, base + Vector2(0, -2 * unit), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(0.75, 0.88, 1.0, 0.25 * alpha))
	var sub := "BATTLE ROYALE (ALLEGEDLY)"
	var ss := int(30 * unit)
	var sw := UiStyle.bold().get_string_size(sub, HORIZONTAL_ALIGNMENT_LEFT, -1, ss).x
	UiStyle.text(_bg, Vector2(-sw * 0.5, base.y + 56 * unit), sub, ss, Color(1.0, 0.86, 0.2, alpha * clampf((_t - 0.4) * 3.0, 0.0, 1.0)), HORIZONTAL_ALIGNMENT_LEFT, -1, 6)
	_bg.draw_set_transform(Vector2.ZERO)


func _draw_stamp() -> void:
	_stamp.draw_set_transform(_stamp.size * 0.5)
	var font := UiStyle.bold()
	var size := 118
	var txt := "TEMU EDITION"
	var w := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var pad := Vector2(40, 26)
	var rect := Rect2(Vector2(-w * 0.5, -size * 0.5) - pad, Vector2(w, size) + pad * 2.0)
	var col := STAMP_RED
	# double border with uneven thickness
	_stamp.draw_rect(rect, col, false, 12.0)
	_stamp.draw_rect(rect.grow(-20), col, false, 4.0)
	# star rivets in the corners
	for corner: Vector2 in [rect.position, rect.position + Vector2(rect.size.x, 0), rect.end, rect.position + Vector2(0, rect.size.y)]:
		var inward := (rect.get_center() - corner).sign() * 34.0
		_stamp.draw_circle(corner + inward, 6.0, col)
	# ink bleed: a few faint offset copies under the main pass
	for o: Vector2 in [Vector2(2, 1), Vector2(-1, 2), Vector2(1, -2)]:
		_stamp.draw_string(font, Vector2(-w * 0.5, size * 0.36) + o, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(col, 0.35))
	_stamp.draw_string(font, Vector2(-w * 0.5, size * 0.36), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)
	if _slammed:
		for sp: Array in _splats:
			_stamp.draw_circle(sp[0], sp[1], col)


func _finish() -> void:
	if _done:
		return
	_done = true
	if not _emitted:
		_emitted = true
		finished.emit()
	queue_free()
