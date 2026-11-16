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
var _ghost: MeshInstance3D
var _ghost_mat_ok: StandardMaterial3D
var _ghost_mat_bad: StandardMaterial3D
var _weak: MeshInstance3D
var _interact_hold := 0.0
var _fov := 80.0

var hud: Hud
var editing: Structures.Destructible
var _edit_mask := 0
var _edit_paint := -1
var _edit_overlay: MeshInstance3D
var _ended := false


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
	hud = Hud.new()
	game.add_child(hud)
	hud.setup(game, pawn, cam)
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
		if editing and event.button_index == MOUSE_BUTTON_LEFT:
			_edit_click(true)
			return
		if editing and event.button_index == MOUSE_BUTTON_RIGHT:
			_edit_mask = 0
			return
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			pawn.cycle_slot(1)
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			pawn.cycle_slot(-1)
	elif event.is_action_pressed("pause"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event.is_action_pressed("jump"):
		if pawn.mode == Pawn.Mode.BUS:
			game.eject(pawn)
		else:
			pawn.jump()
	elif event.is_action_pressed("edit"):
		_toggle_edit()
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
	hud.hit_marker(head)


func damage_taken(amount: float) -> void:
	hud.flash_damage(amount)


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
	pawn.in_fire = Input.is_action_pressed("fire") and captured and editing == null and not _ended
	if _ended:
		pawn.in_move = Vector2.ZERO
	if editing:
		_edit_update()
	# recoil settles back
	if _recoil > 0.0:
		var back := minf(_recoil, delta * 0.25)
		pawn.pitch += _recoil * 0.6 - back
		_recoil = 0.0
	_update_camera(delta)
	_interact(delta)
	_update_ghost()
	_weak.visible = _weak.visible and pawn.slot == 0 and not pawn.build_mode


func _update_camera(delta: float) -> void:
	if pawn.mode == Pawn.Mode.BUS or (pawn.mode == Pawn.Mode.DEAD and not game.bus_done):
		var bb := Basis.from_euler(Vector3(clampf(pawn.pitch, -1.2, 0.4), pawn.yaw, 0))
		var bp := game.bus_position()
		cam.global_transform = Transform3D(bb, bp + Vector3(0, 4, 0) + bb.z * 28.0)
		cam.fov = 80.0
		pawn.aim_from = cam.global_position
		pawn.aim_dir = -bb.z
		return
	var gliding := pawn.mode in [Pawn.Mode.SKYDIVE, Pawn.Mode.GLIDE]
	var aiming := pawn.in_aim and not pawn.build_mode and not pawn.current_weapon().is_empty()
	var dist := 3.0
	var side := 0.9
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
		hud.set_hint("")
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
		hud.set_hint("[E] Search %s" % what)
		if e_down:
			_interact_hold += delta
			hud.set_hint(hud.hint + "  %d%%" % int(minf(_interact_hold / 0.35, 1.0) * 100))
			if _interact_hold >= 0.35:
				game.loot.open_chest(chest)
				_interact_hold = 0.0
		else:
			_interact_hold = 0.0
	elif pk2:
		var it: Dictionary = pk2.data.item
		var r: int = it.rarity
		hud.set_hint("[E] %s %s%s" % [Cfg.RARITY_NAMES[r], Items.display_name(it), (" x%d" % it.count) if it.has("count") else ""])
		if Input.is_action_just_pressed("interact"):
			pawn.take_pickup(pk2)
	else:
		hud.set_hint("")
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


func on_match_end() -> void:
	_ended = true
	_exit_edit()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


# ------------------------------------------------------------------ editing
# G on one of your own builds opens a grid (3x3 wall, 2x2 floor). Click or drag
# to select tiles, G again confirms; right click resets. Ramps rotate per click.

func _toggle_edit() -> void:
	if editing:
		_confirm_edit()
		return
	if pawn.mode != Pawn.Mode.GROUND:
		return
	var hit := game.combat.ray(cam.global_position, cam.global_position + pawn.aim_dir * 9.0, [pawn.get_rid()], Cfg.L_BUILD)
	if hit.is_empty() or not (hit.collider as Node).has_meta("dest"):
		return
	var d: Structures.Destructible = (hit.collider as Node).get_meta("dest")
	if d.owner_id != pawn.id or d.kind == PieceMeshes.Kind.CONE:
		return
	if (hit.position as Vector3).distance_to(pawn.global_position) > 7.5:
		return
	editing = d
	_edit_mask = d.edit
	pawn.set_build_mode(false)
	pawn.rig.hold = "build"
	if _edit_overlay == null:
		_edit_overlay = MeshInstance3D.new()
		_edit_overlay.mesh = ImmediateMesh.new()
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.vertex_color_use_as_albedo = true
		m.no_depth_test = true
		_edit_overlay.material_override = m
		_edit_overlay.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		game.add_child(_edit_overlay)
	_edit_overlay.visible = true
	Sfx.play("edit")


func _confirm_edit() -> void:
	if editing and editing.alive:
		var full := 511 if editing.kind == PieceMeshes.Kind.WALL else 15
		if editing.kind == PieceMeshes.Kind.RAMP:
			game.structures.apply_edit(editing, 0, editing.dir)
		elif _edit_mask != editing.edit and _edit_mask != full:
			game.structures.apply_edit(editing, _edit_mask)
	_exit_edit()


func _exit_edit() -> void:
	editing = null
	_edit_paint = -1
	if _edit_overlay:
		_edit_overlay.visible = false
	pawn._refresh_held()


## Cell index under the crosshair, or -1.
func _edit_cell() -> int:
	var inv := editing.xf.affine_inverse()
	var o: Vector3 = inv * cam.global_position
	var dl: Vector3 = inv.basis * pawn.aim_dir
	var T := Cfg.TILE
	var L := Cfg.LEVEL
	if editing.kind == PieceMeshes.Kind.WALL:
		if absf(dl.z) < 0.001:
			return -1
		var t := -o.z / dl.z
		if t < 0.0:
			return -1
		var p := o + dl * t
		var col := floori(p.x / (T / 3.0))
		var row := floori(p.y / (L / 3.0))
		if col < 0 or col > 2 or row < 0 or row > 2:
			return -1
		return row * 3 + col
	if editing.kind == PieceMeshes.Kind.FLOOR:
		if absf(dl.y) < 0.001:
			return -1
		var t := -o.y / dl.y
		if t < 0.0:
			return -1
		var p := o + dl * t
		var i := floori(p.x / (T / 2.0))
		var j := floori(p.z / (T / 2.0))
		if i < 0 or i > 1 or j < 0 or j > 1:
			return -1
		return j * 2 + i
	return 0


func _edit_click(pressed: bool) -> void:
	if not editing:
		return
	if editing.kind == PieceMeshes.Kind.RAMP:
		if pressed:
			editing_dir_cycle()
		return
	var c := _edit_cell()
	if c < 0:
		return
	_edit_paint = 0 if (_edit_mask & (1 << c)) else 1
	_apply_paint(c)


func editing_dir_cycle() -> void:
	game.structures.apply_edit(editing, 0, (editing.dir + 1) % 4)
	Sfx.play("edit")


func _apply_paint(c: int) -> void:
	var before := _edit_mask
	if _edit_paint == 1:
		_edit_mask |= (1 << c)
	else:
		_edit_mask &= ~(1 << c)
	if before != _edit_mask:
		Sfx.play("edit", 1.3)


func _edit_update() -> void:
	if not editing.alive or editing.center.distance_to(pawn.global_position) > 9.0:
		_exit_edit()
		return
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and _edit_paint >= 0:
		var c := _edit_cell()
		if c >= 0:
			_apply_paint(c)
	elif not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_edit_paint = -1
	_draw_edit_grid()


func _draw_edit_grid() -> void:
	var im := _edit_overlay.mesh as ImmediateMesh
	im.clear_surfaces()
	var T := Cfg.TILE
	var L := Cfg.LEVEL
	var hover := _edit_cell()
	var cells := []
	if editing.kind == PieceMeshes.Kind.WALL:
		for row in 3:
			for col in 3:
				var a := Vector3(T / 3.0 * col, L / 3.0 * row, 0.15)
				cells.append([row * 3 + col, a, Vector3(T / 3.0, 0, 0), Vector3(0, L / 3.0, 0)])
	elif editing.kind == PieceMeshes.Kind.FLOOR:
		for j in 2:
			for i in 2:
				var a := Vector3(T / 2.0 * i, 0.15, T / 2.0 * j)
				cells.append([j * 2 + i, a, Vector3(T / 2.0, 0, 0), Vector3(0, 0, T / 2.0)])
	else:
		cells.append([0, Vector3(0, 0.2, 0), Vector3(T, 0, 0), Vector3(0, L, T)])
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for c: Array in cells:
		var sel := (_edit_mask & (1 << int(c[0]))) != 0 and editing.kind != PieceMeshes.Kind.RAMP
		var col := Color(0.35, 0.75, 1.0, 0.18) if not sel else Color(0.2, 0.5, 1.0, 0.65)
		if c[0] == hover and editing.kind != PieceMeshes.Kind.RAMP:
			col = col.lightened(0.35)
			col.a += 0.15
		var a: Vector3 = c[1]
		var u: Vector3 = c[2] * 0.94
		var v: Vector3 = c[3] * 0.94
		a += (c[2] as Vector3) * 0.03 + (c[3] as Vector3) * 0.03
		var pts := [a, a + u, a + u + v, a + v]
		for k: int in [0, 1, 2, 0, 2, 3]:
			im.surface_set_color(col)
			im.surface_add_vertex(editing.xf * (pts[k] as Vector3))
	im.surface_end()
