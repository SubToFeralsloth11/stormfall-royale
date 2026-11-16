extends Node
## Measures average FPS at a countryside spot while toggling suspects.

var m: Match

func _ready() -> void:
	get_tree().create_timer(120.0).timeout.connect(get_tree().quit)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	m = Match.new()
	add_child(m)
	await m.loaded
	Sfx.loop("bus", -80.0)
	var p := m.player
	await get_tree().physics_frame
	p.get_child(0).disabled = false
	p.mode = Pawn.Mode.GROUND
	p.visible = true
	var s := Vector2(-450, -260)
	p.global_position = Vector3(s.x, m.terrain.height_at(s.x, s.y) + 0.5, s.y)
	p.yaw = 2.1
	await _measure("baseline")
	await _measure("baseline2")
	m.storm.visible = false
	await _measure("no storm wall")
	var sun: DirectionalLight3D
	for c in m.get_children():
		if c is DirectionalLight3D:
			sun = c
	sun.shadow_enabled = false
	await _measure("no storm, no shadows")
	for c in m.structures.batcher.get_children():
		var mmi := c as MultiMeshInstance3D
		if mmi.multimesh.mesh == PropMeshes.get_mesh("grass", 0) or mmi.multimesh.mesh == PropMeshes.get_mesh("grass", 1):
			mmi.visible = false
	await _measure("+ no grass")
	m.structures.batcher.visible = false
	await _measure("+ no batched props/pieces")
	get_tree().quit()

func _measure(label: String) -> void:
	await get_tree().create_timer(1.0).timeout
	var f0 := Engine.get_frames_drawn()
	var t0 := Time.get_ticks_usec()
	await get_tree().create_timer(3.0).timeout
	var fps := (Engine.get_frames_drawn() - f0) / ((Time.get_ticks_usec() - t0) / 1e6)
	print("PERF %-28s %.1f fps  draw_calls=%d prims=%d" % [label, fps, RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME), RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)])
