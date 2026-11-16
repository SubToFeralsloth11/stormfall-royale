class_name IslandBuilder
extends RefCounted
## Populates the island: POI buildings made of destructible grid pieces,
## landmark props, trees/rocks/bushes, cars, chests and floor loot.

const K := PieceMeshes.Kind
const M := PieceMeshes.Mat

var terrain: Terrain
var st: Structures
var loot: Loot
var rng := RandomNumberGenerator.new()
var _occupied := {}            # Vector2i grid cell -> true (building footprints)
var _prop_mat := MeshBuilder.vc_material(0.85)
var _paint := [
	Color(0.95, 0.92, 0.85), Color(0.75, 0.88, 1.0), Color(1.0, 0.85, 0.7), Color(0.85, 1.0, 0.8),
	Color(1.0, 0.95, 0.65), Color(0.95, 0.75, 0.75), Color(0.85, 0.8, 1.0),
]
var _roofs := [Color(0.8, 0.3, 0.25), Color(0.3, 0.45, 0.75), Color(0.35, 0.35, 0.4), Color(0.45, 0.65, 0.35)]
var piece_count := 0
var chest_count := 0


func _init(t: Terrain, s: Structures, l: Loot, seed_value: int) -> void:
	terrain = t
	st = s
	loot = l
	rng.seed = seed_value


func build_all() -> void:
	for i in Terrain.POIS.size():
		_build_poi(i)
	_scatter_nature()
	_scatter_outskirts()
	st.batcher.finalize()


# ------------------------------------------------------------------ POIs

func _build_poi(i: int) -> void:
	var poi: Dictionary = Terrain.POIS[i]
	var level := roundi(terrain.pad_heights[i] / Cfg.LEVEL)
	var c: Vector2 = poi.pos
	match poi.type:
		"city":
			_layout(c, poi.r, level, 34.0, func(cell: Vector2i) -> void:
				if cell.distance_to(_cell2(c)) < 9 and rng.randf() < 0.85:
					_tower(cell, level, rng.randi_range(3, 4), rng.randi_range(5, 9))
				else:
					_house(cell, level, 3, 3, rng.randi_range(2, 3), M.BRICK))
			_props_ring(c, poi.r, "lamp", 14, false)
			_props_ring(c, poi.r * 0.9, "car", 10, true)
		"suburb":
			_layout(c, poi.r, level, 30.0, func(cell: Vector2i) -> void:
				_house(cell, level, rng.randi_range(2, 3), rng.randi_range(2, 3), rng.randi_range(1, 2), M.WOOD))
			_props_ring(c, poi.r * 0.8, "car", 6, true)
			_props_ring(c, poi.r, "oak", 10, true)
		"town":
			_layout(c, poi.r, level, 30.0, func(cell: Vector2i) -> void:
				if rng.randf() < 0.4:
					_shop(cell, level)
				else:
					_house(cell, level, 2, 3, rng.randi_range(1, 2), M.WOOD if rng.randf() < 0.6 else M.BRICK))
			_props_ring(c, poi.r * 0.7, "car", 7, true)
			_props_ring(c, poi.r * 0.8, "lamp", 8, false)
		"farm":
			var cell := _cell2(c)
			_barn(cell + Vector2i(-2, -2), level)
			_house(cell + Vector2i(6, -6), level, 3, 2, 2, M.WOOD)
			_house(cell + Vector2i(-9, 5), level, 2, 2, 1, M.WOOD)
			_landmark("silo", Vector3(c.x + 26, 0, c.y - 4), 0.0, CylinderShape3D, 3.2, 16.0, 800.0, M.METAL)
			_landmark("silo", Vector3(c.x + 26, 0, c.y + 6), 0.0, CylinderShape3D, 3.2, 16.0, 800.0, M.METAL)
			_props_ring(c, poi.r * 0.6, "hay", 16, true)
		"factory":
			var cell := _cell2(c)
			_shed(cell + Vector2i(-6, -4), level, 8, 6, 3)
			_shed(cell + Vector2i(5, 3), level, 5, 5, 2)
			_tower(cell + Vector2i(-6, 6), level, 3, 4)
			_landmark("chimney", Vector3(c.x + 30, 0, c.y - 30), 0.0, CylinderShape3D, 2.0, 26.0, 1200.0, M.BRICK)
			_landmark("chimney", Vector3(c.x + 38, 0, c.y - 22), 0.0, CylinderShape3D, 2.0, 26.0, 1200.0, M.BRICK)
			for k in 10:
				var p := c + Vector2(rng.randf_range(-90, 90), rng.randf_range(-90, 90))
				if not _occupied.has(_cell2(p)):
					_box_prop("container", p, 400.0, M.METAL, Vector3(2.44, 2.6, 6.06), [Color(0.85, 0.3, 0.25), Color(0.25, 0.5, 0.85), Color(0.3, 0.65, 0.35), Color(0.95, 0.7, 0.2)][k % 4])
			_props_ring(c, poi.r * 0.6, "barrel", 14, true)
		"beach":
			_layout(c, poi.r, level, 28.0, func(cell: Vector2i) -> void:
				_house(cell, level, 2, 2, 1, M.WOOD))
			_props_ring(c, poi.r * 1.1, "palm", 18, true)
			_props_ring(c, poi.r * 1.3, "umbrella", 12, false)
		"cabin":
			var cell := _cell2(c)
			_house(cell, level, 3, 3, 2, M.WOOD)
			_house(cell + Vector2i(5, 3), level, 2, 2, 1, M.WOOD)
			_house(cell + Vector2i(-5, 2), level, 2, 2, 1, M.WOOD)
			_props_ring(c, poi.r, "pine", 14, true)
		"quarry":
			for k in 26:
				var p := c + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(10, poi.r)
				_rock(p, rng.randf_range(1.4, 3.2), 3 + k % 3)
			var cell := _cell2(c)
			_shed(cell + Vector2i(-2, -2), level, 4, 3, 1)
			_props_ring(c, poi.r * 0.5, "crate", 10, true)
		"lighthouse":
			var p3 := Vector3(c.x, 0, c.y)
			_landmark("lighthouse", p3, 0.0, CylinderShape3D, 3.4, 30.0, 2000.0, M.BRICK)
			_house(_cell2(c) + Vector2i(3, 2), level, 2, 2, 1, M.WOOD)
			loot.add_chest(Vector3(c.x + 4.5, terrain.height_at(c.x + 4.5, c.y) + 0.0, c.y), 0.0)
			chest_count += 1
		"stadium":
			for k in 12:
				var a := TAU * k / 12.0
				var xf := Transform3D(Basis(Vector3.UP, -a), Vector3(c.x, terrain.pad_heights[i], c.y))
				var mesh := PropMeshes.get_mesh("stadium_ring", 6)
				var shape := mesh.create_trimesh_shape()
				st.add_prop("stadium_%d" % k, mesh, _prop_mat, xf, shape, Transform3D.IDENTITY, 99999.0, -1, 0, Color.WHITE, 2200.0)
			# centre field floors + small press box
			var cell := _cell2(c)
			_shed(cell + Vector2i(-2, -2), level, 4, 4, 1)
	# floor loot + ammo boxes scattered across the POI pad
	for k in int(poi.r / 7.0):
		var p := c + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(0, poi.r)
		var h := terrain.height_at(p.x, p.y)
		if h > 0.8 and not _occupied.has(_cell2(p)):
			if rng.randf() < 0.25:
				loot.add_chest(Vector3(p.x, h, p.y), rng.randf() * TAU, true)
			else:
				loot.spawn_floor_loot(Vector3(p.x, h, p.y))


static func _cell2(p: Vector2) -> Vector2i:
	return Vector2i(floori(p.x / Cfg.TILE), floori(p.y / Cfg.TILE))


## Places buildings on a jittered grid inside radius r with street gaps.
func _layout(c: Vector2, r: float, _level: int, spacing: float, fn: Callable) -> void:
	var n := int(r / spacing)
	for gx in range(-n, n + 1):
		for gz in range(-n, n + 1):
			var p := c + Vector2(gx, gz) * spacing + Vector2(rng.randf_range(-3, 3), rng.randf_range(-3, 3))
			if p.distance_to(c) > r or rng.randf() < 0.12:
				continue
			if absf(terrain.height_at(p.x, p.y) - terrain.height_at(c.x, c.y)) > 1.0:
				continue
			fn.call(_cell2(p))


func _free(cell: Vector2i, w: int, d: int) -> bool:
	for x in range(-1, w + 1):
		for z in range(-1, d + 1):
			if _occupied.has(cell + Vector2i(x, z)):
				return false
	return true


func _claim(cell: Vector2i, w: int, d: int) -> void:
	for x in w:
		for z in d:
			_occupied[cell + Vector2i(x, z)] = true


func _piece(kind: int, cell: Vector3i, dir: int, mat: int, tint: Color, edit := 0) -> void:
	if st.place(kind, cell, dir, mat, -1, true, tint, true, edit):
		piece_count += 1


## Perimeter wall with optional windows/door.
func _walls_ring(x0: int, z0: int, y: int, w: int, d: int, mat: int, tint: Color, door: bool) -> void:
	var door_at := rng.randi() % w if door else -1
	for x in w:
		var e := 0
		if x == door_at:
			e = (1 << 1) | (1 << 4)
		elif rng.randf() < 0.45:
			e = 1 << 4
		_piece(K.WALL, Vector3i(x0 + x, y, z0 + d), 0, mat, tint, e)   # front (+z)
		_piece(K.WALL, Vector3i(x0 + x, y, z0), 0, mat, tint, (1 << 4) if rng.randf() < 0.4 else 0)
	for z in d:
		_piece(K.WALL, Vector3i(x0, y, z0 + z), 1, mat, tint, (1 << 4) if rng.randf() < 0.4 else 0)
		_piece(K.WALL, Vector3i(x0 + w, y, z0 + z), 1, mat, tint, (1 << 4) if rng.randf() < 0.4 else 0)


func _house(cell: Vector2i, level: int, w: int, d: int, floors: int, mat: int) -> void:
	if not _free(cell, w, d):
		return
	_claim(cell, w, d)
	var tint: Color = _paint[rng.randi() % _paint.size()] if mat == M.WOOD else Color(0.95, 0.93, 0.9)
	var wood_tint := tint * Color(0.95, 0.85, 0.7) if mat == M.WOOD else tint
	var roof: Color = _roofs[rng.randi() % _roofs.size()]
	var stair_cell := Vector2i(cell.x, cell.y)
	for f in floors:
		var y := level + f
		for x in w:
			for z in d:
				var cc := Vector2i(cell.x + x, cell.y + z)
				if f > 0 and cc == stair_cell:
					continue   # stairwell opening
				_piece(K.FLOOR, Vector3i(cc.x, y, cc.y), 0, M.WOOD, Color(0.85, 0.65, 0.45))
		_walls_ring(cell.x, cell.y, y, w, d, mat, wood_tint, f == 0)
		if f < floors - 1:
			_piece(K.RAMP, Vector3i(stair_cell.x, y, stair_cell.y), 2, M.WOOD, Color(0.8, 0.6, 0.4))
		# loot spots
		var lx := cell.x + rng.randi_range(0, w - 1)
		var lz := cell.y + rng.randi_range(0, d - 1)
		if Vector2i(lx, lz) != stair_cell or f == 0:
			var p := Cfg.cell_center(Vector3i(lx, y, lz)) + Vector3(rng.randf_range(-1, 1), 0.12, rng.randf_range(-1, 1))
			if rng.randf() < 0.5:
				loot.add_chest(p, rng.randi() % 4 * PI * 0.5)
				chest_count += 1
			else:
				loot.spawn_floor_loot(p)
	# gable roof from ramps
	var ry := level + floors
	for x in w:
		for z in d:
			var dir := 2 if z < d / 2.0 - 0.01 else 0
			if d % 2 == 1 and z == d / 2:
				_piece(K.FLOOR, Vector3i(cell.x + x, ry, cell.y + z), 0, M.BRICK, roof)
			else:
				_piece(K.RAMP, Vector3i(cell.x + x, ry, cell.y + z), dir, M.BRICK, roof)
	# attic chest
	if rng.randf() < 0.35:
		var p := Cfg.cell_center(Vector3i(cell.x, ry, cell.y)) + Vector3(0, 0.12, 0)
		loot.add_chest(p, 0.0)
		chest_count += 1


func _tower(cell: Vector2i, level: int, size: int, floors: int) -> void:
	if not _free(cell, size, size):
		return
	_claim(cell, size, size)
	var mat := M.BRICK if rng.randf() < 0.6 else M.METAL
	var tint: Color = [Color(0.95, 0.9, 0.82), Color(0.8, 0.85, 0.95), Color(0.95, 0.8, 0.7), Color(0.85, 0.85, 0.85)][rng.randi() % 4]
	for f in floors:
		var y := level + f
		var stair := Vector2i(cell.x + (f % 2) * (size - 1), cell.y)
		for x in size:
			for z in size:
				var cc := Vector2i(cell.x + x, cell.y + z)
				if f > 0 and cc == Vector2i(cell.x + ((f - 1) % 2) * (size - 1), cell.y):
					continue
				_piece(K.FLOOR, Vector3i(cc.x, y, cc.y), 0, M.BRICK, Color(0.75, 0.73, 0.7))
		for x in size:
			_piece(K.WALL, Vector3i(cell.x + x, y, cell.y + size), 0, mat, tint, ((1 << 1) | (1 << 4)) if (f == 0 and x == size / 2) else (1 << 4))
			_piece(K.WALL, Vector3i(cell.x + x, y, cell.y), 0, mat, tint, 1 << 4)
		for z in size:
			_piece(K.WALL, Vector3i(cell.x, y, cell.y + z), 1, mat, tint, 1 << 4)
			_piece(K.WALL, Vector3i(cell.x + size, y, cell.y + z), 1, mat, tint, 1 << 4)
		if f < floors - 1:
			_piece(K.RAMP, Vector3i(stair.x, y, stair.y), 2, M.WOOD, Color(0.8, 0.6, 0.4))
		if rng.randf() < 0.45:
			var p := Cfg.cell_center(Vector3i(cell.x + 1, y, cell.y + size - 1)) + Vector3(0, 0.12, 0)
			if rng.randf() < 0.5:
				loot.add_chest(p, PI)
				chest_count += 1
			else:
				loot.spawn_floor_loot(p)
	for x in size:
		for z in size:
			_piece(K.FLOOR, Vector3i(cell.x + x, level + floors, cell.y + z), 0, M.BRICK, Color(0.55, 0.55, 0.58))
	loot.add_chest(Cfg.cell_center(Vector3i(cell.x + 1, level + floors, cell.y + 1)) + Vector3(0, 0.12, 0), 0.0)
	chest_count += 1


func _shop(cell: Vector2i, level: int) -> void:
	if not _free(cell, 3, 2):
		return
	_claim(cell, 3, 2)
	var tint: Color = [Color(1, 0.9, 0.6), Color(0.7, 0.9, 1), Color(1, 0.75, 0.75)][rng.randi() % 3]
	for x in 3:
		for z in 2:
			_piece(K.FLOOR, Vector3i(cell.x + x, level, cell.y + z), 0, M.BRICK, Color(0.8, 0.8, 0.8))
			_piece(K.FLOOR, Vector3i(cell.x + x, level + 1, cell.y + z), 0, M.BRICK, Color(0.5, 0.5, 0.55))
	for x in 3:
		_piece(K.WALL, Vector3i(cell.x + x, level, cell.y + 2), 0, M.BRICK, tint, (1 << 1) | (1 << 4) if x == 1 else (1 << 3) | (1 << 4) | (1 << 5))
		_piece(K.WALL, Vector3i(cell.x + x, level, cell.y), 0, M.BRICK, tint)
	for z in 2:
		_piece(K.WALL, Vector3i(cell.x, level, cell.y + z), 1, M.BRICK, tint)
		_piece(K.WALL, Vector3i(cell.x + 3, level, cell.y + z), 1, M.BRICK, tint)
	loot.spawn_floor_loot(Cfg.cell_center(Vector3i(cell.x + 1, level, cell.y)) + Vector3(0, 0.12, 0))
	if rng.randf() < 0.5:
		loot.add_chest(Cfg.cell_center(Vector3i(cell.x + 2, level, cell.y)) + Vector3(0, 0.12, 0), 0.0)
		chest_count += 1


func _barn(cell: Vector2i, level: int) -> void:
	if not _free(cell, 4, 3):
		return
	_claim(cell, 4, 3)
	var red := Color(0.95, 0.45, 0.4)
	for f in 2:
		for x in 4:
			for z in 3:
				if f == 1 and z == 1:
					continue   # open loft middle
				_piece(K.FLOOR, Vector3i(cell.x + x, level + f, cell.y + z), 0, M.WOOD, Color(0.85, 0.65, 0.45))
		_walls_ring(cell.x, cell.y, level + f, 4, 3, M.WOOD, red, f == 0)
	_piece(K.RAMP, Vector3i(cell.x, level, cell.y + 1), 1, M.WOOD, Color(0.8, 0.6, 0.4))
	for x in 4:
		_piece(K.RAMP, Vector3i(cell.x + x, level + 2, cell.y), 2, M.BRICK, Color(0.45, 0.45, 0.5))
		_piece(K.FLOOR, Vector3i(cell.x + x, level + 3, cell.y + 1), 0, M.BRICK, Color(0.45, 0.45, 0.5))
		_piece(K.RAMP, Vector3i(cell.x + x, level + 2, cell.y + 2), 0, M.BRICK, Color(0.45, 0.45, 0.5))
	for k in 2:
		loot.add_chest(Cfg.cell_center(Vector3i(cell.x + 1 + k * 2, level + 1, cell.y)) + Vector3(0, 0.12, 0), 0.0)
		chest_count += 1


func _shed(cell: Vector2i, level: int, w: int, d: int, h: int) -> void:
	if not _free(cell, w, d):
		return
	_claim(cell, w, d)
	var tint := Color(0.85, 0.88, 0.92)
	for x in w:
		for z in d:
			_piece(K.FLOOR, Vector3i(cell.x + x, level, cell.y + z), 0, M.BRICK, Color(0.6, 0.6, 0.62))
			_piece(K.FLOOR, Vector3i(cell.x + x, level + h, cell.y + z), 0, M.METAL, Color(0.6, 0.65, 0.7))
	for y in h:
		_walls_ring(cell.x, cell.y, level + y, w, d, M.METAL, tint, y == 0)
	# catwalk ramp inside
	if h > 1:
		_piece(K.RAMP, Vector3i(cell.x + 1, level, cell.y + 1), 1, M.METAL, Color(0.6, 0.65, 0.7))
		for x in range(2, w - 1):
			_piece(K.FLOOR, Vector3i(cell.x + x, level + 1, cell.y + 1), 0, M.METAL, Color(0.6, 0.65, 0.7))
	for k in maxi(1, w / 3):
		var p := Cfg.cell_center(Vector3i(cell.x + rng.randi_range(0, w - 1), level, cell.y + rng.randi_range(0, d - 1))) + Vector3(0, 0.12, 0)
		if rng.randf() < 0.5:
			loot.add_chest(p, 0.0)
			chest_count += 1
		else:
			loot.spawn_floor_loot(p)


# ------------------------------------------------------------------ props

func _landmark(kind: String, p: Vector3, yaw: float, shape_type: Variant, radius: float, height: float, hp: float, mat: int) -> void:
	p.y = terrain.height_at(p.x, p.z) - 0.2
	var xf := Transform3D(Basis(Vector3.UP, yaw), p)
	var shape: Shape3D
	if shape_type == CylinderShape3D:
		var cs := CylinderShape3D.new()
		cs.radius = radius
		cs.height = height
		shape = cs
	st.add_prop(kind, PropMeshes.get_mesh(kind), _prop_mat, xf, shape, Transform3D(Basis.IDENTITY, Vector3(0, height * 0.5, 0)), hp, mat, 6, Color.WHITE, 2400.0)
	_occupied[_cell2(Vector2(p.x, p.z))] = true


func _box_prop(kind: String, p: Vector2, hp: float, mat: int, size: Vector3, tint: Color) -> void:
	var h := terrain.height_at(p.x, p.y)
	if h < 0.8:
		return
	var yaw := rng.randf() * TAU
	var b := Basis(Vector3.UP, yaw)
	var xf := Transform3D(b, Vector3(p.x, h - 0.05, p.y))
	var bs := BoxShape3D.new()
	bs.size = size
	st.add_prop(kind, PropMeshes.get_mesh(kind), _prop_mat, xf, bs, Transform3D(Basis.IDENTITY, Vector3(0, size.y * 0.5, 0)), hp, mat, 8, tint, 700.0)


func _props_ring(c: Vector2, r: float, kind: String, count: int, collide: bool) -> void:
	for k in count:
		var p := c + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(r * 0.25, r)
		if _occupied.has(_cell2(p)):
			continue
		_prop(kind, p, collide)


func _prop(kind: String, p: Vector2, collide := true) -> void:
	var h := terrain.height_at(p.x, p.y)
	if h < 0.5 and kind != "palm":
		return
	if h < -0.2:
		return
	var yaw := rng.randf() * TAU
	var s := rng.randf_range(0.85, 1.25)
	var xf := Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * s), Vector3(p.x, h - 0.1, p.y))
	var shape: Shape3D = null
	var sxf := Transform3D.IDENTITY
	var hp := 100.0
	var mat := -1
	var yld := 0
	var tint := Color.WHITE
	var vis := 1500.0
	match kind:
		"pine", "oak", "palm":
			var cs := CylinderShape3D.new()
			cs.radius = 0.45
			cs.height = 7.0
			shape = cs
			sxf = Transform3D(Basis.IDENTITY, Vector3(0, 3.5, 0))
			hp = 300.0
			mat = M.WOOD
			yld = 8
		"bush":
			hp = 50.0
			mat = M.WOOD
			yld = 4
			vis = 300.0
			collide = false
		"car":
			var bs := BoxShape3D.new()
			bs.size = Vector3(1.9, 1.6, 4.3)
			shape = bs
			sxf = Transform3D(Basis.IDENTITY, Vector3(0, 0.8, 0))
			hp = 600.0
			mat = M.METAL
			yld = 10
			tint = [Color(0.9, 0.25, 0.2), Color(0.25, 0.5, 0.9), Color(0.95, 0.85, 0.3), Color(0.3, 0.7, 0.4), Color(0.85, 0.85, 0.88)][rng.randi() % 5]
			xf = Transform3D(Basis(Vector3.UP, yaw), xf.origin)
			vis = 600.0
		"crate", "hay", "barrel":
			var bs := BoxShape3D.new()
			bs.size = Vector3(1.4, 1.4, 1.4)
			shape = bs
			sxf = Transform3D(Basis.IDENTITY, Vector3(0, 0.7, 0))
			hp = 120.0
			mat = M.WOOD if kind != "barrel" else M.METAL
			yld = 6
			vis = 350.0
		"lamp":
			var cs := CylinderShape3D.new()
			cs.radius = 0.15
			cs.height = 6.0
			shape = cs
			sxf = Transform3D(Basis.IDENTITY, Vector3(0, 3, 0))
			hp = 150.0
			mat = M.METAL
			yld = 4
			vis = 400.0
		"umbrella":
			hp = 60.0
			mat = M.WOOD
			yld = 2
			vis = 300.0
	if not collide:
		shape = null
	st.add_prop(kind, PropMeshes.get_mesh(kind, rng.randi() % 3), _prop_mat, xf, shape, sxf, hp, mat, yld, tint, vis, kind != "bush")


func _rock(p: Vector2, s: float, variant: int) -> void:
	var h := terrain.height_at(p.x, p.y)
	if h < -1.0:
		return
	var xf := Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * s), Vector3(p.x, h - 0.3 * s, p.y))
	var sph := SphereShape3D.new()
	sph.radius = 1.6
	st.add_prop("rock", PropMeshes.get_mesh("rock", variant), _prop_mat, xf, sph, Transform3D(Basis.IDENTITY, Vector3(0, 0.6, 0)), 250.0 * s, M.BRICK, 7, Color.WHITE, 1200.0)


func _scatter_nature() -> void:
	var attempts := 9000
	var placed := 0
	for k in attempts:
		var p := Vector2(rng.randf_range(-1450, 1450), rng.randf_range(-1450, 1450))
		var h := terrain.height_at(p.x, p.y)
		if h < 2.5:
			if h > 0.5 and rng.randf() < 0.08:
				_prop("palm", p)
			continue
		if terrain.poi_at(p) >= 0 or _occupied.has(_cell2(p)):
			continue
		var n := terrain.normal_at(p.x, p.y)
		if n.y < 0.8:
			if rng.randf() < 0.15:
				_rock(p, rng.randf_range(1.0, 2.5), rng.randi() % 3)
			continue
		var forest := (terrain._noise.get_noise_2d(p.x * 2.0, p.y * 2.0) + 1.0) * 0.5
		var roll := rng.randf()
		if roll < forest * 0.55:
			_prop("pine" if h > 45.0 or rng.randf() < 0.45 else "oak", p)
			placed += 1
		elif roll < forest * 0.55 + 0.12:
			_prop("bush", p, false)
		elif roll < forest * 0.55 + 0.16:
			_rock(p, rng.randf_range(0.7, 1.8), rng.randi() % 3)


## Lone farmhouses and loot along the countryside, like the unnamed spots in BR.
func _scatter_outskirts() -> void:
	var made := 0
	var tries := 0
	while made < 22 and tries < 400:
		tries += 1
		var p := Vector2(rng.randf_range(-1250, 1250), rng.randf_range(-1250, 1250))
		var h := terrain.height_at(p.x, p.y)
		if h < 4.0 or terrain.poi_at(p) >= 0 or terrain.normal_at(p.x, p.y).y < 0.97:
			continue
		var level := roundi(h / Cfg.LEVEL)
		if absf(level * Cfg.LEVEL - h) > 1.2:
			continue
		var before := piece_count
		_house(_cell2(p), level, 2, 2, 1, M.WOOD)
		if piece_count > before:
			made += 1
