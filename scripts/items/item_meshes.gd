class_name ItemMeshes
extends RefCounted
## Low-poly meshes for weapons (held and dropped), consumables, ammo, chest,
## pickaxe, glider and the drop bus. Weapons point along -Z, grip at origin.

static var _cache := {}

const DARK := Color(0.16, 0.17, 0.19)
const GREY := Color(0.42, 0.44, 0.48)


static func get_mesh(id: String, rarity := 0) -> ArrayMesh:
	var key := "%s_%d" % [id, rarity]
	if _cache.has(key):
		return _cache[key]
	var mb := MeshBuilder.new()
	var accent: Color = Cfg.RARITY_COLORS[clampi(rarity, 0, 4)]
	match id:
		"ar": _ar(mb, accent)
		"pump": _pump(mb, accent)
		"tac": _tac(mb, accent)
		"smg": _smg(mb, accent)
		"pistol": _pistol(mb, accent)
		"sniper": _sniper(mb, accent)
		"rocket": _rocket(mb, accent)
		"bandage": _bandage(mb)
		"medkit": _medkit(mb)
		"mini": _potion(mb, 0.65)
		"shieldpot": _potion(mb, 1.0)
		"ammo": _ammo_box(mb)
		"chest": _chest_base(mb)
		"chest_lid": _chest_lid(mb)
		"pickaxe": _pickaxe(mb, rarity)
		"glider": _glider(mb, rarity)
		"bus": _bus(mb)
		"balloon": _balloon(mb)
		"mats": _mats(mb, rarity)
	var m := mb.build()
	_cache[key] = m
	return m


static func _barrel(mb: MeshBuilder, from: Vector3, length: float, r: float, col: Color) -> void:
	var old := mb.xf
	mb.xf = old * Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), from)
	mb.cylinder(Vector3.ZERO, length, r, r, 8, col)
	mb.xf = old


static func _ar(mb: MeshBuilder, a: Color) -> void:
	mb.box(Vector3(0, 0.08, -0.15), Vector3(0.08, 0.14, 0.55), GREY)
	mb.box(Vector3(0, 0.12, 0.28), Vector3(0.07, 0.12, 0.34), a)               # stock
	mb.box(Vector3(0, 0.15, -0.12), Vector3(0.05, 0.05, 0.3), DARK)             # rail
	_barrel(mb, Vector3(0, 0.09, -0.42), 0.36, 0.022, DARK)
	mb.box(Vector3(0, -0.04, -0.1), Vector3(0.05, 0.18, 0.09), DARK)            # mag
	mb.box(Vector3(0, -0.05, 0.05), Vector3(0.05, 0.14, 0.06), DARK)            # grip
	mb.box(Vector3(0, 0.07, -0.33), Vector3(0.09, 0.08, 0.16), a)               # handguard
	mb.sphere(Vector3(0, 0.2, -0.1), Vector3(0.035, 0.035, 0.08), 2, 6, DARK)  # sight


static func _pump(mb: MeshBuilder, a: Color) -> void:
	_barrel(mb, Vector3(0, 0.1, -0.2), 0.62, 0.035, DARK)
	_barrel(mb, Vector3(0, 0.05, -0.2), 0.5, 0.03, GREY)
	mb.box(Vector3(0, 0.07, -0.42), Vector3(0.08, 0.07, 0.18), a)              # pump grip
	mb.box(Vector3(0, 0.08, -0.08), Vector3(0.08, 0.13, 0.26), GREY)
	mb.box(Vector3(0, 0.04, 0.22), Vector3(0.07, 0.12, 0.38), Color(0.55, 0.35, 0.2))
	mb.box(Vector3(0, -0.05, 0.05), Vector3(0.05, 0.13, 0.06), DARK)


static func _tac(mb: MeshBuilder, a: Color) -> void:
	_barrel(mb, Vector3(0, 0.1, -0.18), 0.5, 0.04, DARK)
	mb.box(Vector3(0, 0.08, -0.06), Vector3(0.09, 0.15, 0.32), a)
	mb.box(Vector3(0, 0.07, 0.2), Vector3(0.06, 0.1, 0.25), GREY)
	mb.box(Vector3(0, -0.05, 0.03), Vector3(0.05, 0.13, 0.06), DARK)
	mb.box(Vector3(0, 0.04, -0.4), Vector3(0.07, 0.06, 0.14), DARK)


static func _smg(mb: MeshBuilder, a: Color) -> void:
	mb.box(Vector3(0, 0.08, -0.08), Vector3(0.08, 0.13, 0.36), a)
	_barrel(mb, Vector3(0, 0.1, -0.26), 0.16, 0.025, DARK)
	mb.box(Vector3(0, -0.07, -0.08), Vector3(0.045, 0.22, 0.07), DARK)
	mb.box(Vector3(0, -0.04, 0.06), Vector3(0.05, 0.13, 0.06), DARK)
	mb.box(Vector3(0, 0.1, 0.17), Vector3(0.03, 0.05, 0.2), GREY)


static func _pistol(mb: MeshBuilder, a: Color) -> void:
	mb.box(Vector3(0, 0.08, -0.06), Vector3(0.05, 0.08, 0.22), GREY)
	mb.box(Vector3(0, 0.02, 0.02), Vector3(0.045, 0.14, 0.07), a)
	_barrel(mb, Vector3(0, 0.08, -0.17), 0.04, 0.018, DARK)


static func _sniper(mb: MeshBuilder, a: Color) -> void:
	_barrel(mb, Vector3(0, 0.1, -0.3), 0.75, 0.025, DARK)
	mb.box(Vector3(0, 0.08, -0.1), Vector3(0.08, 0.12, 0.45), a)
	mb.box(Vector3(0, 0.05, 0.3), Vector3(0.07, 0.14, 0.38), Color(0.5, 0.33, 0.2))
	_barrel(mb, Vector3(0, 0.22, -0.02), 0.32, 0.04, DARK)                      # scope
	mb.box(Vector3(0, -0.05, 0.05), Vector3(0.05, 0.13, 0.06), DARK)


static func _rocket(mb: MeshBuilder, a: Color) -> void:
	_barrel(mb, Vector3(0, 0.12, 0.45), 1.1, 0.1, Color(0.35, 0.42, 0.3))
	_barrel(mb, Vector3(0, 0.12, -0.55), 0.12, 0.12, a)
	mb.box(Vector3(0, -0.02, 0.05), Vector3(0.05, 0.16, 0.07), DARK)
	mb.box(Vector3(-0.1, 0.2, 0.0), Vector3(0.04, 0.1, 0.18), DARK)


static func _bandage(mb: MeshBuilder) -> void:
	var old := mb.xf
	mb.xf = Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3(0.1, 0.1, 0))
	mb.cylinder(Vector3.ZERO, 0.2, 0.1, 0.1, 10, Color(0.95, 0.93, 0.88), true, Color(0.85, 0.82, 0.75))
	mb.xf = old


static func _medkit(mb: MeshBuilder) -> void:
	mb.box(Vector3(0, 0.12, 0), Vector3(0.42, 0.24, 0.3), Color(0.95, 0.95, 0.95))
	mb.box(Vector3(0, 0.245, 0), Vector3(0.22, 0.01, 0.06), Color(0.9, 0.15, 0.15))
	mb.box(Vector3(0, 0.245, 0), Vector3(0.06, 0.01, 0.2), Color(0.9, 0.15, 0.15))
	mb.box(Vector3(0, 0.29, 0), Vector3(0.16, 0.04, 0.04), DARK)


static func _potion(mb: MeshBuilder, size: float) -> void:
	var blue := Color(0.3, 0.7, 1.0)
	mb.sphere(Vector3(0, 0.12 * size, 0), Vector3(0.12, 0.13, 0.12) * size, 4, 10, blue)
	mb.cylinder(Vector3(0, 0.22 * size, 0), 0.1 * size, 0.04 * size, 0.04 * size, 8, Color(0.8, 0.9, 1.0))
	mb.cylinder(Vector3(0, 0.32 * size, 0), 0.04 * size, 0.05 * size, 0.05 * size, 8, Color(0.55, 0.35, 0.2))


static func _ammo_box(mb: MeshBuilder) -> void:
	mb.box(Vector3(0, 0.22, 0), Vector3(0.8, 0.44, 0.45), Color(0.33, 0.42, 0.25))
	mb.box(Vector3(0, 0.46, 0), Vector3(0.82, 0.06, 0.47), Color(0.25, 0.32, 0.18))
	mb.box(Vector3(0, 0.3, 0.23), Vector3(0.4, 0.1, 0.02), Color(0.9, 0.8, 0.3))


static func _chest_base(mb: MeshBuilder) -> void:
	var wood := Color(0.55, 0.32, 0.16)
	var gold := Color(1.0, 0.78, 0.25)
	mb.box(Vector3(0, 0.3, 0), Vector3(1.1, 0.6, 0.65), wood)
	for x: float in [-0.53, 0.53]:
		mb.box(Vector3(x, 0.3, 0), Vector3(0.06, 0.62, 0.67), gold)
	mb.box(Vector3(0, 0.03, 0), Vector3(1.12, 0.06, 0.67), gold)


## Lid pivots at its back-bottom edge (z = +0.325).
static func _chest_lid(mb: MeshBuilder) -> void:
	var wood := Color(0.6, 0.36, 0.18)
	var gold := Color(1.0, 0.78, 0.25)
	# half-cylinder lid along x
	var seg := 8
	for i in seg:
		var a0 := PI * i / seg
		var a1 := PI * (i + 1) / seg
		var p0 := Vector3(0, sin(a0) * 0.3, -0.325 + 0.325 * (1.0 - cos(a0)))
		var p1 := Vector3(0, sin(a1) * 0.3, -0.325 + 0.325 * (1.0 - cos(a1)))
		var n0 := Vector3(0, sin(a0), -cos(a0))
		var n1 := Vector3(0, sin(a1), -cos(a1))
		var l := Vector3(-0.55, 0, 0)
		var r := Vector3(0.55, 0, 0)
		var c := wood if i % 2 == 0 else wood.lightened(0.06)
		mb._add(p0 + l, n0, c); mb._add(p1 + l, n1, c); mb._add(p0 + r, n0, c)
		mb._add(p0 + r, n0, c); mb._add(p1 + l, n1, c); mb._add(p1 + r, n1, c)
		# end caps
		mb.tri(Vector3(-0.55, 0, 0), p0 + l, p1 + l, gold)
		mb.tri(Vector3(0.55, 0, 0), p1 + r, p0 + r, gold)
	mb.box(Vector3(0, 0.18, -0.34), Vector3(0.14, 0.18, 0.04), gold)
	# shift so the hinge (back edge) sits at the origin
	for i in mb.verts.size():
		mb.verts[i] += Vector3(0, 0, -0.325)


static func _pickaxe(mb: MeshBuilder, style: int) -> void:
	var handle: Color = [Color(0.5, 0.33, 0.18), Color(0.25, 0.25, 0.28), Color(0.85, 0.3, 0.6)][style % 3]
	var head: Color = [Color(0.7, 0.72, 0.76), Color(1.0, 0.75, 0.25), Color(0.35, 0.9, 0.95)][style % 3]
	mb.limb(Vector3(0, -0.15, 0), Vector3(0, 0.75, 0), 0.03, 0.03, handle, 6)
	# curved head: two tapered arcs
	for s: float in [-1.0, 1.0]:
		var prev := Vector3(0, 0.72, 0)
		for i in 4:
			var t := float(i + 1) / 4.0
			var p := Vector3(0, 0.72 + sin(t * PI * 0.5) * 0.08 - t * t * 0.12, s * t * 0.34)
			mb.limb(prev, p, 0.05 * (1.0 - t * 0.6), 0.05 * (1.0 - t * 0.7), head, 6)
			prev = p


static func _glider(mb: MeshBuilder, style: int) -> void:
	var cols := [Color(0.95, 0.35, 0.3), Color(0.3, 0.6, 1.0), Color(1.0, 0.8, 0.2), Color(0.5, 0.9, 0.5), Color(0.8, 0.4, 0.95)]
	var c: Color = cols[style % cols.size()]
	# curved canopy: arc of panels
	var seg := 8
	for i in seg:
		var a0 := lerpf(-1.1, 1.1, float(i) / seg)
		var a1 := lerpf(-1.1, 1.1, float(i + 1) / seg)
		var p0 := Vector3(sin(a0) * 1.8, cos(a0) * 0.7 + 2.0, 0)
		var p1 := Vector3(sin(a1) * 1.8, cos(a1) * 0.7 + 2.0, 0)
		var f := Vector3(0, 0, -0.9)
		var b := Vector3(0, -0.15, 0.7)
		var col := c if i % 2 == 0 else c.lightened(0.35)
		mb.quad(p0 + b, p1 + b, p1 + f, p0 + f, col)
		mb.quad(p0 + f, p1 + f, p1 + b, p0 + b, col.darkened(0.2))
	for s: float in [-1.0, 1.0]:
		mb.limb(Vector3(s * 0.25, 0.6, 0), Vector3(s * 1.6, 2.2, 0), 0.02, 0.02, DARK, 4)
	mb.limb(Vector3(-0.3, 0.6, 0), Vector3(0.3, 0.6, 0), 0.03, 0.03, DARK, 5)


static func _bus(mb: MeshBuilder) -> void:
	var blue := Color(0.25, 0.55, 0.95)
	var white := Color(0.95, 0.95, 0.97)
	mb.box(Vector3(0, 1.6, 0), Vector3(3.0, 2.4, 11.0), blue)
	mb.box(Vector3(0, 3.0, 0), Vector3(2.9, 0.5, 10.8), white)
	for i in 6:
		mb.box(Vector3(1.51, 2.2, -4.0 + i * 1.6), Vector3(0.04, 0.9, 1.2), Color(0.3, 0.4, 0.5))
		mb.box(Vector3(-1.51, 2.2, -4.0 + i * 1.6), Vector3(0.04, 0.9, 1.2), Color(0.3, 0.4, 0.5))
	for z: float in [-3.8, 3.8]:
		for x: float in [-1.4, 1.4]:
			var old := mb.xf
			mb.xf = Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3(x + 0.2 * signf(x), 0.55, z))
			mb.cylinder(Vector3.ZERO, 0.4, 0.55, 0.55, 10, DARK)
			mb.xf = old


static func _balloon(mb: MeshBuilder) -> void:
	mb.sphere(Vector3(0, 9.0, 0), Vector3(5.5, 6.0, 5.5), 7, 12, Color(0.3, 0.6, 1.0))
	mb.sphere(Vector3(0, 9.0, 0), Vector3(5.6, 1.2, 5.6), 3, 12, Color(1.0, 0.85, 0.3))
	for i in 4:
		var a := TAU * i / 4.0
		mb.limb(Vector3(cos(a) * 3.8, 4.5, sin(a) * 3.8), Vector3(cos(a) * 1.4, 0.4, sin(a) * 1.4), 0.04, 0.04, DARK, 4)


static func _mats(mb: MeshBuilder, mat: int) -> void:
	var cols := [Color(0.8, 0.55, 0.3), Color(0.65, 0.65, 0.67), Color(0.6, 0.68, 0.78)]
	for i in 3:
		mb.box(Vector3(0, 0.08 + i * 0.13, 0), Vector3(0.5 - i * 0.06, 0.12, 0.3), cols[mat % 3].lightened(i * 0.06))
