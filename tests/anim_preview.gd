extends Node3D
## Poses rigs in key animation states and saves screenshots to /tmp/sf_anim_*.png.

var rigs := []
var cam: Camera3D

func _ready() -> void:
	get_tree().create_timer(40.0).timeout.connect(get_tree().quit)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.55, 0.75, 0.95)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.7, 0.75, 0.8)
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.8, 0.5, 0)
	sun.shadow_enabled = true
	add_child(sun)
	var floor_mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(60, 60)
	floor_mi.mesh = pm
	add_child(floor_mi)
	# [hold, mesh, swing_t, combo, speed, sprint, crouch, aim]
	var setups := [
		["rifle", "ar", -1.0, 0, 0.0, false, false, 0.0],
		["rifle", "ar", -1.0, 0, 0.0, false, false, 0.5],
		["shotgun", "pump", -1.0, 0, 4.0, false, false, 0.0],
		["pistol", "pistol", -1.0, 0, 0.0, false, true, 0.0],
		["pickaxe", "pickaxe", -1.0, 0, 0.0, false, false, 0.0],
		["pickaxe", "pickaxe", 0.28, 0, 0.0, false, false, 0.0],
		["pickaxe", "pickaxe", 0.46, 0, 0.0, false, false, 0.0],
		["pickaxe", "pickaxe", 0.7, 0, 0.0, false, false, 0.0],
		["pickaxe", "pickaxe", 0.28, 1, 0.0, false, false, 0.0],
		["pickaxe", "pickaxe", 0.46, 1, 0.0, false, false, 0.0],
		["rifle", "ar", -1.0, 0, 7.3, true, false, 0.0],
		["build", "", -1.0, 0, 0.0, false, false, 0.0],
	]
	for i in setups.size():
		var s: Array = setups[i]
		var rig := CharacterRig.new()
		add_child(rig)
		rig.setup(i)
		rig.position = Vector3((i % 6) * 1.6, 0, (i / 6) * 2.6)
		rig.hold = s[0]
		rig.set_held_mesh(s[1], 3)
		rigs.append([rig, s])
	cam = Camera3D.new()
	add_child(cam)
	await get_tree().create_timer(1.2).timeout
	var views := [
		[Vector3(4.0, 1.6, -5.0), Vector3(4.0, 0.9, 1.3)],
		[Vector3(-4.5, 1.8, -1.5), Vector3(3.0, 0.9, 1.3)],
		[Vector3(7.4, 1.6, -2.6), Vector3(7.4, 1.0, 0.0)],
		[Vector3(9.6 + 0.75, 1.75, 3.2), Vector3(9.6, 1.2, -2.0)],
		[Vector3(1.6 * 6 + 0.75 - 9.6, 1.75, 3.2 + 2.6), Vector3(0.0, 1.2, 0.6)],
	]
	for view in views.size():
		cam.global_position = views[view][0]
		cam.look_at(views[view][1])
		await get_tree().create_timer(0.4).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("/tmp/sf_anim_%d.png" % view)
	get_tree().quit()

func _process(_d: float) -> void:
	for r: Array in rigs:
		var rig: CharacterRig = r[0]
		var s: Array = r[1]
		rig.swing_t = s[2]
		rig.swing_combo = s[3]
		rig.move_local = Vector2(0, s[4])
		rig.sprinting = s[5]
		rig.crouching = s[6]
		rig.aim_pitch = s[7]
