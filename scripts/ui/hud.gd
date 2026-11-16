class_name Hud
extends CanvasLayer
## In-match HUD. Contract used by gameplay code:
##   setup(game, pawn, cam), hit_marker(head), flash_damage(amount), set_hint(text), push_kill(text),
##   show_end(placement, kills, victory). Reads everything else from pawn / game.hud_info().
## Everything is drawn procedurally; item icons are rendered from their 3D meshes by Game.icons.

const MARGIN := 22.0
const MINI_VIEW := 520.0          # metres across the minimap on foot
const MINI_VIEW_AIR := 1100.0     # ...while skydiving / gliding
const KILLFEED_LIFE := 6.0
const PIECE_KEYS := ["Q", "Z", "X", "V"]
const PIECE_NAMES := ["WALL", "FLOOR", "RAMP", "CONE"]
const AMMO_ORDER := ["light", "medium", "heavy", "shells", "rockets"]
const AMMO_SHORT := {"light": "LIGHT", "medium": "MEDIUM", "heavy": "HEAVY", "shells": "SHELLS", "rockets": "ROCKETS"}

var game: Match
var pawn: Pawn
var cam: Camera3D
var hint := ""
var damage_flash := 0.0

var _info := {}
var _hit_t := 0.0
var _hit_head := false
var _kills: Array = []            # [text, age]
var _elim_popup := 0.0
var _last_kills := 0
var _map_open := false
var _ended := false
var _mini_zoom := MINI_VIEW
var _t := 0.0
var _map_tex: ImageTexture

var _main: Control
var _mini_frame: Panel
var _mini: Control
var _mini_border: Panel
var _map: Control
var _map_view: Control
var _vignette: TextureRect
var _storm_vignette: TextureRect
var _storm_tint: ColorRect
var _end: Control


func setup(g: Match, p: Pawn, c: Camera3D) -> void:
	game = g
	pawn = p
	cam = c
	layer = 5
	_last_kills = pawn.kills
	if game.terrain != null and game.terrain.minimap_image != null:
		_map_tex = ImageTexture.create_from_image(game.terrain.minimap_image)
	_build()


func hit_marker(head: bool) -> void:
	_hit_t = 0.22
	_hit_head = head


func flash_damage(amount: float) -> void:
	damage_flash = clampf(maxf(damage_flash, 0.3 + amount / 80.0), 0.0, 1.0)


func set_hint(t: String) -> void:
	hint = t


func push_kill(text: String) -> void:
	_kills.append([text, 0.0])
	if _kills.size() > 6:
		_kills.pop_front()


func show_end(placement: int, kills: int, victory: bool) -> void:
	if _ended:
		return
	_ended = true
	_map_open = false
	if _map:
		_map.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if victory:
		Sfx.play("victory")
	_end = _build_end(placement, kills, victory)
	add_child(_end)


func is_map_open() -> bool:
	return _map_open


# ------------------------------------------------------------------ build

func _full(c: Control) -> Control:
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


static func _radial(col: Color, inner: float) -> GradientTexture2D:
	var g := Gradient.new()
	g.set_color(0, Color(col, 0.0))
	g.set_offset(0, inner)
	g.set_color(1, col)
	g.set_offset(1, 1.0)
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 256
	t.height = 256
	return t


func _build() -> void:
	_storm_tint = _full(ColorRect.new())
	_storm_tint.color = Color(UiStyle.STORM, 0.0)
	add_child(_storm_tint)
	_storm_vignette = _full(TextureRect.new())
	_storm_vignette.texture = _radial(Color(0.45, 0.15, 0.85, 0.8), 0.55)
	_storm_vignette.stretch_mode = TextureRect.STRETCH_SCALE
	_storm_vignette.modulate.a = 0.0
	add_child(_storm_vignette)
	_vignette = _full(TextureRect.new())
	_vignette.texture = _radial(Color(0.85, 0.02, 0.02, 0.7), 0.68)
	_vignette.stretch_mode = TextureRect.STRETCH_SCALE
	_vignette.modulate.a = 0.0
	add_child(_vignette)
	_main = _full(Control.new())
	_main.draw.connect(_draw_main)
	add_child(_main)
	# minimap: rounded panel that clips its child map drawing
	_mini_frame = Panel.new()
	_mini_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mini_frame.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	_mini_frame.add_theme_stylebox_override("panel", UiStyle.box(Color(0.15, 0.35, 0.6), 18))
	add_child(_mini_frame)
	_mini = _full(Control.new())
	_mini.draw.connect(_draw_minimap)
	_mini_frame.add_child(_mini)
	_mini_border = Panel.new()
	_mini_border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bsb := UiStyle.box(Color(0, 0, 0, 0), 18, 3, Color(1, 1, 1, 0.9))
	bsb.draw_center = false
	_mini_border.add_theme_stylebox_override("panel", bsb)
	add_child(_mini_border)
	# full map overlay
	_map = _full(Control.new())
	_map.visible = false
	_map.draw.connect(_draw_map_backdrop)
	add_child(_map)
	_map_view = Control.new()
	_map_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_map_view.clip_contents = true
	_map_view.draw.connect(_draw_map)
	_map.add_child(_map_view)


func _input(event: InputEvent) -> void:
	if _ended:
		return
	if event.is_action_pressed("map") and not event.is_echo():
		_map_open = not _map_open
		_map.visible = _map_open
		Sfx.play("ui")


# ------------------------------------------------------------------ update

func _process(delta: float) -> void:
	if pawn == null or not is_instance_valid(pawn):
		return
	_t += delta
	if game != null and is_instance_valid(game):
		_info = game.hud_info()
	_hit_t = maxf(0.0, _hit_t - delta)
	damage_flash = maxf(0.0, damage_flash - delta * 1.6)
	_elim_popup = maxf(0.0, _elim_popup - delta)
	if pawn.kills > _last_kills:
		_elim_popup = 2.2
	_last_kills = pawn.kills
	for k: Array in _kills:
		k[1] += delta
	while not _kills.is_empty() and _kills[0][1] > KILLFEED_LIFE:
		_kills.pop_front()
	var low := 0.0
	if pawn.is_alive() and pawn.health < 30.0:
		low = (0.22 + 0.12 * sin(_t * 5.0)) * (1.0 - pawn.health / 30.0)
	_vignette.modulate.a = maxf(damage_flash, low)
	var in_storm: bool = _info.get("in_storm", false) and pawn.is_alive()
	var target := 1.0 if in_storm else 0.0
	_storm_vignette.modulate.a = lerpf(_storm_vignette.modulate.a, target, minf(1.0, delta * 4.0))
	_storm_tint.color.a = _storm_vignette.modulate.a * (0.16 + 0.04 * sin(_t * 3.0))
	var air := pawn.mode == Pawn.Mode.SKYDIVE or pawn.mode == Pawn.Mode.GLIDE or pawn.mode == Pawn.Mode.BUS
	_mini_zoom = lerpf(_mini_zoom, MINI_VIEW_AIR if air else MINI_VIEW, minf(1.0, delta * 2.0))
	_layout_minimap()
	_main.queue_redraw()
	_mini.queue_redraw()
	if _map_open:
		var s := _main.size
		var side := minf(s.y - 150.0 * _u(), s.x - 300.0 * _u())
		_map_view.position = (s - Vector2(side, side)) * 0.5 + Vector2(0, 14.0 * _u())
		_map_view.size = Vector2(side, side)
		_map.queue_redraw()
		_map_view.queue_redraw()
	if _end != null:
		_end.queue_redraw()


func _u() -> float:
	return clampf(_main.size.y / 900.0, 0.7, 1.6)


func _layout_minimap() -> void:
	var u := _u()
	var ms := 230.0 * u
	var r := Rect2(Vector2(_main.size.x - MARGIN - ms, MARGIN), Vector2(ms, ms))
	_mini_frame.position = r.position
	_mini_frame.size = r.size
	_mini_border.position = r.position
	_mini_border.size = r.size


# ------------------------------------------------------------------ main overlay

func _draw_main() -> void:
	if pawn == null or not is_instance_valid(pawn):
		return
	var u := _u()
	_draw_fps(u)
	_draw_killfeed(u)
	_draw_match_info(u)
	_draw_vitals(u)
	if pawn.build_mode:
		_draw_buildbar(u)
	else:
		_draw_hotbar(u)
	_draw_mats(u)
	_draw_ammo(u)
	_draw_weapon_readout(u)
	if not _ended and not _map_open and pawn.is_alive():
		_draw_crosshair(u)
		_draw_progress(u)
	_draw_hint(u)
	_draw_altitude(u)
	_draw_banners(u)


func _draw_fps(u: float) -> void:
	var fps := Engine.get_frames_per_second()
	var col := Color(0.5, 1.0, 0.5) if fps >= 55 else (Color(1.0, 0.85, 0.3) if fps >= 30 else Color(1.0, 0.4, 0.35))
	UiStyle.text(_main, Vector2(8, 16), "FPS %d" % fps, 13, col, HORIZONTAL_ALIGNMENT_LEFT, -1, 3, ThemeDB.fallback_font)


func _draw_killfeed(u: float) -> void:
	var y := 44.0 * u
	var fs := int(17 * u)
	for k: Array in _kills:
		var age: float = k[1]
		var a := clampf((KILLFEED_LIFE - age) / 0.6, 0.0, 1.0) * clampf(age / 0.15, 0.0, 1.0)
		var txt: String = k[0]
		var w := UiStyle.bold().get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var mine := txt.contains(pawn.display_name)
		_main.draw_rect(Rect2(MARGIN - 6, y - fs - 2, w + 16 * u + 14, fs + 10), Color(0, 0, 0, 0.45 * a))
		HudIcons.skull(_main, Rect2(MARGIN - 2, y - fs + 1, fs - 2, fs - 2), Color(1, 1, 1, a))
		UiStyle.text(_main, Vector2(MARGIN + fs + 4, y), txt, fs, Color(1.0, 0.86, 0.25, a) if mine else Color(1, 1, 1, a), HORIZONTAL_ALIGNMENT_LEFT, -1, 4)
		y += fs + 14


## Players left / kills / storm timer under the minimap.
func _draw_match_info(u: float) -> void:
	var ms := 230.0 * u
	var x0 := _main.size.x - MARGIN - ms
	var y := MARGIN + ms + 10.0 * u
	var fs := int(22 * u)
	var ic := 22.0 * u
	_main.draw_rect(Rect2(x0, y, ms, ic + 10 * u), Color(0, 0, 0, 0.45))
	HudIcons.person(_main, Rect2(x0 + 8 * u, y + 5 * u, ic, ic))
	UiStyle.text(_main, Vector2(x0 + 12 * u + ic, y + ic * 0.95), str(_info.get("alive", 0)), fs, Color.WHITE)
	var mid := x0 + ms * 0.5
	HudIcons.skull(_main, Rect2(mid + 8 * u, y + 5 * u, ic, ic))
	UiStyle.text(_main, Vector2(mid + 12 * u + ic, y + ic * 0.95), str(pawn.kills), fs, Color.WHITE)
	var label: String = _info.get("storm_label", "")
	if label != "":
		y += ic + 14 * u
		_main.draw_rect(Rect2(x0, y, ms, ic + 10 * u), Color(0.15, 0.05, 0.3, 0.55))
		HudIcons.storm(_main, Rect2(x0 + 8 * u, y + 5 * u, ic, ic))
		UiStyle.text(_main, Vector2(x0 + 14 * u + ic, y + ic * 0.9), label.to_upper(), int(17 * u), Color(0.92, 0.85, 1.0), HORIZONTAL_ALIGNMENT_LEFT, ms - ic - 20 * u)


## Slanted bar: background, fill fraction, optional segment ticks.
func _bar(r: Rect2, frac: float, col: Color, segments := 0) -> void:
	var sk := r.size.y * 0.35
	var bg := PackedVector2Array([r.position + Vector2(sk, 0), r.position + Vector2(r.size.x + sk, 0), r.end, Vector2(r.position.x, r.end.y)])
	_main.draw_colored_polygon(bg, Color(0, 0, 0, 0.55))
	frac = clampf(frac, 0.0, 1.0)
	if frac > 0.0:
		var w := r.size.x * frac
		var fill := PackedVector2Array([r.position + Vector2(sk, 0), r.position + Vector2(w + sk, 0), Vector2(r.position.x + w, r.end.y), Vector2(r.position.x, r.end.y)])
		_main.draw_polygon(fill, PackedColorArray([col.lightened(0.25), col.lightened(0.25), col.darkened(0.15), col.darkened(0.15)]))
		_main.draw_line(r.position + Vector2(sk, 1.5), r.position + Vector2(w + sk - 1, 1.5), Color(1, 1, 1, 0.45), 2.0)
	for i in range(1, segments):
		var x := r.position.x + r.size.x * i / segments
		_main.draw_line(Vector2(x + sk, r.position.y), Vector2(x, r.end.y), Color(0, 0, 0, 0.5), 2.0)
	var outline := bg.duplicate()
	outline.append(bg[0])
	_main.draw_polyline(outline, Color(0, 0, 0, 0.8), 1.5)


func _draw_vitals(u: float) -> void:
	var s := _main.size
	var x := MARGIN
	var bw := 300.0 * u
	var hh := 26.0 * u
	var sh := 18.0 * u
	var hy := s.y - MARGIN - hh
	var sy := hy - 8.0 * u - sh
	var bx := x + 40.0 * u
	HudIcons.health(_main, Rect2(x, hy - 2 * u, 30 * u, 30 * u))
	HudIcons.shield(_main, Rect2(x + 2 * u, sy - 3 * u, 26 * u, 26 * u))
	_bar(Rect2(bx, hy, bw, hh), pawn.health / Cfg.MAX_HEALTH, UiStyle.HEALTH)
	_bar(Rect2(bx, sy, bw, sh), pawn.shield / Cfg.MAX_SHIELD, UiStyle.SHIELD, 4)
	var tx := bx + bw + 18.0 * u
	UiStyle.text(_main, Vector2(tx, hy + hh * 0.9), str(ceili(pawn.health)), int(28 * u), Color.WHITE)
	UiStyle.text(_main, Vector2(tx + 50 * u, hy + hh * 0.9), "/ %d" % int(Cfg.MAX_HEALTH), int(16 * u), Color(1, 1, 1, 0.65))
	UiStyle.text(_main, Vector2(tx, sy + sh * 0.95), str(ceili(pawn.shield)), int(22 * u), Color(0.75, 0.9, 1.0))
	if pawn.stamina < Cfg.STAMINA_MAX - 0.5:
		var st := Rect2(bx, sy - 12.0 * u, bw * 0.6, 6.0 * u)
		_main.draw_rect(st, Color(0, 0, 0, 0.5))
		_main.draw_rect(Rect2(st.position, Vector2(st.size.x * pawn.stamina / Cfg.STAMINA_MAX, st.size.y)), Color(1.0, 0.9, 0.35))


func _hotbar_geom(u: float, count: int) -> Array:
	var b := 68.0 * u
	var gap := 6.0 * u
	var total := count * b + (count - 1) * gap
	var x0 := _main.size.x - MARGIN - total
	var y0 := _main.size.y - MARGIN - b
	return [x0, y0, b, gap]


func _slot_bg(r: Rect2, col: Color, selected: bool, u: float) -> void:
	var top := col.lightened(0.05)
	var bot := col.darkened(0.55)
	var pts := PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])
	_main.draw_polygon(pts, PackedColorArray([top, top, bot, bot]))
	# soft glossy band
	_main.draw_rect(Rect2(r.position, Vector2(r.size.x, r.size.y * 0.35)), Color(1, 1, 1, 0.1))
	if selected:
		_main.draw_rect(r.grow(1.5 * u), Color.WHITE, false, 3.0 * u)
	else:
		_main.draw_rect(r, Color(0, 0, 0, 0.7), false, 1.5)


func _draw_hotbar(u: float) -> void:
	var g := _hotbar_geom(u, 6)
	var x0: float = g[0]
	var y0: float = g[1]
	var b: float = g[2]
	var gap: float = g[3]
	for i in 6:
		var sel := pawn.slot == i
		var r := Rect2(x0 + i * (b + gap), y0, b, b)
		if sel:
			r = Rect2(r.position + Vector2(-4 * u, -14 * u), r.size + Vector2(8 * u, 8 * u))
		var it: Dictionary = {} if i == 0 else pawn.inventory[i - 1]
		var col := Color(0.2, 0.28, 0.42, 0.85)
		var tex: Texture2D = null
		var label := ""
		if i == 0:
			col = Color(0.32, 0.4, 0.55, 0.9)
			tex = Game.icons.get_icon("pickaxe", pawn.skin % 3)
			label = "Pickaxe"
		elif not it.is_empty():
			col = Cfg.RARITY_COLORS[clampi(int(it.rarity), 0, 4)]
			tex = Game.icons.get_icon(it.id, it.rarity)
			label = Items.display_name(it)
		_slot_bg(r, col, sel, u)
		if tex != null:
			_main.draw_texture_rect(tex, r.grow(-3 * u), false)
		elif label != "":
			UiStyle.text(_main, Vector2(r.position.x + 4, r.get_center().y + 6), label.split(" ")[-1].to_upper(), int(13 * u), Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, r.size.x - 8, 3)
		UiStyle.text(_main, r.position + Vector2(5 * u, 15 * u), str(i + 1), int(14 * u), Color(1, 1, 1, 0.9), HORIZONTAL_ALIGNMENT_LEFT, -1, 3)
		if not it.is_empty():
			var n := ""
			if Items.is_weapon(it):
				n = str(it.ammo)
			else:
				n = "x%d" % int(it.get("count", 1))
			UiStyle.text(_main, Vector2(r.position.x, r.end.y - 5 * u), n, int(16 * u), Color.WHITE, HORIZONTAL_ALIGNMENT_RIGHT, r.size.x - 5 * u, 4)
		if sel and pawn.reload_left >= 0.0 and Items.is_weapon(it):
			var f := 1.0 - pawn.reload_left / maxf(Items.reload_time(it), 0.01)
			_main.draw_rect(Rect2(r.position.x, r.end.y - 5 * u, r.size.x * f, 5 * u), Color(1, 1, 1, 0.85))


func _draw_buildbar(u: float) -> void:
	var g := _hotbar_geom(u, 5)
	var x0: float = g[0]
	var y0: float = g[1]
	var b: float = g[2]
	var gap: float = g[3]
	for i in 5:
		var r := Rect2(x0 + i * (b + gap), y0, b, b)
		if i < 4:
			var sel := pawn.build_kind == i
			if sel:
				r = Rect2(r.position + Vector2(-4 * u, -14 * u), r.size + Vector2(8 * u, 8 * u))
			_slot_bg(r, Color(0.2, 0.55, 1.0, 0.95) if sel else Color(0.12, 0.22, 0.45, 0.85), sel, u)
			HudIcons.piece(_main, i, r.grow(-10 * u), Color(0.92, 0.96, 1.0) if sel else Color(0.65, 0.75, 0.9))
			UiStyle.text(_main, r.position + Vector2(5 * u, 16 * u), PIECE_KEYS[i], int(16 * u), UiStyle.YELLOW if sel else Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT, -1, 4)
			UiStyle.text(_main, Vector2(r.position.x, r.end.y - 4 * u), PIECE_NAMES[i], int(11 * u), Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 3)
		else:
			_slot_bg(r, Color(0.35, 0.3, 0.12, 0.9), false, u)
			HudIcons.material(_main, pawn.build_mat, r.grow(-8 * u))
			UiStyle.text(_main, r.position + Vector2(5 * u, 16 * u), "T", int(16 * u), Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT, -1, 4)
			UiStyle.text(_main, Vector2(r.position.x, r.end.y - 4 * u), PieceMeshes.MAT_NAMES[pawn.build_mat].to_upper(), int(11 * u), Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 3)
	UiStyle.text(_main, Vector2(x0, y0 - 24 * u), "BUILD MODE", int(18 * u), UiStyle.YELLOW, HORIZONTAL_ALIGNMENT_LEFT, -1, 5)


func _mats_rect(u: float) -> Rect2:
	var w := 132.0 * u
	var rh := 40.0 * u
	var y0 := _main.size.y - MARGIN - 68.0 * u - 50.0 * u - 3 * (rh + 4 * u)
	return Rect2(_main.size.x - MARGIN - w, y0, w, rh)


func _draw_mats(u: float) -> void:
	var r0 := _mats_rect(u)
	for i in 3:
		var r := Rect2(r0.position + Vector2(0, i * (r0.size.y + 4 * u)), r0.size)
		var active := pawn.build_mode and pawn.build_mat == i
		_main.draw_rect(r, Color(0.9, 0.7, 0.1, 0.55) if active else Color(0, 0, 0, 0.45))
		if active:
			_main.draw_rect(r, UiStyle.YELLOW, false, 2.5 * u)
		var dim := pawn.build_mode and not active
		HudIcons.material(_main, i, Rect2(r.position + Vector2(4 * u, 0), Vector2(r.size.y, r.size.y)), dim)
		var col := Color.WHITE if pawn.mats[i] > 0 else Color(1, 1, 1, 0.45)
		UiStyle.text(_main, Vector2(r.position.x, r.end.y - 10 * u), str(pawn.mats[i]), int(24 * u), col, HORIZONTAL_ALIGNMENT_RIGHT, r.size.x - 10 * u)


## Reserve ammo for every type, current weapon's type highlighted.
func _draw_ammo(u: float) -> void:
	var m := _mats_rect(u)
	var w := 150.0 * u
	var rh := 24.0 * u
	var x := m.position.x - 10.0 * u - w
	var bottom := m.position.y + 3 * (m.size.y + 4 * u) - 4 * u
	var cur := ""
	var it := pawn.current_weapon()
	if not it.is_empty():
		cur = Items.WEAPONS[it.id].ammo
	for i in AMMO_ORDER.size():
		var t: String = AMMO_ORDER[i]
		var y := bottom - (AMMO_ORDER.size() - i) * (rh + 2 * u)
		var r := Rect2(x, y, w, rh)
		var hi := t == cur
		_main.draw_rect(r, Color(1, 1, 1, 0.22) if hi else Color(0, 0, 0, 0.35))
		var ac: Color = Items.AMMO[t].color
		HudIcons.bullet(_main, Rect2(r.position + Vector2(3 * u, 1 * u), Vector2(rh - 2 * u, rh - 2 * u)), ac)
		var a := 1.0 if (hi or pawn.ammo[t] > 0) else 0.45
		UiStyle.text(_main, Vector2(r.position.x + rh + 4 * u, r.end.y - 6 * u), AMMO_SHORT[t], int(13 * u), Color(1, 1, 1, a), HORIZONTAL_ALIGNMENT_LEFT, -1, 3)
		UiStyle.text(_main, Vector2(r.position.x, r.end.y - 5 * u), str(pawn.ammo[t]), int(17 * u), Color(UiStyle.YELLOW, a) if hi else Color(1, 1, 1, a), HORIZONTAL_ALIGNMENT_RIGHT, w - 6 * u, 3)


## Selected item name + big "mag / reserve" readout left of the hotbar.
func _draw_weapon_readout(u: float) -> void:
	if pawn.build_mode:
		return
	var g := _hotbar_geom(u, 6)
	var right: float = g[0] - 18.0 * u
	var base := _main.size.y - MARGIN - 8.0 * u
	var it := pawn.current_item()
	if it.is_empty():
		UiStyle.text(_main, Vector2(right - 300 * u, base), "HARVESTING TOOL", int(18 * u), Color(0.85, 0.9, 1.0), HORIZONTAL_ALIGNMENT_RIGHT, 300 * u, 4)
		return
	var rc: Color = Cfg.RARITY_COLORS[clampi(int(it.rarity), 0, 4)]
	var title: String = (Cfg.RARITY_NAMES[clampi(int(it.rarity), 0, 4)] + " " + Items.display_name(it)).to_upper()
	if Items.is_weapon(it):
		var w: Dictionary = Items.WEAPONS[it.id]
		var reserve: int = pawn.ammo[w.ammo]
		var big := int(44 * u)
		var rtxt := "/ %d" % reserve
		var rw := UiStyle.bold().get_string_size(rtxt, HORIZONTAL_ALIGNMENT_LEFT, -1, int(22 * u)).x
		UiStyle.text(_main, Vector2(right - rw, base), rtxt, int(22 * u), Color(1, 1, 1, 0.75), HORIZONTAL_ALIGNMENT_LEFT, -1, 4)
		var mag_col := Color.WHITE if int(it.ammo) > int(w.mag) / 4 else Color(1.0, 0.45, 0.35)
		UiStyle.text(_main, Vector2(right - rw - 220 * u, base), str(it.ammo), big, mag_col, HORIZONTAL_ALIGNMENT_RIGHT, 212 * u, 6)
		if pawn.reload_left >= 0.0:
			UiStyle.text(_main, Vector2(right - 300 * u, base - big - 26 * u), "RELOADING...", int(16 * u), UiStyle.YELLOW, HORIZONTAL_ALIGNMENT_RIGHT, 300 * u, 4)
		UiStyle.text(_main, Vector2(right - 400 * u, base - big - 4 * u), title, int(18 * u), rc.lightened(0.2), HORIZONTAL_ALIGNMENT_RIGHT, 400 * u, 5)
	else:
		UiStyle.text(_main, Vector2(right - 400 * u, base - 30 * u), title, int(18 * u), rc.lightened(0.2), HORIZONTAL_ALIGNMENT_RIGHT, 400 * u, 5)
		UiStyle.text(_main, Vector2(right - 300 * u, base), "x%d" % int(it.get("count", 1)), int(32 * u), Color.WHITE, HORIZONTAL_ALIGNMENT_RIGHT, 300 * u, 5)


func _draw_crosshair(u: float) -> void:
	var c := (_main.size * 0.5).round()
	var air := pawn.mode != Pawn.Mode.GROUND
	if pawn.build_mode or air:
		_main.draw_circle(c, 3.5, Color(0, 0, 0, 0.7))
		_main.draw_circle(c, 2.2, Color.WHITE)
		if pawn.build_mode:
			_main.draw_arc(c, 10.0, 0, TAU, 20, Color(1, 1, 1, 0.5), 1.5, true)
	else:
		var spread := pawn.current_spread_deg()
		var fov := cam.fov if cam != null else 80.0
		var px := tan(deg_to_rad(spread)) / tan(deg_to_rad(fov * 0.5)) * _main.size.y * 0.5
		var gap := 5.0 + px
		var ln := 10.0
		for d: Vector2 in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
			_main.draw_line(c + d * (gap - 1), c + d * (gap + ln + 1), Color(0, 0, 0, 0.75), 4.0)
			_main.draw_line(c + d * gap, c + d * (gap + ln), Color.WHITE, 2.0)
		if pawn.current_weapon().is_empty():
			_main.draw_circle(c, 2.0, Color.WHITE)
	if _hit_t > 0.0:
		var hc := Color(1.0, 0.82, 0.15) if _hit_head else Color.WHITE
		var k := 1.0 + (_hit_t / 0.22) * 0.4
		for d: Vector2 in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
			var dn := d.normalized()
			_main.draw_line(c + dn * 8.0 * k, c + dn * 17.0 * k, Color(0, 0, 0, 0.6), 4.5)
			_main.draw_line(c + dn * 8.0 * k, c + dn * 17.0 * k, hc, 2.5)


## Reload ring around the crosshair, consumable use bar below it.
func _draw_progress(u: float) -> void:
	var c := _main.size * 0.5
	if pawn.reload_left >= 0.0:
		var it := pawn.current_weapon()
		if not it.is_empty():
			var f := clampf(1.0 - pawn.reload_left / maxf(Items.reload_time(it), 0.01), 0.0, 1.0)
			_main.draw_arc(c, 30 * u, 0, TAU, 40, Color(0, 0, 0, 0.35), 5 * u, true)
			_main.draw_arc(c, 30 * u, -PI * 0.5, -PI * 0.5 + TAU * f, 40, Color.WHITE, 4 * u, true)
	if pawn.use_left >= 0.0:
		var it := pawn.current_item()
		var f := clampf(1.0 - pawn.use_left / maxf(pawn.use_total, 0.01), 0.0, 1.0)
		var w := 260.0 * u
		var r := Rect2(c.x - w * 0.5, c.y + 80 * u, w, 14 * u)
		var nm := Items.display_name(it).to_upper() if not it.is_empty() else "USING"
		UiStyle.text(_main, Vector2(r.position.x, r.position.y - 8 * u), nm, int(18 * u), Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT, -1, 4)
		UiStyle.text(_main, Vector2(r.position.x, r.position.y - 8 * u), "%.1f" % pawn.use_left, int(18 * u), UiStyle.YELLOW, HORIZONTAL_ALIGNMENT_RIGHT, w, 4)
		_main.draw_rect(r, Color(0, 0, 0, 0.55))
		_main.draw_rect(Rect2(r.position, Vector2(w * f, r.size.y)), Color(0.45, 0.85, 1.0) if not it.is_empty() and Items.CONSUMABLES.get(it.id, {}).get("stat", "") == "shield" else UiStyle.HEALTH)
		_main.draw_rect(r, Color(1, 1, 1, 0.8), false, 1.5)


func _draw_hint(u: float) -> void:
	var t := hint
	if t == "" and pawn.mode == Pawn.Mode.BUS:
		t = "[SPACE]  JUMP FROM THE BUS"
	elif t == "" and pawn.mode == Pawn.Mode.SKYDIVE and pawn.height_above_ground() > 15.0:
		t = "[SPACE]  DEPLOY GLIDER"
	if t == "" or _ended:
		return
	var fs := int(20 * u)
	var w := UiStyle.bold().get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var c := Vector2(_main.size.x * 0.5, _main.size.y * 0.74)
	var r := Rect2(c.x - w * 0.5 - 16 * u, c.y - fs - 6 * u, w + 32 * u, fs + 18 * u)
	_main.draw_style_box(UiStyle.box(Color(0, 0, 0, 0.55), 6), r)
	UiStyle.text(_main, Vector2(c.x - w * 0.5, c.y + 2 * u), t, fs, Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT, -1, 4)


## Altitude gauge on the right while dropping.
func _draw_altitude(u: float) -> void:
	if pawn.mode != Pawn.Mode.SKYDIVE and pawn.mode != Pawn.Mode.GLIDE:
		return
	var h := pawn.height_above_ground()
	var x := _main.size.x - MARGIN - 300 * u
	var top := _main.size.y * 0.32
	var bot := _main.size.y * 0.62
	_main.draw_line(Vector2(x, top), Vector2(x, bot), Color(1, 1, 1, 0.6), 3 * u)
	for i in 6:
		var y := lerpf(bot, top, i / 5.0)
		_main.draw_line(Vector2(x - 6 * u, y), Vector2(x + 6 * u, y), Color(1, 1, 1, 0.6), 2)
	var f := clampf(h / Cfg.BUS_HEIGHT, 0.0, 1.0)
	var y := lerpf(bot, top, f)
	var tri := PackedVector2Array([Vector2(x - 8 * u, y), Vector2(x - 20 * u, y - 8 * u), Vector2(x - 20 * u, y + 8 * u)])
	_main.draw_colored_polygon(tri, UiStyle.YELLOW)
	UiStyle.text(_main, Vector2(x + 12 * u, y + 8 * u), "%d m" % int(h), int(22 * u), Color.WHITE)
	var deploy := lerpf(bot, top, clampf(Cfg.AUTO_DEPLOY / Cfg.BUS_HEIGHT, 0.0, 1.0))
	_main.draw_line(Vector2(x - 10 * u, deploy), Vector2(x + 10 * u, deploy), Color(0.4, 0.8, 1.0), 3 * u)


func _draw_banners(u: float) -> void:
	var cx := _main.size.x * 0.5
	if _info.get("in_storm", false) and pawn.is_alive() and not _ended:
		var a := 0.75 + 0.25 * sin(_t * 6.0)
		UiStyle.text(_main, Vector2(cx - 300 * u, 120 * u), "YOU ARE IN THE STORM!", int(30 * u), Color(0.9, 0.75, 1.0, a), HORIZONTAL_ALIGNMENT_CENTER, 600 * u, 8, UiStyle.heavy())
	if _elim_popup > 0.0:
		var a := clampf(_elim_popup / 0.4, 0.0, 1.0)
		var pop := 1.0 + maxf(0.0, _elim_popup - 1.9) * 1.5
		_main.draw_set_transform(Vector2(cx, _main.size.y * 0.5 + 200 * u), 0.0, Vector2.ONE * pop)
		UiStyle.text(_main, Vector2(-300 * u, 0), "ELIMINATION", int(30 * u), Color(1.0, 0.35, 0.3, a), HORIZONTAL_ALIGNMENT_CENTER, 600 * u, 8, UiStyle.heavy())
		UiStyle.text(_main, Vector2(-300 * u, 28 * u), "%d ELIMINATIONS" % pawn.kills, int(18 * u), Color(1, 1, 1, a), HORIZONTAL_ALIGNMENT_CENTER, 600 * u, 5)
		_main.draw_set_transform(Vector2.ZERO)
	if pawn.mode == Pawn.Mode.BUS and not _map_open:
		UiStyle.text(_main, Vector2(cx - 300 * u, 110 * u), "THE BATTLE BUS", int(30 * u), Color(0.6, 0.85, 1.0), HORIZONTAL_ALIGNMENT_CENTER, 600 * u, 8, UiStyle.heavy())


# ------------------------------------------------------------------ minimap

func _draw_minimap() -> void:
	var s := _mini.size
	if s.x <= 1.0 or pawn == null or not is_instance_valid(pawn):
		return
	var u := _u()
	var p := Vector2(pawn.global_position.x, pawn.global_position.z)
	var view := _mini_zoom
	var k := s.x / view
	var to_mini := func(w: Vector2) -> Vector2: return (w - p) * k + s * 0.5
	_mini.draw_rect(Rect2(Vector2.ZERO, s), Color(0.22, 0.55, 0.85))
	if _map_tex != null:
		var img_px := _map_tex.get_size().x
		var px_per_m := img_px / (Cfg.MAP_SIZE * 1.2)
		var cuv: Vector2 = Terrain.world_to_map_uv(p) * img_px
		var half := view * 0.5 * px_per_m
		_mini.draw_texture_rect_region(_map_tex, Rect2(Vector2.ZERO, s), Rect2(cuv - Vector2(half, half), Vector2(half, half) * 2.0))
	_draw_storm_circles(_mini, to_mini, k, s.length(), 1.0)
	# bus route
	var bus: Array = _info.get("bus_path", [])
	if bus.size() >= 2:
		_mini.draw_line(to_mini.call(bus[0]), to_mini.call(bus[1]), Color(1, 1, 1, 0.8), 2.0 * u)
	# POI names when close
	for poi: Dictionary in Terrain.POIS:
		var d: float = (poi.pos as Vector2).distance_to(p)
		if d < view * 0.75:
			var at: Vector2 = to_mini.call(poi.pos)
			UiStyle.text(_mini, at + Vector2(-100, 0), String(poi.name).to_upper(), int(12 * u), Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, 200, 4)
	# dotted path to the safe zone when outside it
	var nc: Vector2 = _info.get("next_center", Vector2.ZERO)
	var nr: float = _info.get("next_radius", 99999.0)
	if nr < 5000.0 and p.distance_to(nc) > nr:
		var target := nc + (p - nc).normalized() * nr
		var a: Vector2 = to_mini.call(p)
		var b: Vector2 = to_mini.call(target)
		var n := int(a.distance_to(b) / (8.0 * u))
		for i in range(1, mini(n, 60), 2):
			_mini.draw_line(a.lerp(b, float(i) / n), a.lerp(b, float(i + 1) / n), Color.WHITE, 2.0 * u)
	_player_arrow(_mini, s * 0.5, 9.0 * u)
	UiStyle.text(_mini, Vector2(0, 18 * u), "N", int(16 * u), Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, s.x, 4)


## Storm drawing shared by minimap and full map. `to_px` maps world xz -> canvas.
func _draw_storm_circles(ci: CanvasItem, to_px: Callable, k: float, cover: float, thick: float) -> void:
	var sc: Vector2 = _info.get("storm_center", Vector2.ZERO)
	var sr: float = _info.get("storm_radius", 99999.0)
	var nc: Vector2 = _info.get("next_center", Vector2.ZERO)
	var nr: float = _info.get("next_radius", 99999.0)
	if sr < 5000.0:
		var c: Vector2 = to_px.call(sc)
		var rp := sr * k
		# thick ring outward from the storm edge = tinted "outside" region
		var w := cover * 2.0 + c.length()
		ci.draw_arc(c, rp + w * 0.5, 0, TAU, 96, Color(0.45, 0.2, 0.9, 0.42), w)
		ci.draw_arc(c, rp, 0, TAU, 96, Color(0.75, 0.5, 1.0, 0.95), 2.5 * thick, true)
	if nr < 5000.0:
		ci.draw_arc(to_px.call(nc), nr * k, 0, TAU, 96, Color(1, 1, 1, 0.95), 2.0 * thick, true)


func _player_arrow(ci: CanvasItem, at: Vector2, r: float) -> void:
	var fwd := Vector2(-sin(pawn.yaw), -cos(pawn.yaw))
	var side := Vector2(-fwd.y, fwd.x)
	var pts := PackedVector2Array([at + fwd * r * 1.3, at - fwd * r * 0.7 + side * r * 0.9, at - fwd * r * 0.25, at - fwd * r * 0.7 - side * r * 0.9])
	ci.draw_colored_polygon(pts, UiStyle.YELLOW)
	var o := pts.duplicate()
	o.append(pts[0])
	ci.draw_polyline(o, Color.BLACK, 1.5, true)


# ------------------------------------------------------------------ full map

func _draw_map_backdrop() -> void:
	var s := _map.size
	var u := _u()
	_map.draw_rect(Rect2(Vector2.ZERO, s), Color(0.02, 0.05, 0.16, 0.82))
	var r := Rect2(_map_view.position, _map_view.size)
	_map.draw_rect(r.grow(4 * u), Color(1, 1, 1, 0.9), false, 3 * u)
	UiStyle.text(_map, Vector2(0, r.position.y - 22 * u), "MAP", int(36 * u), Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, s.x, 8, UiStyle.heavy())
	var label: String = _info.get("storm_label", "")
	if label != "":
		UiStyle.text(_map, Vector2(r.end.x + 24 * u, r.position.y + 30 * u), label.to_upper(), int(20 * u), Color(0.9, 0.8, 1.0), HORIZONTAL_ALIGNMENT_LEFT, -1, 5)
	UiStyle.text(_map, Vector2(r.end.x + 24 * u, r.position.y + 62 * u), "%d PLAYERS LEFT" % int(_info.get("alive", 0)), int(20 * u), Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT, -1, 5)
	UiStyle.text(_map, Vector2(r.end.x + 24 * u, r.end.y), "[M] CLOSE", int(16 * u), Color(1, 1, 1, 0.7), HORIZONTAL_ALIGNMENT_LEFT, -1, 4)
	# legend
	var ly := r.position.y + 110 * u
	_map.draw_arc(Vector2(r.end.x + 36 * u, ly), 10 * u, 0, TAU, 20, Color.WHITE, 2.0)
	UiStyle.text(_map, Vector2(r.end.x + 54 * u, ly + 6 * u), "NEXT SAFE ZONE", int(14 * u), Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT, -1, 3)
	_map.draw_rect(Rect2(r.end.x + 26 * u, ly + 20 * u, 20 * u, 14 * u), Color(0.45, 0.2, 0.9, 0.8))
	UiStyle.text(_map, Vector2(r.end.x + 54 * u, ly + 33 * u), "STORM", int(14 * u), Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT, -1, 3)


func _draw_map() -> void:
	var side := _map_view.size.x
	if side <= 1.0 or pawn == null or not is_instance_valid(pawn):
		return
	var u := _u()
	var span := Cfg.MAP_SIZE * 1.2
	var k := side / span
	var to_px := func(w: Vector2) -> Vector2: return Terrain.world_to_map_uv(w) * side
	_map_view.draw_rect(Rect2(Vector2.ZERO, Vector2(side, side)), Color(0.22, 0.55, 0.85))
	if _map_tex != null:
		_map_view.draw_texture_rect(_map_tex, Rect2(Vector2.ZERO, Vector2(side, side)), false)
	# grid A..J / 1..10
	for i in range(1, 10):
		var x := side * i / 10.0
		_map_view.draw_line(Vector2(x, 0), Vector2(x, side), Color(1, 1, 1, 0.15), 1.0)
		_map_view.draw_line(Vector2(0, x), Vector2(side, x), Color(1, 1, 1, 0.15), 1.0)
	for i in 10:
		UiStyle.text(_map_view, Vector2(side * (i + 0.5) / 10.0 - 10, 18 * u), "ABCDEFGHIJ"[i], int(14 * u), Color(1, 1, 1, 0.6), HORIZONTAL_ALIGNMENT_CENTER, 20, 3)
		UiStyle.text(_map_view, Vector2(6 * u, side * (i + 0.5) / 10.0 + 6), str(i + 1), int(14 * u), Color(1, 1, 1, 0.6), HORIZONTAL_ALIGNMENT_LEFT, -1, 3)
	_draw_storm_circles(_map_view, to_px, k, side * 1.5, 1.4)
	var bus: Array = _info.get("bus_path", [])
	if bus.size() >= 2:
		var a: Vector2 = to_px.call(bus[0])
		var b: Vector2 = to_px.call(bus[1])
		_map_view.draw_line(a, b, Color(1, 1, 1, 0.9), 3 * u)
		var dir := (b - a).normalized()
		var side_v := Vector2(-dir.y, dir.x)
		for t: float in [0.25, 0.5, 0.75]:
			var m := a.lerp(b, t)
			_map_view.draw_colored_polygon(PackedVector2Array([m + dir * 10 * u, m - dir * 6 * u + side_v * 7 * u, m - dir * 6 * u - side_v * 7 * u]), Color.WHITE)
		UiStyle.text(_map_view, b + Vector2(-60, -10 * u), "BUS ROUTE", int(14 * u), Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, 120, 4)
	for poi: Dictionary in Terrain.POIS:
		var at: Vector2 = to_px.call(poi.pos)
		_map_view.draw_circle(at, 3 * u, Color.WHITE)
		UiStyle.text(_map_view, at + Vector2(-110, -8 * u), String(poi.name).to_upper(), int(15 * u), Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, 220, 5)
	var pp: Vector2 = to_px.call(Vector2(pawn.global_position.x, pawn.global_position.z))
	_map_view.draw_circle(pp, 14 * u, Color(1.0, 0.86, 0.12, 0.25 + 0.15 * sin(_t * 5.0)))
	_player_arrow(_map_view, pp, 10.0 * u)


# ------------------------------------------------------------------ end screen

func _build_end(placement: int, kills: int, victory: bool) -> Control:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	var t0 := _t
	root.draw.connect(func() -> void:
		var s := root.size
		var u := _u()
		var a := clampf((_t - t0) / 0.5, 0.0, 1.0)
		root.draw_polygon(PackedVector2Array([Vector2.ZERO, Vector2(s.x, 0), s, Vector2(0, s.y)]),
			PackedColorArray([Color(0, 0, 0, 0.25 * a), Color(0, 0, 0, 0.25 * a), Color(0, 0, 0, 0.8 * a), Color(0, 0, 0, 0.8 * a)]))
		var cy := s.y * 0.36
		if victory:
			# light burst behind the title
			for i in 16:
				var ang := _t * 0.2 + i * TAU / 16.0
				var r := s.length()
				root.draw_colored_polygon(PackedVector2Array([Vector2(s.x * 0.5, cy), Vector2(s.x * 0.5, cy) + Vector2(cos(ang), sin(ang)) * r, Vector2(s.x * 0.5, cy) + Vector2(cos(ang + 0.1), sin(ang + 0.1)) * r]), Color(1.0, 0.85, 0.3, 0.12 * a))
		var pop := 1.0 + (1.0 - a) * 0.6
		root.draw_set_transform(Vector2(s.x * 0.5, cy), 0.0, Vector2.ONE * pop)
		var font := UiStyle.heavy()
		var big := int(130 * u)
		var title := "#1 VICTORY!" if victory else "ELIMINATED"
		var col := Color(1.0, 0.82, 0.18, a) if victory else Color(1.0, 0.3, 0.28, a)
		var w := font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, big).x
		for d in 5:
			root.draw_string(font, Vector2(-w * 0.5 + d * 2, big * 0.35 + d * 3), title, HORIZONTAL_ALIGNMENT_LEFT, -1, big, Color(0.25, 0.1, 0.0, 0.8 * a) if victory else Color(0.15, 0.0, 0.0, 0.8 * a))
		root.draw_string_outline(font, Vector2(-w * 0.5, big * 0.35), title, HORIZONTAL_ALIGNMENT_LEFT, -1, big, int(12 * u), Color(0.3, 0.12, 0.0, a) if victory else Color(0.2, 0, 0, a))
		root.draw_string(font, Vector2(-w * 0.5, big * 0.35), title, HORIZONTAL_ALIGNMENT_LEFT, -1, big, col)
		if victory:
			root.draw_string(font, Vector2(-w * 0.5, big * 0.35 - 6 * u), title, HORIZONTAL_ALIGNMENT_LEFT, -1, big, Color(1, 1, 0.8, 0.25 * a))
		root.draw_set_transform(Vector2.ZERO)
		var sub := "VICTORY ROYALE  (TEMU EDITION)" if victory else "#%d OF 100" % placement
		UiStyle.text(root, Vector2(0, cy + 110 * u), sub, int(34 * u), Color(1, 1, 1, a), HORIZONTAL_ALIGNMENT_CENTER, s.x, 7, UiStyle.heavy())
		UiStyle.text(root, Vector2(0, cy + 165 * u), "PLACED #%d    •    %d ELIMINATIONS" % [placement, kills], int(24 * u), Color(0.85, 0.9, 1.0, a), HORIZONTAL_ALIGNMENT_CENTER, s.x, 5))
	var btn := Button.new()
	btn.text = "RETURN TO LOBBY"
	UiStyle.style_button(btn, UiStyle.YELLOW, Color(0.08, 0.06, 0.02), 30, 8)
	btn.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	btn.offset_left = -190
	btn.offset_right = 190
	btn.offset_top = -170
	btn.offset_bottom = -90
	btn.pressed.connect(func() -> void:
		Sfx.play("ui")
		Game.return_to_menu())
	root.add_child(btn)
	return root
