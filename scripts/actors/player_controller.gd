class_name PlayerController
extends Node
## Reads input, drives the player pawn, runs the over-the-shoulder camera,
## the build preview and a compact HUD.

var game: Match
var pawn: Pawn
var cam: Camera3D
var _cam_pivot := Vector3.ZERO
var _recoil := 0.0
var shake := 0.0
var damage_flash := 0.0
var _hit_t := 0.0
var _hit_head := false
var _ghost: MeshInstance3D
var _ghost_mat_ok: StandardMaterial3D
var _ghost_mat_bad: StandardMaterial3D
var _weak: MeshInstance3D
var _interact_hold := 0.0
var _fov := 80.0

# HUD
var hud: CanvasLayer
var _cross: Control
var _info: Label
var _bars: Control
var _hint: Label
var _slots: HBoxContainer
var _flash: ColorRect


func setup(g: Match, p: Pawn) -> void:
	game = g
	pawn = p
	cam = Camera3D.new()
	cam.far = 5000.0
	cam.near = 0.08
	cam.fov = _fov
	game.add_child(cam)
	cam.current = true
	_cam_pivot = pawn.global_position
	_ghost = MeshInstance3D.new()
	_ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ghost_mat_ok = StandardMaterial3D.new()
	_ghost_mat_ok.albedo_color = Color(0.35, 0.7, 1.0, 0.45)
	_ghost_mat_ok.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ghost_mat_ok.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ghost_mat_ok.cull_mode = BaseMaterial3D.CULL_DISABLED
	_ghost_mat_bad = _ghost_mat_ok.duplicate()
	_ghost_mat_bad.albedo_color = Color(1.0, 0.3, 0.3, 0.4)
	game.add_child(_ghost)
	_ghost.visible = false
	_weak = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.16
	sm.height = 0.32
	_weak.mesh = sm
	var wm := StandardMaterial3D.new()
	wm.albedo_color = Color(0.3, 0.8, 1.0)
	wm.emission_enabled = true
	wm.emission = Color(0.3, 0.8, 1.0)
	wm.emission_energy_multiplier = 2.0
	wm.no_depth_test = true
	_weak.material_override = wm
	_weak.visible = false
	game.add_child(_weak)
	_build_hud()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var sens := Cfg.mouse_sens * (Cfg.ads_sens_mult if pawn.in_aim and not pawn.build_mode else 1.0)
		if _scoped():
			sens *= 0.35
		pawn.yaw -= event.relative.x * sens
		pawn.pitch = clampf(pawn.pitch - event.relative.y * sens, -1.45, 1.45)
	elif event is InputEventMouseButton and event.pressed:
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			pawn.cycle_slot(1)
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			pawn.cycle_slot(-1)
	elif event.is_action_pressed("pause"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event.is_action_pressed("jump"):
		pawn.jump()
	elif event.is_action_pressed("reload"):
		pawn.start_reload()
	elif event.is_action_pressed("build_wall"):
		_build_key(PieceMeshes.Kind.WALL)
	elif event.is_action_pressed("build_floor"):
		_build_key(PieceMeshes.Kind.FLOOR)
	elif event.is_action_pressed("build_stair"):
		_build_key(PieceMeshes.Kind.RAMP)
	elif event.is_action_pressed("build_cone"):
		_build_key(PieceMeshes.Kind.CONE)
	elif event.is_action_pressed("build_toggle"):
		pawn.set_build_mode(not pawn.build_mode)
	elif event.is_action_pressed("cycle_mat"):
		pawn.build_mat = (pawn.build_mat + 1) % 3
	elif event.is_action_pressed("emote"):
		pawn.start_emote(randi() % 4)
	elif event.is_action_pressed("drop_item"):
		pawn.drop_current()
	else:
		for i in 6:
			if event.is_action_pressed("slot_%d" % i):
				pawn.select_slot(i)


func _build_key(kind: int) -> void:
	pawn.set_build_mode(true, kind)


func add_recoil(r: float) -> void:
	_recoil += r * 0.012
	shake = maxf(shake, 0.08 * r)


func hit_marker(head: bool) -> void:
	_hit_t = 0.18
	_hit_head = head


func show_weakspot(p: Vector3) -> void:
	_weak.global_position = p
	_weak.visible = true


func _scoped() -> bool:
	var w := pawn.current_weapon()
	return pawn.in_aim and not pawn.build_mode and not w.is_empty() and Items.WEAPONS[w.id].get("scope", false)


func _process(delta: float) -> void:
	if pawn == null:
		return
	var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	pawn.in_move = Input.get_vector("move_left", "move_right", "move_back", "move_forward") if captured else Vector2.ZERO
	pawn.in_sprint = Input.is_action_pressed("sprint")
	pawn.in_crouch = Input.is_action_pressed("crouch")
	pawn.in_aim = Input.is_action_pressed("aim") and captured
	pawn.in_fire = Input.is_action_pressed("fire") and captured
	# recoil settles back
	if _recoil > 0.0:
		var back := minf(_recoil, delta * 0.25)
		pawn.pitch += _recoil * 0.6 - back
		_recoil = 0.0
	_update_camera(delta)
	_interact(delta)
	_update_ghost()
	_update_hud(delta)
	_weak.visible = _weak.visible and pawn.slot == 0 and not pawn.build_mode


func _update_camera(delta: float) -> void:
	var gliding := pawn.mode in [Pawn.Mode.SKYDIVE, Pawn.Mode.GLIDE]
	var aiming := pawn.in_aim and not pawn.build_mode and not pawn.current_weapon().is_empty()
	var dist := 3.2
	var side := 0.75
	var height := 1.6 if not pawn.crouched else 1.15
	var target_fov := 80.0
	if aiming:
		dist = 1.7
		side = 0.6
		target_fov = float(Items.WEAPONS[pawn.current_weapon().id].ads_fov)
	if gliding:
		dist = 5.5
		side = 0.0
		height = 1.4
		target_fov = 85.0 + pawn.dive * 10.0
	if pawn._sliding:
		target_fov = 88.0
	_fov = lerpf(_fov, target_fov, clampf(delta * 14.0, 0.0, 1.0))
	cam.fov = _fov
	var focus := pawn.global_position + Vector3(0, height, 0)
	_cam_pivot = _cam_pivot.lerp(focus, clampf(delta * 25.0, 0.0, 1.0)) if _cam_pivot.distance_to(focus) < 3.0 else focus
	var basis := Basis.from_euler(Vector3(pawn.pitch, pawn.yaw, 0))
	var right := basis.x
	var back := basis.z
	var desired := _cam_pivot + right * side + back * dist
	# keep the camera out of walls
	var hit := game.combat.ray(_cam_pivot + right * side * 0.5, desired + back * 0.25, [pawn.get_rid()], Cfg.L_WORLD | Cfg.L_BUILD)
	if not hit.is_empty():
		desired = (hit.position as Vector3) - back * 0.25
	if _scoped():
		desired = pawn.eye_pos()
	var shake_off := Vector3(randf_range(-1, 1), randf_range(-1, 1), 0) * shake * 0.15
	shake = maxf(0.0, shake - delta * 2.5)
	cam.global_transform = Transform3D(basis, desired + basis * shake_off)
	pawn.aim_from = cam.global_position
	pawn.aim_dir = -basis.z
	pawn.rig.visible = not _scoped()


func _interact(delta: float) -> void:
	if pawn.mode != Pawn.Mode.GROUND:
		_hint.text = ""
		return
	# auto-collect ammo and materials
	for pk: Loot.Pickup in game.loot.pickups_near(pawn.global_position, 1.6):
		if not pk.data.has("item"):
			pawn.take_pickup(pk)
	var chest := game.loot.nearest_chest(pawn.global_position + Vector3(0, 0.5, 0), 2.6)
	var pk2 := game.loot.nearest_pickup(pawn.global_position, 2.4)
	var e_down := Input.is_action_pressed("interact")
	if chest:
		var what := "Ammo Box" if chest.ammo_box else "Chest"
		_hint.text = "[E] Search %s" % what
		if e_down:
			_interact_hold += delta
			_hint.text += "  %d%%" % int(minf(_interact_hold / 0.35, 1.0) * 100)
			if _interact_hold >= 0.35:
				game.loot.open_chest(chest)
				_interact_hold = 0.0
		else:
			_interact_hold = 0.0
	elif pk2:
		var it: Dictionary = pk2.data.item
		var r: int = it.rarity
		_hint.text = "[E] %s %s%s" % [Cfg.RARITY_NAMES[r], Items.display_name(it), (" x%d" % it.count) if it.has("count") else ""]
		if Input.is_action_just_pressed("interact"):
			pawn.take_pickup(pk2)
	else:
		_hint.text = ""
		_interact_hold = 0.0


func _update_ghost() -> void:
	if not pawn.build_mode or pawn.mode != Pawn.Mode.GROUND:
		_ghost.visible = false
		return
	var t := game.build_target(pawn)
	_ghost.visible = true
	_ghost.mesh = PieceMeshes.get_mesh(t.kind, pawn.build_mat)
	_ghost.global_transform = Structures.piece_xf(t.kind, t.cell, t.dir)
	var ok: bool = game.structures.can_place(t.kind, t.cell, t.dir) and pawn.mats[pawn.build_mat] >= Cfg.BUILD_COST
	_ghost.material_override = _ghost_mat_ok if ok else _ghost_mat_bad


# ------------------------------------------------------------------ HUD

func _build_hud() -> void:
	hud = CanvasLayer.new()
	game.add_child(hud)
	_flash = ColorRect.new()
	_flash.color = Color(1, 0, 0, 0)
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(_flash)
	_cross = Control.new()
	_cross.set_anchors_preset(Control.PRESET_FULL_RECT)
	_cross.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cross.draw.connect(_draw_cross)
	hud.add_child(_cross)
	_bars = Control.new()
	_bars.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bars.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bars.draw.connect(_draw_bars)
	hud.add_child(_bars)
	_info = Label.new()
	_info.position = Vector2(20, 16)
	_info.add_theme_font_size_override("font_size", 18)
	_info.add_theme_color_override("font_outline_color", Color.BLACK)
	_info.add_theme_constant_override("outline_size", 6)
	hud.add_child(_info)
	_hint = Label.new()
	_hint.set_anchors_preset(Control.PRESET_CENTER)
	_hint.position = Vector2(-150, 70)
	_hint.size = Vector2(300, 30)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.add_theme_font_size_override("font_size", 20)
	_hint.add_theme_color_override("font_outline_color", Color.BLACK)
	_hint.add_theme_constant_override("outline_size", 6)
	hud.add_child(_hint)


func _update_hud(delta: float) -> void:
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
