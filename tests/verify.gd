extends Node
## Verification run: world build time/memory, jump height, countryside
## screenshots from the ground, and a front view of the player's arms.

var m: Match

func _ready() -> void:
	get_tree().create_timer(80.0).timeout.connect(get_tree().quit)
	var t0 := Time.get_ticks_msec()
	m = Match.new()
	add_child(m)
	await m.loaded
	print("VERIFY build ms=", Time.get_ticks_msec() - t0, " mem MB=", OS.get_static_memory_usage() / 1048576)
	Sfx.loop("bus", -80.0)
	var p := m.player
	var spots := [Vector2(520, 120), Vector2(-450, -260), Vector2(200, -650)]
	await get_tree().physics_frame
	p.get_child(0).disabled = false
	p.mode = Pawn.Mode.GROUND
	p.visible = true
	p.inventory[0] = Items.make_weapon("ar", 2)
	for i in spots.size():
		var s: Vector2 = spots[i]
		p.global_position = Vector3(s.x, m.terrain.height_at(s.x, s.y) + 0.5, s.y)
		p.velocity = Vector3.ZERO
		p.yaw = i * 2.1
		p.pitch = -0.05
		await get_tree().create_timer(1.0).timeout
		if i == 0:
			var y0 := p.global_position.y
			var peak := y0
			p.jump()
			for f in 60:
				await get_tree().physics_frame
				peak = maxf(peak, p.global_position.y)
			print("VERIFY jump height=", snappedf(peak - y0, 0.01), " on_floor_before=true")
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("/tmp/sf_verify_%d.png" % i)
	# front view of arms holding the rifle
	p.select_slot(1)
	await get_tree().create_timer(0.8).timeout
	m.controller.set_process(false)
	var cam := m.controller.cam
	var fwd := Vector3(-sin(p.yaw), 0, -cos(p.yaw))
	cam.global_position = p.global_position + fwd * 2.6 + Vector3(0, 1.4, 0)
	cam.look_at(p.global_position + Vector3(0, 1.1, 0))
	await get_tree().create_timer(0.3).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("/tmp/sf_verify_arms.png")
	p.select_slot(0)
	await get_tree().create_timer(0.6).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("/tmp/sf_verify_arms2.png")
	get_tree().quit()
