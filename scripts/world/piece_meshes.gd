class_name PieceMeshes
extends RefCounted
## Low-poly meshes for build pieces. Vertex colours are light greyscale
## patterns; the material colour (or MultiMesh instance colour) tints them.

enum Kind { WALL, FLOOR, RAMP, CONE }
enum Mat { WOOD, BRICK, METAL }

const MAT_TINT := [Color(0.86, 0.6, 0.36), Color(0.72, 0.7, 0.68), Color(0.62, 0.7, 0.78)]
const MAT_NAMES := ["Wood", "Stone", "Metal"]
const MAX_HP := [150.0, 300.0, 500.0]   # per material
const BUILD_TIME := [4.0, 8.0, 14.0]
const START_HP_FRAC := 0.1

static var _cache := {}


static func get_mesh(kind: int, mat: int, edit := 0) -> ArrayMesh:
	var key := "%d_%d_%d" % [kind, mat, edit]
	if _cache.has(key):
		return _cache[key]
	var mb := MeshBuilder.new()
	match kind:
		Kind.WALL:
			if edit == 0:
				_wall(mb, mat)
			else:
				_wall_edited(mb, mat, edit)
		Kind.FLOOR:
			if edit == 0:
				_floor(mb, mat)
			else:
				_floor_edited(mb, mat, edit)
		Kind.RAMP:
			_ramp(mb, mat)
		Kind.CONE:
			_cone(mb, mat)
	var m := mb.build()
	_cache[key] = m
	return m


static func _shade(i: int, a := 1.0, b := 0.86) -> Color:
	var v := a if i % 2 == 0 else b
	return Color(v, v, v)


## Wall local frame: x 0..TILE, y 0..LEVEL, z centred on 0.
static func _wall(mb: MeshBuilder, mat: int) -> void:
	var T := Cfg.TILE
	var L := Cfg.LEVEL
	var th := Cfg.PIECE_THICK
	match mat:
		Mat.WOOD:
			var n := 6
			for i in n:
				var h := L / n
				mb.box(Vector3(T * 0.5, h * (i + 0.5), 0), Vector3(T - 0.04, h - 0.05, th), _shade(i, 1.0, 0.84))
			# cross braces
			mb.box(Vector3(0.12, L * 0.5, th * 0.5 + 0.03), Vector3(0.22, L, 0.06), Color(0.7, 0.7, 0.7))
			mb.box(Vector3(T - 0.12, L * 0.5, th * 0.5 + 0.03), Vector3(0.22, L, 0.06), Color(0.7, 0.7, 0.7))
		Mat.BRICK:
			mb.box(Vector3(T * 0.5, L * 0.5, 0), Vector3(T, L, th * 0.7), Color(0.55, 0.55, 0.55))
			var rows := 6
			for r in rows:
				var h := L / rows
				var cols := 4
				var w := T / cols
				var off := 0.0 if r % 2 == 0 else w * 0.5
				for c in cols + 1:
					var x0 := clampf(c * w - off, 0.0, T)
					var x1 := clampf((c + 1) * w - off, 0.0, T)
					if x1 - x0 < 0.05:
						continue
					var shade := 0.9 + 0.1 * float((r * 7 + c * 3) % 3) / 2.0
					mb.box(Vector3((x0 + x1) * 0.5, h * (r + 0.5), 0), Vector3(x1 - x0 - 0.06, h - 0.06, th), Color(shade, shade, shade))
		Mat.METAL:
			_corrugated(mb, Vector3.ZERO, T, L, th)
			mb.box(Vector3(T * 0.5, 0.08, 0), Vector3(T, 0.16, th + 0.04), Color(0.7, 0.7, 0.7))
			mb.box(Vector3(T * 0.5, L - 0.08, 0), Vector3(T, 0.16, th + 0.04), Color(0.7, 0.7, 0.7))


## Corrugated sheet with smooth sine profile on both faces.
static func _corrugated(mb: MeshBuilder, origin: Vector3, w: float, h: float, th: float) -> void:
	var waves := 10
	var steps := waves * 4
	var amp := th * 0.35
	for side in 2:
		var sgn := 1.0 if side == 0 else -1.0
		for i in steps:
			var x0 := w * i / steps
			var x1 := w * (i + 1) / steps
			var a0 := TAU * waves * i / steps
			var a1 := TAU * waves * (i + 1) / steps
			var z0 := sgn * (th * 0.3 + amp * sin(a0))
			var z1 := sgn * (th * 0.3 + amp * sin(a1))
			var n0 := Vector3(-amp * cos(a0) * TAU * waves / w * sgn, 0, sgn).normalized()
			var n1 := Vector3(-amp * cos(a1) * TAU * waves / w * sgn, 0, sgn).normalized()
			var c := Color(0.95, 0.95, 0.95)
			var p00 := origin + Vector3(x0, 0, z0)
			var p01 := origin + Vector3(x0, h, z0)
			var p10 := origin + Vector3(x1, 0, z1)
			var p11 := origin + Vector3(x1, h, z1)
			if side == 0:
				mb._add(p00, n0, c); mb._add(p01, n0, c); mb._add(p10, n1, c)
				mb._add(p10, n1, c); mb._add(p01, n0, c); mb._add(p11, n1, c)
			else:
				mb._add(p00, n0, c); mb._add(p10, n1, c); mb._add(p01, n0, c)
				mb._add(p10, n1, c); mb._add(p11, n1, c); mb._add(p01, n0, c)
	mb.box(origin + Vector3(0.03, h * 0.5, 0), Vector3(0.06, h, th), Color(0.8, 0.8, 0.8))
	mb.box(origin + Vector3(w - 0.03, h * 0.5, 0), Vector3(0.06, h, th), Color(0.8, 0.8, 0.8))


## 3x3 cell grid, bit (row*3+col) set = removed; row 0 is the bottom.
static func _wall_edited(mb: MeshBuilder, mat: int, mask: int) -> void:
	var T := Cfg.TILE
	var L := Cfg.LEVEL
	var cw := T / 3.0
	var ch := L / 3.0
	for row in 3:
		for col in 3:
			if mask & (1 << (row * 3 + col)):
				continue
			var shade := 0.95 if (row + col) % 2 == 0 else 0.85
			mb.box(Vector3(cw * (col + 0.5), ch * (row + 0.5), 0), Vector3(cw, ch, Cfg.PIECE_THICK), Color(shade, shade, shade))
			# trim lines to read as the material
			if mat == Mat.WOOD:
				mb.box(Vector3(cw * (col + 0.5), ch * (row + 0.5), 0), Vector3(cw - 0.02, 0.04, Cfg.PIECE_THICK + 0.02), Color(0.7, 0.7, 0.7))
			elif mat == Mat.METAL:
				mb.box(Vector3(cw * (col + 0.5), ch * (row + 0.5), 0), Vector3(0.05, ch - 0.02, Cfg.PIECE_THICK + 0.03), Color(0.75, 0.75, 0.75))


## Floor local frame: x,z 0..TILE, y centred on 0.
static func _floor(mb: MeshBuilder, mat: int) -> void:
	var T := Cfg.TILE
	var th := Cfg.PIECE_THICK
	match mat:
		Mat.WOOD:
			var n := 6
			for i in n:
				var w := T / n
				mb.box(Vector3(w * (i + 0.5), 0, T * 0.5), Vector3(w - 0.04, th, T - 0.02), _shade(i, 1.0, 0.86))
		Mat.BRICK:
			mb.box(Vector3(T * 0.5, -0.02, T * 0.5), Vector3(T, th * 0.8, T), Color(0.55, 0.55, 0.55))
			for i in 4:
				for j in 4:
					var s := 0.88 + 0.12 * float((i * 5 + j * 3) % 3) / 2.0
					mb.box(Vector3(T / 4 * (i + 0.5), 0.0, T / 4 * (j + 0.5)), Vector3(T / 4 - 0.07, th, T / 4 - 0.07), Color(s, s, s))
		Mat.METAL:
			mb.box(Vector3(T * 0.5, 0, T * 0.5), Vector3(T, th, T), Color(0.92, 0.92, 0.92))
			for i in 5:
				for j in 5:
					mb.box(Vector3(T / 5 * (i + 0.5), th * 0.5 + 0.015, T / 5 * (j + 0.5)), Vector3(0.36, 0.03, 0.1) if (i + j) % 2 == 0 else Vector3(0.1, 0.03, 0.36), Color(0.75, 0.75, 0.75))


static func _floor_edited(mb: MeshBuilder, _mat: int, mask: int) -> void:
	var h := Cfg.TILE * 0.5
	for i in 2:
		for j in 2:
			if mask & (1 << (j * 2 + i)):
				continue
			var s := 0.95 if (i + j) % 2 == 0 else 0.86
			mb.box(Vector3(h * (i + 0.5), 0, h * (j + 0.5)), Vector3(h, Cfg.PIECE_THICK, h), Color(s, s, s))


## Ramp local frame: rises along +z from y=0 (z=0) to y=LEVEL (z=TILE).
static func _ramp(mb: MeshBuilder, mat: int) -> void:
	var T := Cfg.TILE
	var L := Cfg.LEVEL
	var th := Cfg.PIECE_THICK
	var angle := atan2(L, T)
	var length := sqrt(T * T + L * L)
	var old := mb.xf
	mb.xf = Transform3D(Basis(Vector3.RIGHT, -angle), Vector3(0, 0, 0))
	if mat == Mat.WOOD:
		var steps := 8
		for i in steps:
			var sl := length / steps
			mb.box(Vector3(T * 0.5, 0, sl * (i + 0.5)), Vector3(T - 0.04, th, sl - 0.05), _shade(i, 1.0, 0.86))
			mb.box(Vector3(T * 0.5, th * 0.5 + 0.04, sl * (i + 0.85)), Vector3(T - 0.3, 0.08, 0.12), Color(0.75, 0.75, 0.75))
	elif mat == Mat.BRICK:
		mb.box(Vector3(T * 0.5, -0.03, length * 0.5), Vector3(T, th * 0.8, length), Color(0.55, 0.55, 0.55))
		for i in 6:
			for j in 3:
				var s := 0.88 + 0.12 * float((i + j * 2) % 3) / 2.0
				mb.box(Vector3(T / 3 * (j + 0.5), 0, length / 6 * (i + 0.5)), Vector3(T / 3 - 0.07, th, length / 6 - 0.07), Color(s, s, s))
	else:
		mb.box(Vector3(T * 0.5, 0, length * 0.5), Vector3(T, th, length), Color(0.92, 0.92, 0.92))
		for i in 7:
			mb.box(Vector3(T * 0.5, th * 0.5 + 0.02, length / 7 * (i + 0.5)), Vector3(T - 0.4, 0.04, 0.1), Color(0.72, 0.72, 0.72))
	mb.xf = old


## Cone (pyramid) local frame: base x,z 0..TILE at y=0, apex at centre y=LEVEL*0.5.
static func _cone(mb: MeshBuilder, _mat: int) -> void:
	var T := Cfg.TILE
	var apex := Vector3(T * 0.5, Cfg.LEVEL * 0.5, T * 0.5)
	var c := [Vector3(0, 0, 0), Vector3(T, 0, 0), Vector3(T, 0, T), Vector3(0, 0, T)]
	for i in 4:
		var a: Vector3 = c[i]
		var b: Vector3 = c[(i + 1) % 4]
		var s := 0.95 if i % 2 == 0 else 0.85
		mb.tri(a, b, apex, Color(s, s, s))                    # outside
		mb.tri(a, apex, b, Color(s * 0.7, s * 0.7, s * 0.7))  # underside
	# rim
	mb.box(Vector3(T * 0.5, 0.06, 0.06), Vector3(T, 0.12, 0.12), Color(0.75, 0.75, 0.75))
	mb.box(Vector3(T * 0.5, 0.06, T - 0.06), Vector3(T, 0.12, 0.12), Color(0.75, 0.75, 0.75))
	mb.box(Vector3(0.06, 0.06, T * 0.5), Vector3(0.12, 0.12, T), Color(0.75, 0.75, 0.75))
	mb.box(Vector3(T - 0.06, 0.06, T * 0.5), Vector3(0.12, 0.12, T), Color(0.75, 0.75, 0.75))
