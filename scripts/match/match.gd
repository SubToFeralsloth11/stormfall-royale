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
	_spawn_player()
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
	e.fog_density = 0.00035
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
	pawns.append(player)
	var c: Vector2 = Terrain.POIS[0].pos
	player.global_position = Vector3(c.x + 30, 450.0, c.y + 220)
	player.yaw = 0.0
	player.start_skydive(Vector3(0, -20, -10))
	controller = PlayerController.new()
	add_child(controller)
	controller.setup(self, player)


func _process(delta: float) -> void:
	time += delta


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
		"phase": -1, "storm_label": "", "storm_time": 0.0,
		"storm_center": Vector2.ZERO, "storm_radius": 99999.0,
		"next_center": Vector2.ZERO, "next_radius": 99999.0,
		"bus_path": [], "in_storm": false,
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
