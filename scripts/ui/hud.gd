class_name Hud
extends CanvasLayer
## In-match HUD. Contract used by gameplay code:
##   setup(game, pawn, cam), hit_marker(head), flash_damage(amount), set_hint(text), push_kill(text),
##   show_end(placement, kills, victory). Reads everything else from pawn / game.hud_info().

var game: Match
var pawn: Pawn
var cam: Camera3D
var hint := ""
var damage_flash := 0.0
var _hit_t := 0.0
var _hit_head := false
var _cross: Control
var _info: Label
var _bars: Control
var _hint: Label
var _flash: ColorRect


func setup(g: Match, p: Pawn, c: Camera3D) -> void:
	game = g
	pawn = p
	cam = c
	_build()


func hit_marker(head: bool) -> void:
	_hit_t = 0.18
	_hit_head = head


func flash_damage(_amount: float) -> void:
	damage_flash = 1.0


func set_hint(t: String) -> void:
	hint = t
	_hint.text = t


func push_kill(_text: String) -> void:
	pass


func show_end(_placement: int, _kills: int, _victory: bool) -> void:
	pass



func _build() -> void:
	_flash = ColorRect.new()
	_flash.color = Color(1, 0, 0, 0)
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_flash)
	_cross = Control.new()
	_cross.set_anchors_preset(Control.PRESET_FULL_RECT)
	_cross.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cross.draw.connect(_draw_cross)
	add_child(_cross)
	_bars = Control.new()
	_bars.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bars.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bars.draw.connect(_draw_bars)
	add_child(_bars)
	_info = Label.new()
	_info.position = Vector2(20, 16)
	_info.add_theme_font_size_override("font_size", 18)
	_info.add_theme_color_override("font_outline_color", Color.BLACK)
	_info.add_theme_constant_override("outline_size", 6)
	add_child(_info)
	_hint = Label.new()
	_hint.set_anchors_preset(Control.PRESET_CENTER)
	_hint.position = Vector2(-150, 70)
	_hint.size = Vector2(300, 30)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.add_theme_font_size_override("font_size", 20)
	_hint.add_theme_color_override("font_outline_color", Color.BLACK)
	_hint.add_theme_constant_override("outline_size", 6)
	add_child(_hint)


func _process(delta: float) -> void:
	if pawn == null:
		return
	_hit_t = maxf(0.0, _hit_t - delta)
	damage_flash = maxf(0.0, damage_flash - delta * 2.0)
	_flash.color = Color(0.9, 0.1, 0.1, damage_flash * 0.25)
	var it := pawn.current_item()
	var wtxt := "Pickaxe"
	if not it.is_empty():
		wtxt = "%s %s" % [Cfg.RARITY_NAMES[it.rarity], Items.display_name(it)]
		if Items.is_weapon(it):
			var w: Dictionary = Items.WEAPONS[it.id]
			wtxt += "   %d / %d" % [it.ammo, pawn.ammo[w.ammo]]
			if pawn.reload_left >= 0.0:
				wtxt += "  (reloading)"
		else:
			wtxt += " x%d" % it.count
	var mode_txt := ""
	match pawn.mode:
		Pawn.Mode.SKYDIVE: mode_txt = "SKYDIVING  %dm  [Space] deploy glider" % int(pawn.height_above_ground())
		Pawn.Mode.GLIDE: mode_txt = "GLIDING  %dm" % int(pawn.height_above_ground())
		Pawn.Mode.SWIM: mode_txt = "SWIMMING"
	var build_txt := ""
	if pawn.build_mode:
		build_txt = "BUILD: %s (%s)   [Q]Wall [Z]Floor [X]Ramp [V]Cone [T]Material [1]Exit" % [["Wall", "Floor", "Ramp", "Cone"][pawn.build_kind], PieceMeshes.MAT_NAMES[pawn.build_mat]]
	var inv := ""
	for i in 5:
		var s: Dictionary = pawn.inventory[i]
		var mark := ">" if pawn.slot == i + 1 else " "
		inv += "%s%d:%s  " % [mark, i + 2, "-" if s.is_empty() else Items.display_name(s).split(" ")[-1]]
	_info.text = "%s\nWood %d   Stone %d   Metal %d\n%s%s\n%s\n%s\nFPS %d" % [
		wtxt, pawn.mats[0], pawn.mats[1], pawn.mats[2],
		(">" if pawn.slot == 0 else " "), "1:Pickaxe  " + inv, build_txt, mode_txt,
		Engine.get_frames_per_second()]
	_cross.queue_redraw()
	_bars.queue_redraw()


func _draw_cross() -> void:
	var c := _cross.size * 0.5
	if pawn.build_mode or pawn.mode != Pawn.Mode.GROUND:
		_cross.draw_circle(c, 2.5, Color.WHITE)
		return
	var spread := pawn.current_spread_deg()
	var px := tan(deg_to_rad(spread)) / tan(deg_to_rad(cam.fov * 0.5)) * _cross.size.y * 0.5
	var gap := 6.0 + px
	var col := Color(1, 1, 1, 0.95)
	for d: Vector2 in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
		_cross.draw_line(c + d * gap, c + d * (gap + 9.0), Color.BLACK, 4.0)
		_cross.draw_line(c + d * gap, c + d * (gap + 9.0), col, 2.0)
	if _hit_t > 0.0:
		var hc := Color(1.0, 0.85, 0.2) if _hit_head else Color.WHITE
		for d: Vector2 in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
			_cross.draw_line(c + d * 7.0, c + d * 14.0, hc, 2.5)


func _draw_bars() -> void:
	var s := _bars.size
	var x := 30.0
	var y := s.y - 70.0
	var w := 320.0
	_bars.draw_rect(Rect2(x, y, w, 18), Color(0, 0, 0, 0.5))
	_bars.draw_rect(Rect2(x, y, w * pawn.shield / Cfg.MAX_SHIELD, 18), Color(0.25, 0.65, 1.0))
	_bars.draw_rect(Rect2(x, y + 24, w, 22), Color(0, 0, 0, 0.5))
	_bars.draw_rect(Rect2(x, y + 24, w * pawn.health / Cfg.MAX_HEALTH, 22), Color(0.35, 0.85, 0.3))
	_bars.draw_string(ThemeDB.fallback_font, Vector2(x + w + 10, y + 15), str(int(pawn.shield)), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.6, 0.85, 1))
	_bars.draw_string(ThemeDB.fallback_font, Vector2(x + w + 10, y + 42), str(int(pawn.health)), HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color.WHITE)
	if pawn.stamina < Cfg.STAMINA_MAX:
		_bars.draw_rect(Rect2(s.x * 0.5 - 60, s.y * 0.5 + 40, 120 * pawn.stamina / Cfg.STAMINA_MAX, 4), Color(1, 1, 0.6, 0.8))
	if pawn.use_left >= 0.0:
		var f := 1.0 - pawn.use_left / pawn.use_total
		_bars.draw_rect(Rect2(s.x * 0.5 - 100, s.y * 0.5 + 60, 200, 10), Color(0, 0, 0, 0.5))
		_bars.draw_rect(Rect2(s.x * 0.5 - 100, s.y * 0.5 + 60, 200 * f, 10), Color(0.4, 0.9, 1.0))
