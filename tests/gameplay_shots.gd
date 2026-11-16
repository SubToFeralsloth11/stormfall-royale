extends Node
## Drops the player straight onto the ground with loot and mats, then drives
## inputs to capture third-person screenshots: rifle idle, pickaxe swing,
## builds, edit grid. Saves /tmp/sf_play_*.png.

var m: Match

func _ready() -> void:
	get_tree().create_timer(90.0).timeout.connect(get_tree().quit)
	m = Match.new()
	add_child(m)
	await m.loaded
	var p := m.player
	var c: Vector2 = Terrain.POIS[1].pos + Vector2(40, 60)
	p.global_position = Vector3(c.x, m.terrain.height_at(c.x, c.y) + 1.0, c.y)
	await get_tree().physics_frame
	p.get_child(0).disabled = false
	p.global_position = Vector3(c.x, m.terrain.height_at(c.x, c.y) + 1.0, c.y)
	p.mode = Pawn.Mode.GROUND
	p.visible = true
	p.inventory[0] = Items.make_weapon("ar", 3)
	p.inventory[1] = Items.make_weapon("pump", 2)
	p.mats = [300, 300, 300]
	p.ammo.medium = 120
	Sfx.loop("bus", -80.0)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	await _wait(1.5)
	p.select_slot(1)
	p.pitch = -0.1
	await _wait(1.0)
	_shot(0)
	Input.action_press("aim")
	await _wait(0.6)
	_shot(1)
	Input.action_release("aim")
	p.select_slot(0)
	await _wait(0.5)
	Input.action_press("fire")
	await _wait(0.33)
	_shot(2)
	await _wait(0.12)
	_shot(3)
	Input.action_release("fire")
	await _wait(0.6)
	p.set_build_mode(true, PieceMeshes.Kind.WALL)
	await _wait(0.2)
	m.try_build(p)
	p.yaw += 0.6
	await _wait(0.2)
	p.build_kind = PieceMeshes.Kind.RAMP
	p.yaw -= 0.6
	p.yaw += PI * 0.5
	m.try_build(p)
	p.build_kind = PieceMeshes.Kind.FLOOR
	await _wait(0.3)
	_shot(4)
	var r := p.rig
	print("DBG held=", r.held.mesh, " hold=", r.hold, " trail=", r._trail.visible if r._trail else null, " swing=", r.swing_t, " glider=", r.glider.visible)
	for ch in r.skeleton.get_children():
		print("DBG child ", ch.name, " ", ch.get_class(), " vis=", ch.visible if ch is Node3D else "")
	p.yaw -= PI * 0.5
	p.set_build_mode(false)
	await _wait(0.3)
	var ev := InputEventAction.new()
	ev.action = "edit"
	ev.pressed = true
	m.controller._toggle_edit()
	m.controller._edit_mask = (1 << 1) | (1 << 4)
	await _wait(0.4)
	_shot(5)
	m.controller._toggle_edit()
	await _wait(0.6)
	_shot(6)
	get_tree().quit()

func _wait(s: float) -> void:
	await get_tree().create_timer(s).timeout

func _shot(i: int) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("/tmp/sf_play_%d.png" % i)
