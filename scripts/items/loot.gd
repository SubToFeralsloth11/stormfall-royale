class_name Loot
extends Node3D
## Floor loot, dropped items, chests and ammo boxes, with a spatial index so
## pawns can find nearby interactables without per-item Areas.

const CELL := 32.0

class Pickup:
	extends RefCounted
	var id := 0
	var data := {}      # {"item": {...}} or {"ammo": type, "count": n} or {"mats": m, "count": n}
	var node: Node3D
	var pos := Vector3.ZERO
	var alive := true

class Chest:
	extends RefCounted
	var id := 0
	var node: Node3D
	var lid: Node3D
	var pos := Vector3.ZERO
	var opened := false
	var ammo_box := false
	var light: OmniLight3D
	var sparkle: GPUParticles3D

var terrain: Terrain
var rng := RandomNumberGenerator.new()
var _pickups := {}            # id -> Pickup
var _grid := {}               # Vector2i -> Array[Pickup]
var chests: Array[Chest] = []
var _chest_grid := {}
var _next := 1
var _ring_mats := []
var _beam_mats := []
var _item_mat := MeshBuilder.vc_material(0.6, 0.15)


func _init(t: Terrain, seed_value: int) -> void:
	terrain = t
	rng.seed = seed_value
	for r in 5:
		var c: Color = Cfg.RARITY_COLORS[r]
		var ring := StandardMaterial3D.new()
		ring.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		ring.albedo_color = Color(c.r, c.g, c.b, 0.55)
		ring.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		ring.cull_mode = BaseMaterial3D.CULL_DISABLED
		_ring_mats.append(ring)
		var beam := ring.duplicate() as StandardMaterial3D
		beam.albedo_color = Color(c.r, c.g, c.b, 0.18)
		beam.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_beam_mats.append(beam)


static func _key(p: Vector3) -> Vector2i:
	return Vector2i(floori(p.x / CELL), floori(p.z / CELL))


# ------------------------------------------------------------------ pickups

func spawn(data: Dictionary, pos: Vector3, from := Vector3.INF) -> Pickup:
	var pk := Pickup.new()
	pk.id = _next
	_next += 1
	pk.data = data
	pk.pos = pos
	pk.node = _make_visual(data)
	add_child(pk.node)
	if from != Vector3.INF:
		pk.node.position = from
		var tw := pk.node.create_tween()
		tw.tween_method(func(t: float) -> void:
			if is_instance_valid(pk.node):
				pk.node.position = from.lerp(pos, t) + Vector3(0, sin(t * PI) * 1.2, 0), 0.0, 1.0, 0.45)
	else:
		pk.node.position = pos
	_pickups[pk.id] = pk
	var k := _key(pos)
	if not _grid.has(k):
		_grid[k] = []
	_grid[k].append(pk)
	return pk


func _make_visual(data: Dictionary) -> Node3D:
	var root := Node3D.new()
	var mi := MeshInstance3D.new()
	var rarity := 0
	if data.has("item"):
		var item: Dictionary = data.item
		rarity = item.rarity
		mi.mesh = ItemMeshes.get_mesh(item.id, item.rarity)
		if Items.is_weapon(item):
			mi.rotation = Vector3(0, randf() * TAU, PI * 0.5)
			mi.position = Vector3(0, 0.25, 0)
			mi.scale = Vector3.ONE * 1.3
	elif data.has("ammo"):
		mi.mesh = ItemMeshes.get_mesh("ammo")
		mi.scale = Vector3.ONE * 0.6
	else:
		mi.mesh = ItemMeshes.get_mesh("mats", data.mats)
	mi.material_override = _item_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	root.set_meta("spin", mi)
	if data.has("item"):
		var ring := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.75
		cyl.bottom_radius = 0.75
		cyl.height = 0.02
		cyl.radial_segments = 16
		ring.mesh = cyl
		ring.material_override = _ring_mats[rarity]
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ring.position.y = 0.03
		root.add_child(ring)
		if rarity >= 1:
			var beam := MeshInstance3D.new()
			var bc := CylinderMesh.new()
			bc.top_radius = 0.05
			bc.bottom_radius = 0.45
			bc.height = 2.2 + rarity * 0.6
			bc.radial_segments = 10
			bc.cap_top = false
			bc.cap_bottom = false
			beam.mesh = bc
			beam.material_override = _beam_mats[rarity]
			beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			beam.position.y = bc.height * 0.5
			root.add_child(beam)
	var vis := 160.0 if data.has("item") else 80.0
	for c in root.get_children():
		(c as GeometryInstance3D).visibility_range_end = vis
	return root


func remove(pk: Pickup) -> void:
	if not pk.alive:
		return
	pk.alive = false
	_pickups.erase(pk.id)
	var k := _key(pk.pos)
	if _grid.has(k):
		_grid[k].erase(pk)
	pk.node.queue_free()


func pickups_near(p: Vector3, r: float) -> Array:
	var out := []
	var k := _key(p)
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			for pk: Pickup in _grid.get(k + Vector2i(dx, dz), []):
				if pk.alive and pk.pos.distance_to(p) <= r:
					out.append(pk)
	return out


func nearest_pickup(p: Vector3, r: float, items_only := true) -> Pickup:
	var best: Pickup = null
	var bd := r
	for pk: Pickup in pickups_near(p, r):
		if items_only and not pk.data.has("item"):
			continue
		var d := pk.pos.distance_to(p)
		if d < bd:
			bd = d
			best = pk
	return best


## Weapon + its ammo, or a consumable. Used for floor loot.
func spawn_floor_loot(pos: Vector3) -> void:
	if rng.randf() < 0.62:
		var w := Items.roll_weapon(rng)
		spawn({"item": w}, pos)
		var ammo: String = Items.WEAPONS[w.id].ammo
		spawn({"ammo": ammo, "count": Items.AMMO[ammo].drop * 2}, pos + Vector3(0.9, 0, 0.3))
	else:
		spawn({"item": Items.roll_consumable(rng)}, pos)


# ------------------------------------------------------------------ chests

func add_chest(pos: Vector3, yaw: float, ammo_box := false) -> Chest:
	var ch := Chest.new()
	ch.id = _next
	_next += 1
	ch.pos = pos
	ch.ammo_box = ammo_box
	var root := Node3D.new()
	root.position = pos
	root.rotation.y = yaw
	var mat := MeshBuilder.vc_material(0.5, 0.2)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var base := MeshInstance3D.new()
	base.mesh = ItemMeshes.get_mesh("ammo" if ammo_box else "chest")
	base.material_override = mat
	base.visibility_range_end = 220.0
	root.add_child(base)
	if not ammo_box:
		var lid := Node3D.new()
		lid.position = Vector3(0, 0.6, 0.325)
		var lm := MeshInstance3D.new()
		lm.mesh = ItemMeshes.get_mesh("chest_lid")
		lm.material_override = mat
		lm.visibility_range_end = 220.0
		lid.add_child(lm)
		root.add_child(lid)
		ch.lid = lid
		var light := OmniLight3D.new()
		light.light_color = Color(1.0, 0.8, 0.35)
		light.light_energy = 1.4
		light.omni_range = 3.5
		light.position = Vector3(0, 0.9, 0)
		light.distance_fade_enabled = true
		light.distance_fade_begin = 25.0
		light.distance_fade_length = 10.0
		root.add_child(light)
		ch.light = light
		ch.sparkle = _sparkles()
		ch.sparkle.position = Vector3(0, 0.7, 0)
		root.add_child(ch.sparkle)
	add_child(root)
	ch.node = root
	chests.append(ch)
	var k := _key(pos)
	if not _chest_grid.has(k):
		_chest_grid[k] = []
	_chest_grid[k].append(ch)
	return ch


func _sparkles() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = 10
	p.lifetime = 1.2
	p.visibility_range_end = 45.0
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(0.6, 0.3, 0.4)
	pm.gravity = Vector3(0, 0.6, 0)
	pm.scale_min = 0.5
	pm.scale_max = 1.0
	pm.color = Color(1.0, 0.9, 0.4)
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.06, 0.06)
	var qm := StandardMaterial3D.new()
	qm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	qm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	qm.vertex_color_use_as_albedo = true
	qm.albedo_color = Color(1, 0.95, 0.6)
	q.material = qm
	p.draw_pass_1 = q
	return p


func chests_near(p: Vector3, r: float) -> Array:
	var out := []
	var k := _key(p)
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			for ch: Chest in _chest_grid.get(k + Vector2i(dx, dz), []):
				if not ch.opened and ch.pos.distance_to(p) <= r:
					out.append(ch)
	return out


func nearest_chest(p: Vector3, r: float) -> Chest:
	var best: Chest = null
	var bd := r
	for ch: Chest in chests_near(p, r):
		var d := ch.pos.distance_to(p)
		if d < bd:
			bd = d
			best = ch
	return best


func open_chest(ch: Chest) -> void:
	if ch.opened:
		return
	ch.opened = true
	Sfx.play_at("chest_open", ch.pos)
	var fwd := ch.node.global_transform.basis.z.normalized() * -1.0
	var side := ch.node.global_transform.basis.x.normalized()
	var out := ch.pos + Vector3(0, 0.4, 0)
	var spots := [fwd * 1.6, fwd * 1.4 + side * 1.0, fwd * 1.4 - side * 1.0, fwd * 2.4 + side * 0.4]
	var drops := []
	if ch.ammo_box:
		var types := Items.AMMO.keys()
		for i in 2:
			var t: String = types[rng.randi() % 4]
			drops.append({"ammo": t, "count": Items.AMMO[t].drop * 2})
		ch.node.queue_free()
	else:
		var w := Items.roll_weapon(rng, true)
		drops.append({"item": w})
		var ammo: String = Items.WEAPONS[w.id].ammo
		drops.append({"ammo": ammo, "count": Items.AMMO[ammo].drop * 2})
		drops.append({"item": Items.roll_consumable(rng)})
		drops.append({"mats": 0, "count": 30})
		var tw := ch.lid.create_tween()
		tw.tween_property(ch.lid, "rotation:x", -1.9, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		ch.light.queue_free()
		ch.sparkle.emitting = false
	for i in drops.size():
		var target: Vector3 = out + spots[i % spots.size()]
		target.y = ground_height(target)
		spawn(drops[i], target, out)


## Ground (terrain or structure) height under p via physics, falling back to terrain.
func ground_height(p: Vector3) -> float:
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(p + Vector3(0, 1.5, 0), p + Vector3(0, -8, 0), Cfg.L_WORLD | Cfg.L_BUILD)
	var hit := space.intersect_ray(q)
	if hit:
		return hit.position.y
	return terrain.height_at(p.x, p.z)


func _process(delta: float) -> void:
	# gentle bob/spin for nearby pickups only
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var k := _key(cam.global_position)
	var t := Time.get_ticks_msec() * 0.001
	for dx in range(-2, 3):
		for dz in range(-2, 3):
			for pk: Pickup in _grid.get(k + Vector2i(dx, dz), []):
				var mi: Node3D = pk.node.get_meta("spin")
				if pk.data.has("item") and Items.is_weapon(pk.data.item):
					mi.position.y = 0.3 + sin(t * 2.0 + pk.id) * 0.06
				else:
					mi.rotation.y += delta * 1.2
