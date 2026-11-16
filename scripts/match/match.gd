class_name Match
extends Node3D
## Owns the world (terrain, structures, loot, combat), the pawns and match
## flow. Pawns call back into it for building, hit feedback and queries.

signal loaded

var terrain: Terrain
var structures: Structures
var loot: Loot
var combat: Combat
var player: Pawn
var controller: PlayerController
var pawns: Array[Pawn] = []
var time := 0.0
var ended := false
var seed_value := 1234
var _weakspots := {}   # dest id -> Vector3
var storm: Storm
var brains: Array[BotBrain] = []
var bus_node: Node3D
var bus_a := Vector2.ZERO
var bus_b := Vector2.ZERO
var bus_t := 0.0          # metres travelled
var bus_len := 1.0
var bus_done := false
var _brain_i := 0
var _storm_tick := 0.0
var _lite_fight_t := 0.0
var _rng := RandomNumberGenerator.new()
const BOT_COUNT := 99
const NAME_A := ["Pixel", "Turbo", "Mighty", "Sneaky", "Cosmic", "Lucky", "Rapid", "Frosty", "Silent", "Crispy", "Wobbly", "Shadow", "Neon", "Toasty", "Brave", "Fuzzy", "Spicy", "Rusty", "Jolly", "Hyper"]
const NAME_B := ["Panda", "Llama", "Falcon", "Noodle", "Badger", "Taco", "Comet", "Pickle", "Otter", "Ninja", "Walrus", "Rocket", "Muffin", "Gecko", "Raptor", "Bean", "Yeti", "Kraken", "Waffle", "Moose"]


func _ready() -> void:
	_setup_environment()
	await get_tree().process_frame
	terrain = Terrain.new()
	add_child(terrain)
	terrain.generate(seed_value)
	_water()
	structures = Structures.new(terrain)
	add_child(structures)
	loot = Loot.new(terrain, seed_value)
	add_child(loot)
	combat = Combat.new(self)
	add_child(combat)
	Fx.reset(self)
	var ib := IslandBuilder.new(terrain, structures, loot, seed_value + 1)
	ib.build_all()
	_rng.seed = seed_value + 9
	storm = Storm.new()
	add_child(storm)
	storm.setup(terrain, seed_value + 3)
	_setup_bus()
	_spawn_player()
	_spawn_bots()
	Sfx.loop("bus", 0.0)
	loaded.emit()


func _setup_environment() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.22, 0.48, 0.92)
	sm.sky_horizon_color = Color(0.65, 0.82, 0.98)
	sm.ground_horizon_color = Color(0.65, 0.82, 0.98)
	sm.ground_bottom_color = Color(0.3, 0.45, 0.6)
	sm.sun_angle_max = 20.0
	sky.sky_material = sm
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_energy = 1.0
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.tonemap_exposure = 1.05
	e.fog_enabled = true
	e.fog_light_color = Color(0.68, 0.82, 0.97)
	e.fog_density = 0.00012
	e.fog_sky_affect = 0.3
	e.glow_enabled = true
	e.glow_intensity = 0.4
	e.adjustment_enabled = true
	e.adjustment_saturation = 1.15
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-52), deg_to_rad(35), 0)
	sun.light_energy = 1.25
	sun.light_color = Color(1.0, 0.96, 0.9)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 160.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	add_child(sun)


func _water() -> void:
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(9000, 9000)
	mi.mesh = pm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.15, 0.55, 0.85, 0.82)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.roughness = 0.08
	mat.metallic_specular = 0.9
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position.y = Cfg.SEA_LEVEL
	add_child(mi)


func _spawn_player() -> void:
	player = Pawn.new()
	add_child(player)
	player.setup(self, 1, "You", Cfg.selected_skin, true)
	_board(player)
	controller = PlayerController.new()
	add_child(controller)
	controller.setup(self, player)


func _spawn_bots() -> void:
	for i in BOT_COUNT:
		var b := Pawn.new()
		add_child(b)
		var nm := "%s%s%d" % [NAME_A[_rng.randi() % NAME_A.size()], NAME_B[_rng.randi() % NAME_B.size()], _rng.randi_range(1, 99)]
		b.setup(self, i + 2, nm, _rng.randi() % Skins.count(), false)
		_board(b)
		var brain := BotBrain.new(b, self, seed_value * 31 + i)
		brain.plan_drop(bus_a, bus_b)
		brains.append(brain)


func _board(pw: Pawn) -> void:
	pawns.append(pw)
	pw.eliminated.connect(_on_eliminated)
	pw.mode = Pawn.Mode.BUS
	pw.visible = false
	pw.set_physics_process(true)
	pw.get_child(0).set_deferred("disabled", true)   # collision shape off while riding
	pw.global_position = Vector3(bus_a.x, Cfg.BUS_HEIGHT, bus_a.y)


# ------------------------------------------------------------------ bus

func _setup_bus() -> void:
	var ang := _rng.randf() * TAU
	var off := Vector2.from_angle(ang + PI * 0.5) * _rng.randf_range(-450.0, 450.0)
	bus_a = Vector2.from_angle(ang) * 2100.0 + off
	bus_b = -Vector2.from_angle(ang) * 2100.0 + off
	bus_len = bus_a.distance_to(bus_b)
	bus_node = Node3D.new()
	add_child(bus_node)
	var mat := MeshBuilder.vc_material(0.5)
	var body := MeshInstance3D.new()
	body.mesh = ItemMeshes.get_mesh("bus")
	body.material_override = mat
	bus_node.add_child(body)
	var balloon := MeshInstance3D.new()
	balloon.mesh = ItemMeshes.get_mesh("balloon")
	balloon.material_override = mat
	balloon.position = Vector3(0, 3.2, 0)
	bus_node.add_child(balloon)
	var dir := (bus_b - bus_a).normalized()
	bus_node.rotation.y = atan2(-dir.x, -dir.y) + PI
	_place_bus()


func _place_bus() -> void:
	var p := bus_a.lerp(bus_b, bus_t / bus_len)
	bus_node.global_position = Vector3(p.x, Cfg.BUS_HEIGHT, p.y)


func bus_progress() -> float:
	return bus_t / bus_len


func bus_position() -> Vector3:
	return bus_node.global_position


func can_jump() -> bool:
	# doors open once the bus is over the island
	var p := bus_a.lerp(bus_b, bus_t / bus_len)
	return terrain.coast_distance(p.x, p.y) < 150.0 or bus_progress() > 0.5


func eject(pw: Pawn) -> void:
	if pw.mode != Pawn.Mode.BUS or not can_jump() and not bus_done:
		return
	var dir := (bus_b - bus_a).normalized()
	pw.global_position = bus_node.global_position + Vector3(_rng.randf_range(-2, 2), -4.0, _rng.randf_range(-2, 2))
	pw.get_child(0).set_deferred("disabled", false)
	pw.start_skydive(Vector3(dir.x, 0, dir.y) * 15.0 + Vector3(0, -8, 0))
	if pw.is_player:
		Sfx.loop("bus", -80.0)


func _process(delta: float) -> void:
	time += delta
	if not bus_done:
		bus_t = minf(bus_len, bus_t + Cfg.BUS_SPEED * delta)
		_place_bus()
		for pw in pawns:
			if pw.mode == Pawn.Mode.BUS:
				pw.global_position = bus_node.global_position
		if bus_t >= bus_len * 0.97:
			bus_done = true
			for pw in pawns:
				if pw.mode == Pawn.Mode.BUS:
					eject(pw)
			bus_node.visible = false
	# bots: think a slice per frame, steer every frame
	var n := brains.size()
	var slice := maxi(1, n / 6)
	for k in slice:
		if n == 0:
			break
		_brain_i = (_brain_i + 1) % n
		brains[_brain_i].think(delta * 6.0)
	for b in brains:
		b.steer(delta)
	_update_lod()
	_tick_storm(delta)
	_lite_fights(delta)


## Far bots skip physics and animate rarely; near bots run full simulation.
func _update_lod() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var cp := cam.global_position
	for pw in pawns:
		if pw.is_player or not pw.is_alive():
			continue
		var d := pw.global_position.distance_to(cp)
		var far := d > 260.0
		if far != pw.lite and pw.mode != Pawn.Mode.BUS:
			pw.lite = far
			if not far:
				# snap onto real geometry when becoming physical again
				pw.velocity = Vector3.ZERO
		if pw.mode == Pawn.Mode.BUS:
			continue
		pw.rig.visible = d < 700.0
		pw.rig.lod_skip = 0 if d < 45.0 else (1 if d < 110.0 else (3 if d < 260.0 else 8))


func _tick_storm(delta: float) -> void:
	_storm_tick += delta
	var in_storm := player.is_alive() and player.mode != Pawn.Mode.BUS and storm.is_outside(player.global_position)
	Sfx.loop("storm", -4.0 if in_storm else -80.0)
	if _storm_tick < 1.0:
		return
	_storm_tick = 0.0
	if storm.damage <= 0.0:
		return
	for pw in pawns:
		if pw.is_alive() and pw.mode != Pawn.Mode.BUS and storm.is_outside(pw.global_position):
			pw.take_damage(storm.damage, null, "storm", false, pw.global_position + Vector3.UP, true)


## Fights between bots far from the player are resolved statistically.
func _lite_fights(delta: float) -> void:
	_lite_fight_t += delta
	if _lite_fight_t < 0.5:
		return
	_lite_fight_t = 0.0
	for b in brains:
		var pw := b.pawn
		if not pw.is_alive() or not pw.lite or pw.mode != Pawn.Mode.GROUND:
			continue
		var e := b.enemy
		if e == null or not e.is_alive() or not e.lite:
			continue
		var w := pw.current_weapon()
		if w.is_empty() or w.ammo <= 0:
			continue
		var wd: Dictionary = Items.WEAPONS[w.id]
		var d := pw.global_position.distance_to(e.global_position)
		var hit_chance := clampf(b.skill * 0.9 - d * 0.004, 0.08, 0.8)
		var shots := maxi(1, int(float(wd.rate) * 0.5))
		for i in shots:
			if w.ammo <= 0:
				break
			w.ammo -= 1
			if _rng.randf() < hit_chance:
				e.take_damage(Items.damage(w) * (0.6 if d > float(wd.range) * 0.3 else 1.0), pw, w.id, _rng.randf() < 0.15, e.global_position + Vector3.UP)


func _on_eliminated(victim: Pawn, killer: Pawn, weapon: String) -> void:
	victim.placement = alive_count() + 1
	var wname: String = "the storm" if weapon == "storm" else ("a fall" if weapon == "fall" else (Items.WEAPONS[weapon].name if Items.WEAPONS.has(weapon) else "a pickaxe"))
	var text: String
	if killer and killer != victim:
		text = "%s eliminated %s with %s" % [killer.display_name, victim.display_name, wname]
	else:
		text = "%s was eliminated by %s" % [victim.display_name, wname]
	controller.hud.push_kill(text)
	if killer == player and victim != player:
		Sfx.play("elim")
	if victim == player:
		_finish(false)
	elif alive_count() <= 1 and player.is_alive():
		player.placement = 1
		_finish(true)


func _finish(victory: bool) -> void:
	if ended:
		return
	ended = victory
	if victory:
		Sfx.play("victory")
	controller.on_match_end()
	controller.hud.show_end(player.placement, player.kills, victory)


# ------------------------------------------------------------------ queries

func near_player(p: Vector3, r: float) -> bool:
	return player != null and player.global_position.distance_to(p) < r


func pawns_near(p: Vector3, r: float) -> Array:
	var out := []
	for pw in pawns:
		if pw.is_alive() and pw.global_position.distance_to(p) < r:
			out.append(pw)
	return out


# ------------------------------------------------------------------ feedback

func player_fired(recoil: float) -> void:
	controller.add_recoil(recoil)


func player_hit_marker(head: bool, shield_hit: bool) -> void:
	controller.hit_marker(head)


func camera_shake(amount: float) -> void:
	controller.shake = maxf(controller.shake, amount)


func player_damaged(_attacker: Pawn, amount: float) -> void:
	controller.damage_taken(amount)


## Everything the HUD needs that isn't on the pawn.
func hud_info() -> Dictionary:
	return {
		"alive": alive_count(),
		"phase": storm.phase, "storm_label": storm.label(), "storm_time": storm.timer,
		"storm_center": storm.center, "storm_radius": storm.radius,
		"next_center": storm.next_center, "next_radius": storm.next_radius,
		"bus_path": [] if bus_done else [bus_a, bus_b],
		"in_storm": player.mode != Pawn.Mode.BUS and storm.is_outside(player.global_position),
		"in_bus": player.mode == Pawn.Mode.BUS, "can_jump": can_jump(),
	}


func alive_count() -> int:
	var n := 0
	for pw in pawns:
		if pw.is_alive():
			n += 1
	return n


## Harvest weak spot: first hit spawns one, hitting near it crits and moves it.
func check_weakspot(pw: Pawn, d: Structures.Destructible, at: Vector3) -> bool:
	if not pw.is_player or not d.harvest:
		return false
	var crit := false
	if _weakspots.has(d.id) and (_weakspots[d.id] as Vector3).distance_to(at) < 0.7:
		crit = true
	var n := (at - pw.eye_pos()).normalized()
	var side := n.cross(Vector3.UP).normalized()
	var spot := at + side * randf_range(-0.9, 0.9) + Vector3.UP * randf_range(-0.6, 0.6)
	_weakspots[d.id] = spot
	controller.show_weakspot(spot)
	return crit


# ------------------------------------------------------------------ building

## Fortnite-style target selection for the current piece.
func build_target(pw: Pawn) -> Dictionary:
	var K := PieceMeshes.Kind
	var feet := pw.global_position
	var fwd := Vector3(-sin(pw.yaw), 0, -cos(pw.yaw))
	var dir4 := _dir4(pw.yaw)                 # 0:-z 1:+x 2:+z 3:-x
	var level := floori((feet.y + 0.4) / Cfg.LEVEL)
	var pitch := pw.pitch
	var cell: Vector3i
	var dir := 0
	match pw.build_kind:
		K.WALL:
			var here := Cfg.cell_of(feet + Vector3(0, 0.4, 0))
			var p := feet + fwd * 1.4
			var c := Cfg.cell_of(Vector3(p.x, feet.y + 0.4, p.z))
			if c.x != here.x or c.z != here.z:
				here = c
			if pitch > 0.6:
				here.y += 1
			cell = here
			match dir4:
				0: dir = 0
				2:
					cell.z += 1
					dir = 0
				1:
					cell.x += 1
					dir = 1
				3: dir = 1
		K.FLOOR:
			var p := feet + fwd * (0.5 if pitch < -0.9 else 3.4)
			cell = Cfg.cell_of(Vector3(p.x, feet.y + 0.4, p.z))
			if pitch > 0.35:
				cell = Cfg.cell_of(feet + Vector3(0, 0.4, 0))
				cell.y += 1
		K.RAMP:
			var here := Cfg.cell_of(feet + Vector3(0, 0.4, 0))
			var p := feet + fwd * 3.2
			cell = Cfg.cell_of(Vector3(p.x, feet.y + 0.4, p.z))
			dir = dir4   # ramp rises away from the player
			var below := structures.get_slot(K.RAMP, Vector3i(here.x, level, here.z), dir)
			var below2 := structures.get_slot(K.RAMP, Vector3i(here.x, level - 1, here.z), dir)
			if (below or below2) and (cell.x != here.x or cell.z != here.z):
				var base := level if below else level - 1
				cell.y = base + 1
			if pitch > 0.7:
				cell.y += 1
		K.CONE:
			var p := feet + fwd * 3.0
			cell = Cfg.cell_of(Vector3(p.x, feet.y + 0.4, p.z))
			if pitch > 0.3:
				cell = Cfg.cell_of(feet + Vector3(0, 0.4, 0))
				cell.y += 1
	return {"kind": pw.build_kind, "cell": cell, "dir": dir}


static func _dir4(yaw: float) -> int:
	# facing -z at yaw 0; yaw increases counter-clockwise (toward -x)
	var a := posmod(roundi(yaw / (PI * 0.5)), 4)
	return [0, 3, 2, 1][a]


func try_build(pw: Pawn) -> bool:
	if pw.mats[pw.build_mat] < Cfg.BUILD_COST:
		return false
	var t := build_target(pw)
	if not structures.can_place(t.kind, t.cell, t.dir):
		return false
	var d := structures.place(t.kind, t.cell, t.dir, pw.build_mat, pw.id)
	if d == null:
		return false
	pw.mats[pw.build_mat] -= Cfg.BUILD_COST
	pw.on_built()
	Sfx.play_at("build", d.center)
	return true
