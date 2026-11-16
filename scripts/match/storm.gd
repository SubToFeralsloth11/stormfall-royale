class_name Storm
extends Node3D
## Shrinking storm circle following Cfg.STORM_PHASES (wait, shrink, dmg%/s,
## radius, move). Phase 0 forms the first 1500 m eye; later eyes are picked
## inside the previous one; late phases may move outside it.

const START_RADIUS := 2600.0

var phase := -1
var waiting := true
var timer := 0.0
var center := Vector2.ZERO
var radius := START_RADIUS
var next_center := Vector2.ZERO
var next_radius := START_RADIUS
var damage := 0.0
var finished := false
var _from_center := Vector2.ZERO
var _from_radius := START_RADIUS
var _rng := RandomNumberGenerator.new()
var _wall: MeshInstance3D
var _terrain: Terrain


func setup(t: Terrain, seed_value: int) -> void:
	_terrain = t
	_rng.seed = seed_value
	var cyl := CylinderMesh.new()
	cyl.top_radius = 1.0
	cyl.bottom_radius = 1.0
	cyl.height = 1.0
	cyl.radial_segments = 96
	cyl.rings = 1
	cyl.cap_top = false
	cyl.cap_bottom = false
	_wall = MeshInstance3D.new()
	_wall.mesh = cyl
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/storm.gdshader")
	_wall.material_override = mat
	_wall.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_wall.extra_cull_margin = 4000.0
	add_child(_wall)
	_begin_phase(0)
	_update_wall()


func _pick_center(inside_c: Vector2, inside_r: float, new_r: float, move: float) -> Vector2:
	for i in 40:
		var maxd := maxf(inside_r - new_r, 0.0) + move
		var c := inside_c + Vector2.from_angle(_rng.randf() * TAU) * sqrt(_rng.randf()) * maxd
		# keep eyes over land so the endgame isn't in the sea
		if _terrain.height_at(c.x, c.y) > 1.0 and absf(c.x) < 1250.0 and absf(c.y) < 1250.0:
			return c
	return inside_c


func _begin_phase(i: int) -> void:
	phase = i
	waiting = true
	var p: Array = Cfg.STORM_PHASES[i]
	timer = p[0]
	var new_r: float = p[3]
	if i == 0:
		next_center = _pick_center(Vector2.ZERO, 700.0, 0.0, 0.0)
	else:
		next_center = _pick_center(center, radius, new_r, p[4])
	next_radius = new_r


func _process(delta: float) -> void:
	if finished:
		return
	timer -= delta
	var p: Array = Cfg.STORM_PHASES[phase]
	if waiting:
		if timer <= 0.0:
			waiting = false
			_from_center = center
			_from_radius = radius
			timer = maxf(p[1], 30.0) if phase == 0 else p[1]
			damage = p[2]
	else:
		var total: float = maxf(p[1], 30.0) if phase == 0 else p[1]
		var k := clampf(1.0 - timer / maxf(total, 0.01), 0.0, 1.0)
		center = _from_center.lerp(next_center, k)
		radius = lerpf(_from_radius, next_radius, k)
		if timer <= 0.0:
			center = next_center
			radius = next_radius
			if phase + 1 < Cfg.STORM_PHASES.size():
				_begin_phase(phase + 1)
			else:
				finished = true
	_update_wall()


func _update_wall() -> void:
	_wall.position = Vector3(center.x, -60.0, center.y)
	_wall.scale = Vector3(maxf(radius, 0.5), 1600.0, maxf(radius, 0.5))


func is_outside(p: Vector3) -> bool:
	return Vector2(p.x, p.z).distance_to(center) > radius


func label() -> String:
	if finished:
		return "Final storm"
	var t := maxi(0, ceili(timer))
	var mmss := "%d:%02d" % [t / 60, t % 60]
	if waiting:
		return "Storm shrinks in %s" % mmss if phase > 0 or radius < START_RADIUS else "Storm forming in %s" % mmss
	return "Storm closing %s" % mmss
