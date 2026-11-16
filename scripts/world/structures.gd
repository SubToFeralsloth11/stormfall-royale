class_name Structures
extends Node3D
## Owns every destructible thing in the world: build pieces (player-built and
## POI buildings) and harvestable props. Handles placement rules on the
## 5.12 m x 3.84 m grid, damage, editing, and structural-integrity collapse.

signal destroyed(d: Destructible)

const K := PieceMeshes.Kind

class Destructible:
	extends RefCounted
	var id := 0
	var is_piece := true
	var kind := 0             # PieceMeshes.Kind for pieces
	var prop := ""            # prop type for props
	var cell := Vector3i.ZERO
	var dir := 0              # wall axis (0/1) or ramp direction (0..3)
	var mat := 0              # PieceMeshes.Mat (harvest material)
	var hp := 100.0
	var max_hp := 100.0
	var building := false
	var build_rate := 0.0     # hp per second while building
	var harvest := false      # gives materials when pickaxed
	var harvest_yield := 0
	var owner_id := -1
	var edit := 0
	var tint := Color.WHITE
	var xf := Transform3D.IDENTITY
	var aabb := AABB()
	var key := ""
	var body: StaticBody3D
	var mesh_inst: MeshInstance3D
	var batch := -1
	var alive := true
	var center: Vector3:
		get: return aabb.get_center()

var terrain: Terrain
var batcher: Batcher
var _next_id := 1
var _slots := {}                 # key -> Destructible
var _spatial := {}               # Vector3i -> Array[Destructible]
var _building: Array[Destructible] = []
var _mat_cache := {}
var _static_mat := MeshBuilder.vc_material(0.8)
var _collapse_queue: Array = []  # [time, Destructible]
var _time := 0.0
var _wobbles := {}               # id -> [Destructible, t]  (batched props shake when hit)


func _init(t: Terrain) -> void:
	terrain = t
	batcher = Batcher.new()
	add_child(batcher)


func material_for(tint: Color) -> StandardMaterial3D:
	var k := tint.to_html()
	if not _mat_cache.has(k):
		var m := MeshBuilder.vc_material(0.8)
		m.albedo_color = tint
		_mat_cache[k] = m
	return _mat_cache[k]


# ------------------------------------------------------------------ geometry

static func slot_key(kind: int, cell: Vector3i, dir: int) -> String:
	match kind:
		K.WALL: return "W%d,%d,%d,%d" % [cell.x, cell.y, cell.z, dir]
		K.FLOOR: return "F%d,%d,%d" % [cell.x, cell.y, cell.z]
		K.RAMP: return "R%d,%d,%d" % [cell.x, cell.y, cell.z]
	return "C%d,%d,%d" % [cell.x, cell.y, cell.z]


## Transform from piece-local mesh space to world.
static func piece_xf(kind: int, cell: Vector3i, dir: int) -> Transform3D:
	var o := Cfg.cell_origin(cell)
	match kind:
		K.WALL:
			if dir == 0:
				return Transform3D(Basis.IDENTITY, o)
			return Transform3D(Basis(Vector3.UP, -PI * 0.5), o)
		K.RAMP:
			var c := Cfg.cell_center(cell)
			var ang: float = [PI, PI * 0.5, 0.0, -PI * 0.5][dir]
			var b := Basis(Vector3.UP, ang)
			return Transform3D(b, c) * Transform3D(Basis.IDENTITY, Vector3(-Cfg.TILE * 0.5, 0, -Cfg.TILE * 0.5))
	return Transform3D(Basis.IDENTITY, o)


static func piece_aabb(kind: int, cell: Vector3i, dir: int) -> AABB:
	var o := Cfg.cell_origin(cell)
	var T := Cfg.TILE
	var L := Cfg.LEVEL
	var h := Cfg.PIECE_THICK * 0.5
	match kind:
		K.WALL:
			if dir == 0:
				return AABB(o + Vector3(0, 0, -h), Vector3(T, L, h * 2))
			return AABB(o + Vector3(-h, 0, 0), Vector3(h * 2, L, T))
		K.FLOOR:
			return AABB(o + Vector3(0, -h, 0), Vector3(T, h * 2, T))
		K.CONE:
			return AABB(o, Vector3(T, L * 0.5, T))
	return AABB(o, Vector3(T, L, T))


# ------------------------------------------------------------------ placement

func is_free(kind: int, cell: Vector3i, dir: int) -> bool:
	return not _slots.has(slot_key(kind, cell, dir))


func get_slot(kind: int, cell: Vector3i, dir: int) -> Destructible:
	return _slots.get(slot_key(kind, cell, dir))


## Fortnite-style rule: a new piece must touch the ground or an existing piece,
## and must not be entirely buried.
func can_place(kind: int, cell: Vector3i, dir: int) -> bool:
	if not is_free(kind, cell, dir):
		return false
	var box := piece_aabb(kind, cell, dir)
	var top := box.position.y + box.size.y
	var c := box.get_center()
	if top < terrain.height_at(c.x, c.z) - 0.3 and kind != K.FLOOR:
		return false
	if absf(c.x) > Terrain.EXTENT * 0.5 - 20.0 or absf(c.z) > Terrain.EXTENT * 0.5 - 20.0:
		return false
	if _touches_ground(box):
		return true
	for n in _query(box.grow(0.06)):
		if n.is_piece:
			return true
	return false


func place(kind: int, cell: Vector3i, dir: int, mat: int, owner_id := -1, instant := false, tint := Color(-1, 0, 0), static_batch := false, edit := 0) -> Destructible:
	var key := slot_key(kind, cell, dir)
	if _slots.has(key):
		return null
	var d := Destructible.new()
	d.id = _next_id
	_next_id += 1
	d.kind = kind
	d.cell = cell
	d.dir = dir
	d.mat = mat
	d.owner_id = owner_id
	d.edit = edit
	d.key = key
	d.max_hp = PieceMeshes.MAX_HP[mat]
	d.tint = PieceMeshes.MAT_TINT[mat] if tint.r < 0.0 else tint
	d.xf = piece_xf(kind, cell, dir)
	d.aabb = piece_aabb(kind, cell, dir)
	d.harvest = static_batch
	d.harvest_yield = 5 if mat == 0 else 4
	if instant:
		d.hp = d.max_hp
	else:
		d.hp = d.max_hp * PieceMeshes.START_HP_FRAC
		d.building = true
		d.build_rate = (d.max_hp - d.hp) / PieceMeshes.BUILD_TIME[mat]
		_building.append(d)
	_slots[key] = d
	_index(d)
	_make_body(d)
	if static_batch and edit == 0:
		d.batch = batcher.add("p%d_%d" % [kind, mat], PieceMeshes.get_mesh(kind, mat), _static_mat, d.xf, d.tint, 900.0)
	else:
		_make_mesh(d, not instant)
	return d


func _make_mesh(d: Destructible, pop: bool) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = PieceMeshes.get_mesh(d.kind, d.mat, d.edit)
	mi.material_override = material_for(d.tint)
	mi.visibility_range_end = 700.0
	add_child(mi)
	mi.global_transform = d.xf
	d.mesh_inst = mi
	if pop:
		# quick "assemble" pop so builds read clearly
		var c := d.aabb.get_center()
		var start := Transform3D(Basis().scaled(Vector3.ONE * 0.6), c) * Transform3D(Basis.IDENTITY, -c) * d.xf
		mi.global_transform = start
		var tw := mi.create_tween()
		tw.tween_property(mi, "global_transform", d.xf, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _make_body(d: Destructible) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = Cfg.L_BUILD
	body.collision_mask = 0
	body.set_meta("dest", d)
	add_child(body)
	body.global_transform = d.xf
	_add_shapes(d, body)
	d.body = body


func _add_shapes(d: Destructible, body: StaticBody3D) -> void:
	var T := Cfg.TILE
	var L := Cfg.LEVEL
	var th := Cfg.PIECE_THICK
	match d.kind:
		K.WALL:
			if d.edit == 0:
				_box_shape(body, Vector3(T * 0.5, L * 0.5, 0), Vector3(T, L, th))
			else:
				for row in 3:
					for col in 3:
						if not (d.edit & (1 << (row * 3 + col))):
							_box_shape(body, Vector3(T / 3 * (col + 0.5), L / 3 * (row + 0.5), 0), Vector3(T / 3, L / 3, th))
		K.FLOOR:
			if d.edit == 0:
				_box_shape(body, Vector3(T * 0.5, 0, T * 0.5), Vector3(T, th, T))
			else:
				for i in 2:
					for j in 2:
						if not (d.edit & (1 << (j * 2 + i))):
							_box_shape(body, Vector3(T / 4 * (2 * i + 1), 0, T / 4 * (2 * j + 1)), Vector3(T / 2, th, T / 2))
		K.RAMP:
			var ang := atan2(L, T)
			var length := sqrt(T * T + L * L)
			var cs := CollisionShape3D.new()
			var bs := BoxShape3D.new()
			bs.size = Vector3(T, th, length)
			cs.shape = bs
			cs.transform = Transform3D(Basis(Vector3.RIGHT, -ang), Vector3(T * 0.5, L * 0.5, T * 0.5))
			body.add_child(cs)
		K.CONE:
			var cs := CollisionShape3D.new()
			var cv := ConvexPolygonShape3D.new()
			cv.points = PackedVector3Array([Vector3(0, 0, 0), Vector3(T, 0, 0), Vector3(T, 0, T), Vector3(0, 0, T), Vector3(T * 0.5, L * 0.5, T * 0.5)])
			cs.shape = cv
			body.add_child(cs)


static func _box_shape(body: StaticBody3D, pos: Vector3, size: Vector3) -> void:
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	cs.position = pos
	body.add_child(cs)


## Props (trees, rocks, cars...) share the damage pipeline but not integrity.
func add_prop(prop: String, mesh: Mesh, mat: Material, xf: Transform3D, col_shape: Shape3D, shape_xf: Transform3D, hp: float, harvest_mat: int, yield_per_hit: int, tint := Color.WHITE, vis_end := 1400.0, shadow := true) -> Destructible:
	var d := Destructible.new()
	d.id = _next_id
	_next_id += 1
	d.is_piece = false
	d.prop = prop
	d.hp = hp
	d.max_hp = hp
	d.mat = harvest_mat
	d.harvest = harvest_mat >= 0
	d.harvest_yield = yield_per_hit
	d.xf = xf
	d.tint = tint
	d.aabb = xf * mesh.get_aabb()
	if col_shape:
		var body := StaticBody3D.new()
		body.collision_layer = Cfg.L_WORLD
		body.collision_mask = 0
		body.set_meta("dest", d)
		var cs := CollisionShape3D.new()
		cs.shape = col_shape
		cs.transform = shape_xf
		body.add_child(cs)
		add_child(body)
		body.global_transform = xf
		d.body = body
	d.batch = batcher.add(prop, mesh, mat, xf, tint, vis_end, shadow)
	return d


# ------------------------------------------------------------------ damage

func _process(delta: float) -> void:
	_time += delta
	for i in range(_building.size() - 1, -1, -1):
		var d := _building[i]
		if not d.alive:
			_building.remove_at(i)
			continue
		d.hp = minf(d.max_hp, d.hp + d.build_rate * delta)
		if d.hp >= d.max_hp:
			d.building = false
			_building.remove_at(i)
	for id: int in _wobbles.keys():
		var w: Array = _wobbles[id]
		var d: Destructible = w[0]
		w[1] += delta
		if not d.alive:
			_wobbles.erase(id)
			continue
		var k: float = w[1] / 0.35
		if k >= 1.0:
			batcher.set_instance_transform(d.batch, d.xf)
			_wobbles.erase(id)
			continue
		var ang := sin(k * PI * 4.0) * (1.0 - k) * 0.06
		batcher.set_instance_transform(d.batch, Transform3D(d.xf.basis.rotated(Vector3(1, 0, 0.6).normalized(), ang), d.xf.origin))
	while not _collapse_queue.is_empty() and _collapse_queue[0][0] <= _time:
		var item: Array = _collapse_queue.pop_front()
		var d: Destructible = item[1]
		if d.alive:
			destroy(d, false)


## Returns true if destroyed.
func damage(d: Destructible, amount: float) -> bool:
	if not d.alive:
		return false
	d.hp -= amount
	if d.mesh_inst and d.is_piece:
		_shake(d)
	elif d.batch >= 0 and not d.is_piece:
		_wobbles[d.id] = [d, 0.0]
	if d.hp <= 0.0:
		destroy(d)
		return true
	return false


func _shake(d: Destructible) -> void:
	var mi := d.mesh_inst
	var tw := mi.create_tween()
	var off := Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)) * 0.05
	tw.tween_property(mi, "global_transform", Transform3D(d.xf.basis, d.xf.origin + off), 0.04)
	tw.tween_property(mi, "global_transform", d.xf, 0.06)


func destroy(d: Destructible, check_integrity := true) -> void:
	if not d.alive:
		return
	d.alive = false
	if d.body:
		d.body.queue_free()
	if d.mesh_inst:
		d.mesh_inst.queue_free()
	if d.batch >= 0:
		batcher.hide_instance(d.batch)
	if d.is_piece:
		_slots.erase(d.key)
		_unindex(d)
	Fx.debris(d.center, d.tint, d.is_piece)
	destroyed.emit(d)
	if d.is_piece and check_integrity:
		_check_integrity(d)


## Replace geometry after an edit (walls: 3x3 mask, floors: 2x2 mask, ramps: dir).
func apply_edit(d: Destructible, edit: int, new_dir := -1) -> void:
	if not d.alive:
		return
	if d.kind == K.RAMP and new_dir >= 0 and new_dir != d.dir:
		_slots.erase(d.key)
		_unindex(d)
		d.dir = new_dir
		d.key = slot_key(d.kind, d.cell, d.dir)
		d.xf = piece_xf(d.kind, d.cell, d.dir)
		_slots[d.key] = d
		_index(d)
	else:
		d.edit = edit
	if d.batch >= 0:
		batcher.hide_instance(d.batch)
		d.batch = -1
	if d.mesh_inst:
		d.mesh_inst.queue_free()
	d.body.queue_free()
	_make_body(d)
	_make_mesh(d, false)
	Sfx.play_at("edit", d.center)


# ------------------------------------------------------------------ integrity

func _cells_for(box: AABB) -> Array[Vector3i]:
	var out: Array[Vector3i] = []
	var a := Cfg.cell_of(box.position)
	var b := Cfg.cell_of(box.end)
	for x in range(a.x, b.x + 1):
		for y in range(a.y, b.y + 1):
			for z in range(a.z, b.z + 1):
				out.append(Vector3i(x, y, z))
	return out


func _index(d: Destructible) -> void:
	for c in _cells_for(d.aabb.grow(0.02)):
		if not _spatial.has(c):
			_spatial[c] = []
		_spatial[c].append(d)


func _unindex(d: Destructible) -> void:
	for c in _cells_for(d.aabb.grow(0.02)):
		if _spatial.has(c):
			_spatial[c].erase(d)
			if _spatial[c].is_empty():
				_spatial.erase(c)


func _query(box: AABB) -> Array:
	var seen := {}
	var out := []
	for c in _cells_for(box):
		for d: Destructible in _spatial.get(c, []):
			if d.alive and not seen.has(d.id) and d.aabb.intersects(box):
				seen[d.id] = true
				out.append(d)
	return out


func neighbors(d: Destructible) -> Array:
	var out := []
	for n: Destructible in _query(d.aabb.grow(0.06)):
		if n != d:
			out.append(n)
	return out


func _touches_ground(box: AABB) -> bool:
	var pts := [box.get_center(), box.position, Vector3(box.end.x, 0, box.position.z), Vector3(box.position.x, 0, box.end.z), box.end]
	for p: Vector3 in pts:
		if box.position.y <= terrain.height_at(p.x, p.z) + 0.3:
			return true
	return false


func is_grounded(d: Destructible) -> bool:
	return _touches_ground(d.aabb)


func _check_integrity(removed: Destructible) -> void:
	var visited := {}
	for start: Destructible in neighbors(removed):
		if visited.has(start.id):
			continue
		var comp := []
		var supported := false
		var queue := [start]
		var local := {start.id: true}
		while not queue.is_empty():
			var cur: Destructible = queue.pop_back()
			comp.append(cur)
			if is_grounded(cur) or comp.size() > 800:
				supported = true
				break
			for n: Destructible in neighbors(cur):
				if not local.has(n.id):
					local[n.id] = true
					queue.append(n)
		for id: int in local:
			visited[id] = true
		if not supported:
			# collapse bottom-up-ish with a short cascade like the real thing
			comp.sort_custom(func(a: Destructible, b: Destructible) -> bool: return a.aabb.position.y < b.aabb.position.y)
			for i in comp.size():
				_collapse_queue.append([_time + 0.05 + i * 0.03, comp[i]])
			_collapse_queue.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])


func pieces_near(p: Vector3, r: float) -> Array:
	return _query(AABB(p - Vector3.ONE * r, Vector3.ONE * r * 2.0))
