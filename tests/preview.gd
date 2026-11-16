extends Node3D
## Visual smoke test: builds the island and a line-up of all skins, then
## saves screenshots from a few cameras to /tmp/sf_preview_*.png and quits.

var terrain: Terrain
var shots := []
var cam: Camera3D

func _ready() -> void:
	get_tree().create_timer(60.0).timeout.connect(get_tree().quit)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	sky.sky_material = ProceduralSkyMaterial.new()
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.9, 0.6, 0)
	sun.shadow_enabled = true
	add_child(sun)
	terrain = Terrain.new()
	add_child(terrain)
	var t0 := Time.get_ticks_msec()
	terrain.generate(1234)
	var st := Structures.new(terrain)
	add_child(st)
	var loot := Loot.new(terrain, 1)
	add_child(loot)
	Fx.reset(self)
	var ib := IslandBuilder.new(terrain, st, loot, 77)
	ib.build_all()
	print("world ms ", Time.get_ticks_msec() - t0, " pieces ", ib.piece_count, " chests ", ib.chest_count)
	var c: Vector2 = Terrain.POIS[0].pos
	var base := Vector3(c.x + 40, terrain.height_at(c.x + 40, c.y + 60), c.y + 60)
	for i in Skins.count():
		var rig := CharacterRig.new()
		add_child(rig)
		rig.setup(i)
		rig.position = base + Vector3((i % 10) * 1.2, 0, (i / 10) * 2.0)
		rig.position.y = terrain.height_at(rig.position.x, rig.position.z)
		rig.rotation.y = PI
		rig.hold = ["rifle", "pickaxe", "shotgun", "pistol"][i % 4]
		rig.set_held_mesh(["ar", "pickaxe", "pump", "pistol"][i % 4], i % 5)
		if i == 5: rig.move_local = Vector2(0, 5.5)
		if i == 6: rig.crouching = true
		if i == 7: rig.emote = 0
		if i == 8: rig.pose = CharacterRig.Pose.GLIDE
		if i == 9: rig.pose = CharacterRig.Pose.SKYDIVE
	cam = Camera3D.new()
	cam.far = 4000.0
	add_child(cam)
	shots = [
		[base + Vector3(6, 1.6, 6.5), base + Vector3(6, 1.0, 0)],
		[Vector3(c.x - 60, 60, c.y + 140), Vector3(c.x, 10, c.y)],
		[Vector3(0, 700, 1500), Vector3(0, 0, 0)],
		[Vector3(Terrain.POIS[1].pos.x + 50, 40, Terrain.POIS[1].pos.y + 90), Vector3(Terrain.POIS[1].pos.x, 20, Terrain.POIS[1].pos.y)],
	]
	_next_shot(0)

func _next_shot(i: int) -> void:
	if i >= shots.size():
		get_tree().quit()
		return
	cam.global_position = shots[i][0]
	cam.look_at(shots[i][1])
	await get_tree().create_timer(1.5).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("/tmp/sf_preview_%d.png" % i)
	print("shot ", i, " fps ", Engine.get_frames_per_second())
	_next_shot(i + 1)
