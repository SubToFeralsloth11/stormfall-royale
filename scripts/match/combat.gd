class_name Combat
extends Node3D
## Hit resolution (pawns, structures, props), travelling projectiles with
## gravity (sniper) and explosives (rockets).

const HIT_MASK := Cfg.L_WORLD | Cfg.L_BUILD | Cfg.L_PAWN

class Projectile:
	extends RefCounted
	var owner: Pawn
	var pos := Vector3.ZERO
	var vel := Vector3.ZERO
	var gravity := 0.0
	var dmg := 0.0
	var head_mult := 1.0
	var struct_mult := 1.0
	var weapon := ""
	var explosive := 0.0
	var life := 4.0
	var node: Node3D

var game: Match
var _projectiles: Array[Projectile] = []
var _rocket_mat: StandardMaterial3D


func _init(g: Match) -> void:
	game = g
	_rocket_mat = MeshBuilder.vc_material(0.5)


## Raycast that skips `exclude` pawn. Returns {} or hit dict.
func ray(from: Vector3, to: Vector3, exclude: Array[RID] = [], mask := HIT_MASK) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(from, to, mask, exclude)
	q.hit_from_inside = false
	return get_world_3d().direct_space_state.intersect_ray(q)


## Applies one bullet/pellet hit. Returns "head", "body", "build", "world" or "".
func apply_hit(attacker: Pawn, hit: Dictionary, dmg: float, head_mult: float, struct_mult: float, weapon: String) -> String:
	if hit.is_empty():
		return ""
	var col: Object = hit.collider
	if col is Pawn:
		var victim := col as Pawn
		if victim == attacker or not victim.is_alive():
			return ""
		var head := victim.is_head_hit(hit.position)
		var amount := dmg * (head_mult if head else 1.0)
		victim.take_damage(amount, attacker, weapon, head, hit.position)
		return "head" if head else "body"
	if col is Node and (col as Node).has_meta("dest"):
		var d: Structures.Destructible = (col as Node).get_meta("dest")
		var amount := dmg * struct_mult
		if d.is_piece or d.max_hp < 9000.0:
			game.structures.damage(d, amount)
			if attacker and attacker.is_player:
				Fx.number(hit.position, str(roundi(amount)), 3)
		Fx.impact(hit.position, hit.normal, d.tint)
		return "build"
	Fx.impact(hit.position, hit.normal)
	return "world"


func spawn_projectile(owner: Pawn, from: Vector3, dir: Vector3, speed: float, dmg: float, head_mult: float, struct_mult: float, weapon: String, explosive: float) -> void:
	var p := Projectile.new()
	p.owner = owner
	p.pos = from
	p.vel = dir * speed
	p.gravity = 9.0 if explosive <= 0.0 else 0.0
	p.dmg = dmg
	p.head_mult = head_mult
	p.struct_mult = struct_mult
	p.weapon = weapon
	p.explosive = explosive
	var mi := MeshInstance3D.new()
	if explosive > 0.0:
		var m := CylinderMesh.new()
		m.top_radius = 0.0
		m.bottom_radius = 0.09
		m.height = 0.6
		m.radial_segments = 6
		mi.mesh = m
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.5, 0.55, 0.45)
		mat.emission_enabled = true
		mat.emission = Color(1, 0.5, 0.2)
		mat.emission_energy_multiplier = 0.6
		mi.material_override = mat
	else:
		var m := CylinderMesh.new()
		m.top_radius = 0.02
		m.bottom_radius = 0.02
		m.height = 1.6
		m.radial_segments = 4
		mi.mesh = m
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = Color(1, 0.9, 0.6)
		mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	p.node = mi
	_orient(p)
	_projectiles.append(p)


func _orient(p: Projectile) -> void:
	if p.vel.length_squared() > 0.01:
		p.node.global_transform = Transform3D(MeshBuilder._basis_from_y(p.vel.normalized()), p.pos)


func _physics_process(delta: float) -> void:
	for i in range(_projectiles.size() - 1, -1, -1):
		var p := _projectiles[i]
		p.life -= delta
		p.vel.y -= p.gravity * delta
		var nxt := p.pos + p.vel * delta
		var excl: Array[RID] = []
		if is_instance_valid(p.owner):
			excl.append(p.owner.get_rid())
		var hit := ray(p.pos, nxt, excl)
		if not hit.is_empty() or p.life <= 0.0 or nxt.y < -30.0:
			if p.explosive > 0.0:
				explode(p.owner, hit.position if not hit.is_empty() else nxt, p.explosive, p.dmg, p.struct_mult, p.weapon)
			elif not hit.is_empty():
				var res := apply_hit(p.owner if is_instance_valid(p.owner) else null, hit, p.dmg, p.head_mult, p.struct_mult, p.weapon)
				if is_instance_valid(p.owner) and p.owner.is_player and (res == "head" or res == "body"):
					p.owner.on_hit_confirm(res == "head", false)
			p.node.queue_free()
			_projectiles.remove_at(i)
			continue
		p.pos = nxt
		_orient(p)


func explode(owner: Pawn, at: Vector3, radius: float, dmg: float, struct_mult: float, weapon: String) -> void:
	Fx.explosion(at, radius)
	Sfx.play_at("explosion", at)
	if owner and owner.is_player:
		owner.shake(0.6)
	for d: Structures.Destructible in game.structures.pieces_near(at, radius):
		game.structures.damage(d, dmg * struct_mult)
	for pw: Pawn in game.pawns_near(at, radius + 1.0):
		if not pw.is_alive():
			continue
		var dist := pw.global_position.distance_to(at)
		var falloff := clampf(1.0 - dist / (radius + 1.0), 0.25, 1.0)
		# walls between blast and pawn block it
		var los := ray(at + (pw.global_position + Vector3.UP - at).normalized() * 0.3, pw.global_position + Vector3.UP, [], Cfg.L_BUILD | Cfg.L_WORLD)
		if not los.is_empty():
			continue
		pw.take_damage(dmg * falloff, owner, weapon, false, pw.global_position + Vector3.UP)
