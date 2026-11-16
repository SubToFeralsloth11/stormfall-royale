class_name PropMeshes
extends RefCounted
## Stylised low-poly props with curved, smooth-shaded silhouettes.

static var _cache := {}


static func get_mesh(kind: String, variant := 0) -> ArrayMesh:
	var key := "%s_%d" % [kind, variant]
	if _cache.has(key):
		return _cache[key]
	var mb := MeshBuilder.new()
	MeshBuilder.detail = 1.6
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(key)
	match kind:
		"pine": _pine(mb, rng)
		"oak": _oak(mb, rng)
		"palm": _palm(mb, rng)
		"bush": _bush(mb, rng)
		"rock": _rock(mb, rng, variant)
		"car": _car(mb)
		"crate": _crate(mb)
		"hay": _hay(mb)
		"barrel": _barrel(mb)
		"container": _container(mb)
		"lighthouse": _lighthouse(mb)
		"silo": _silo(mb)
		"chimney": _chimney(mb)
		"stadium_ring": _stadium_ring(mb, variant)
		"umbrella": _umbrella(mb, rng)
		"lamp": _lamp(mb)
		"grass": _grass(mb, rng)
		"flower": _flower(mb, rng, variant)
		"tent": _tent(mb, variant)
		"log": _log(mb)
		"fence": _fence(mb)
		"campfire": _campfire(mb)
	MeshBuilder.detail = 1.0
	var m := mb.build()
	_cache[key] = m
	return m


static func _pine(mb: MeshBuilder, rng: RandomNumberGenerator) -> void:
	var trunk := Color(0.45, 0.3, 0.18)
	mb.cylinder(Vector3.ZERO, 3.2, 0.42, 0.3, 7, trunk)
	var g := Color(0.16, 0.45, 0.24).lerp(Color(0.22, 0.52, 0.22), rng.randf())
	var y := 2.2
	var r := 3.3
	for i in 4:
		mb.cylinder(Vector3(0, y, 0), 3.6 - i * 0.35, r, 0.0, 9, g.lightened(i * 0.06), true)
		y += 2.2
		r *= 0.74


static func _oak(mb: MeshBuilder, rng: RandomNumberGenerator) -> void:
	mb.cylinder(Vector3.ZERO, 4.0, 0.5, 0.36, 7, Color(0.5, 0.34, 0.2))
	mb.limb(Vector3(0, 3.2, 0), Vector3(1.4, 5.0, 0.3), 0.28, 0.18, Color(0.5, 0.34, 0.2), 6)
	var g := Color(0.3, 0.62, 0.22).lerp(Color(0.42, 0.7, 0.24), rng.randf())
	mb.sphere(Vector3(0, 6.2, 0), Vector3(3.4, 2.8, 3.4), 5, 9, g)
	mb.sphere(Vector3(1.9, 5.4, 0.8), Vector3(2.2, 1.9, 2.2), 4, 8, g.lightened(0.08))
	mb.sphere(Vector3(-1.6, 5.6, -1.0), Vector3(2.3, 2.0, 2.3), 4, 8, g.darkened(0.08))
	mb.sphere(Vector3(0.3, 7.8, -0.4), Vector3(2.0, 1.6, 2.0), 4, 8, g.lightened(0.12))


static func _palm(mb: MeshBuilder, rng: RandomNumberGenerator) -> void:
	var p := Vector3.ZERO
	var lean := Vector3(rng.randf_range(0.15, 0.3), 1.0, 0.0).normalized()
	for i in 6:
		var nxt := p + lean * 1.4 + Vector3(0.05 * i, 0, 0)
		mb.limb(p, nxt, 0.32 - i * 0.02, 0.3 - i * 0.02, Color(0.6, 0.45, 0.28) if i % 2 == 0 else Color(0.52, 0.38, 0.24), 6)
		p = nxt
	var leaf := Color(0.25, 0.62, 0.2)
	for k in 7:
		var a := TAU * k / 7.0
		var d := Vector3(cos(a), 0, sin(a))
		var mid := p + d * 2.0 + Vector3(0, 0.5, 0)
		var tip := p + d * 3.8 + Vector3(0, -0.9, 0)
		var side := d.cross(Vector3.UP) * 0.6
		mb.tri(p, mid + side, mid - side, leaf)
		mb.tri(p, mid - side, mid + side, leaf.darkened(0.15))
		mb.tri(mid - side, mid + side, tip, leaf)
		mb.tri(mid + side, mid - side, tip, leaf.darkened(0.15))
	mb.sphere(p + Vector3(0, -0.3, 0), Vector3.ONE * 0.35, 3, 6, Color(0.4, 0.28, 0.15))


static func _bush(mb: MeshBuilder, rng: RandomNumberGenerator) -> void:
	var g := Color(0.28, 0.58, 0.2).lerp(Color(0.36, 0.66, 0.24), rng.randf())
	mb.sphere(Vector3(0, 0.6, 0), Vector3(1.2, 0.9, 1.2), 4, 8, g)
	mb.sphere(Vector3(0.7, 0.5, 0.3), Vector3(0.8, 0.7, 0.8), 3, 7, g.lightened(0.07))
	mb.sphere(Vector3(-0.6, 0.45, -0.3), Vector3(0.8, 0.65, 0.8), 3, 7, g.darkened(0.06))


static func _rock(mb: MeshBuilder, rng: RandomNumberGenerator, variant: int) -> void:
	var noise := FastNoiseLite.new()
	noise.seed = variant * 31 + 5
	noise.frequency = 0.6
	var base := Color(0.56, 0.55, 0.55) if variant < 3 else Color(0.66, 0.34, 0.24)
	var rings := 5
	var seg := 8
	var rad := Vector3(rng.randf_range(1.6, 2.4), rng.randf_range(1.1, 1.7), rng.randf_range(1.5, 2.2))
	for r in rings:
		for s in seg:
			var corners := []
			for k: Vector2i in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 1)]:
				var polar := PI * (1.0 - float(r + k.x) / rings)
				var az := TAU * float(s + k.y) / seg
				var u := MeshBuilder._sph(polar, az)
				var disp := 1.0 + noise.get_noise_3dv(u * 2.0) * 0.28
				var p := u * rad * disp
				p.y = maxf(p.y, -0.4)
				corners.append(p)
			var shade := 0.92 + 0.08 * ((r + s) % 3) / 2.0
			mb.quad(corners[3], corners[0], corners[1], corners[2], base * shade)


static func _car(mb: MeshBuilder) -> void:
	var body := Color(0.95, 0.95, 0.95)
	var glass := Color(0.35, 0.45, 0.55)
	var dark := Color(0.15, 0.15, 0.16)
	mb.box(Vector3(0, 0.75, 0), Vector3(1.9, 0.7, 4.3), body)
	# rounded cabin: half-cylinder roof along z
	var old := mb.xf
	mb.xf = Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 1.1, 1.0))
	mb.cylinder(Vector3.ZERO, 2.4, 0.9, 0.9, 10, glass, true)
	mb.xf = old
	mb.box(Vector3(0, 1.1, -0.2), Vector3(1.86, 0.15, 2.5), body)
	for x: float in [-0.95, 0.95]:
		for z: float in [-1.4, 1.35]:
			mb.xf = Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3(x - 0.12 * signf(x), 0.38, z))
			mb.cylinder(Vector3.ZERO, 0.26, 0.38, 0.38, 10, dark)
			mb.xf = old
	mb.box(Vector3(0.6, 0.85, 2.16), Vector3(0.35, 0.18, 0.02), Color(1, 1, 0.8))
	mb.box(Vector3(-0.6, 0.85, 2.16), Vector3(0.35, 0.18, 0.02), Color(1, 1, 0.8))


static func _crate(mb: MeshBuilder) -> void:
	var w := Color(0.78, 0.58, 0.35)
	mb.box(Vector3(0, 0.6, 0), Vector3(1.2, 1.2, 1.2), w)
	for y: float in [0.08, 1.12]:
		mb.box(Vector3(0, y, 0), Vector3(1.26, 0.14, 1.26), w.darkened(0.2))


static func _hay(mb: MeshBuilder) -> void:
	var old := mb.xf
	mb.xf = Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3(0.8, 0.8, 0))
	mb.cylinder(Vector3.ZERO, 1.6, 0.8, 0.8, 10, Color(0.92, 0.8, 0.38), true, Color(0.85, 0.7, 0.3))
	mb.xf = old


static func _barrel(mb: MeshBuilder) -> void:
	mb.cylinder(Vector3.ZERO, 1.2, 0.42, 0.42, 10, Color(0.75, 0.25, 0.2))
	mb.cylinder(Vector3(0, 0.3, 0), 0.08, 0.44, 0.44, 10, Color(0.3, 0.3, 0.3), false)
	mb.cylinder(Vector3(0, 0.85, 0), 0.08, 0.44, 0.44, 10, Color(0.3, 0.3, 0.3), false)


static func _container(mb: MeshBuilder) -> void:
	var c := Color(0.95, 0.95, 0.95)
	mb.box(Vector3(0, 1.3, 0), Vector3(2.44, 2.6, 6.06), c)
	for i in 12:
		mb.box(Vector3(1.24, 1.3, -2.8 + i * 0.51), Vector3(0.06, 2.4, 0.18), c.darkened(0.15))
		mb.box(Vector3(-1.24, 1.3, -2.8 + i * 0.51), Vector3(0.06, 2.4, 0.18), c.darkened(0.15))


static func _lighthouse(mb: MeshBuilder) -> void:
	var y := 0.0
	var r := 3.6
	for i in 6:
		var h := 4.0
		var col := Color(0.95, 0.95, 0.95) if i % 2 == 0 else Color(0.85, 0.2, 0.18)
		mb.cylinder(Vector3(0, y, 0), h, r, r - 0.3, 14, col, i == 5)
		y += h
		r -= 0.3
	mb.cylinder(Vector3(0, y, 0), 0.4, r + 0.7, r + 0.7, 14, Color(0.2, 0.2, 0.22))
	mb.cylinder(Vector3(0, y + 0.4, 0), 2.4, r - 0.4, r - 0.4, 12, Color(1.0, 0.95, 0.6))
	mb.cylinder(Vector3(0, y + 2.8, 0), 1.6, r, 0.0, 12, Color(0.85, 0.2, 0.18))


static func _silo(mb: MeshBuilder) -> void:
	mb.cylinder(Vector3.ZERO, 14.0, 3.2, 3.2, 14, Color(0.82, 0.84, 0.86))
	mb.sphere(Vector3(0, 14.0, 0), Vector3(3.2, 2.4, 3.2), 4, 14, Color(0.72, 0.74, 0.78), 0.5, 1.0)
	for i in 5:
		mb.cylinder(Vector3(0, 2.0 + i * 2.8, 0), 0.15, 3.25, 3.25, 14, Color(0.6, 0.6, 0.62), false)


static func _chimney(mb: MeshBuilder) -> void:
	mb.cylinder(Vector3.ZERO, 26.0, 2.2, 1.5, 12, Color(0.7, 0.32, 0.25))
	mb.cylinder(Vector3(0, 22.0, 0), 1.0, 1.75, 1.75, 12, Color(0.95, 0.95, 0.95), false)
	mb.cylinder(Vector3(0, 26.0, 0), 0.6, 1.8, 1.8, 12, Color(0.25, 0.25, 0.27))


## Curved stadium stand segment (variant = number of tiers). Spans 30 degrees.
static func _stadium_ring(mb: MeshBuilder, tiers: int) -> void:
	var r0 := 55.0
	var seg := 6
	var span := TAU / 12.0
	for t in tiers:
		var ri := r0 + t * 3.0
		var ro := ri + 3.0
		var y0 := t * 1.6
		var y1 := y0 + 1.6
		var col: Color = [Color(0.95, 0.35, 0.3), Color(0.25, 0.55, 0.95), Color(0.98, 0.82, 0.25)][t % 3]
		for s in seg:
			var a0 := span * s / seg - span * 0.5
			var a1 := span * (s + 1) / seg - span * 0.5
			var d0 := Vector3(cos(a0), 0, sin(a0))
			var d1 := Vector3(cos(a1), 0, sin(a1))
			# tread (top)
			mb.quad(d0 * ri + Vector3(0, y1, 0), d1 * ri + Vector3(0, y1, 0), d1 * ro + Vector3(0, y1, 0), d0 * ro + Vector3(0, y1, 0), col)
			# riser (faces centre)
			mb.quad(d0 * ri + Vector3(0, y0, 0), d1 * ri + Vector3(0, y0, 0), d1 * ri + Vector3(0, y1, 0), d0 * ri + Vector3(0, y1, 0), Color(0.85, 0.85, 0.85))
			if t == tiers - 1:
				mb.quad(d1 * ro, d0 * ro, d0 * ro + Vector3(0, y1, 0), d1 * ro + Vector3(0, y1, 0), Color(0.75, 0.75, 0.78))


static func _umbrella(mb: MeshBuilder, rng: RandomNumberGenerator) -> void:
	mb.cylinder(Vector3.ZERO, 2.4, 0.05, 0.05, 5, Color(0.9, 0.9, 0.9))
	var cols := [Color(1, 0.35, 0.35), Color(1, 1, 1)]
	var off := rng.randi() % 2
	for i in 8:
		var a0 := TAU * i / 8.0
		var a1 := TAU * (i + 1) / 8.0
		var top := Vector3(0, 2.75, 0)
		var p0 := Vector3(cos(a0) * 1.6, 2.1, sin(a0) * 1.6)
		var p1 := Vector3(cos(a1) * 1.6, 2.1, sin(a1) * 1.6)
		mb.tri(top, p0, p1, cols[(i + off) % 2])
		mb.tri(top, p1, p0, Color(0.8, 0.8, 0.8))


static func _lamp(mb: MeshBuilder) -> void:
	mb.cylinder(Vector3.ZERO, 6.0, 0.12, 0.09, 6, Color(0.25, 0.27, 0.3))
	mb.limb(Vector3(0, 6.0, 0), Vector3(1.2, 6.3, 0), 0.08, 0.08, Color(0.25, 0.27, 0.3), 5)
	mb.sphere(Vector3(1.25, 6.15, 0), Vector3(0.35, 0.2, 0.35), 3, 8, Color(1, 0.95, 0.75))


static func _grass(mb: MeshBuilder, rng: RandomNumberGenerator) -> void:
	var base := Color(0.3, 0.6, 0.2)
	for i in 7:
		var a := rng.randf() * TAU
		var r := rng.randf() * 0.25
		var p := Vector3(cos(a) * r, 0, sin(a) * r)
		var lean := Vector3(rng.randf_range(-0.25, 0.25), 0, rng.randf_range(-0.25, 0.25))
		var h := rng.randf_range(0.35, 0.7)
		var side := Vector3(cos(a + 1.3), 0, sin(a + 1.3)) * 0.05
		var c := base.lerp(Color(0.5, 0.78, 0.3), rng.randf())
		mb.tri(p - side, p + Vector3(0, h, 0) + lean, p + side, c)
		mb.tri(p + side, p + Vector3(0, h, 0) + lean, p - side, c.darkened(0.15))


static func _flower(mb: MeshBuilder, rng: RandomNumberGenerator, variant: int) -> void:
	var cols := [Color(1.0, 0.85, 0.2), Color(1.0, 0.45, 0.6), Color(0.6, 0.5, 1.0), Color(1, 1, 1)]
	for i in 5:
		var p := Vector3(rng.randf_range(-0.5, 0.5), 0, rng.randf_range(-0.5, 0.5))
		var h := rng.randf_range(0.25, 0.45)
		mb.cylinder(p, h, 0.012, 0.012, 3, Color(0.3, 0.6, 0.2), false)
		mb.sphere(p + Vector3(0, h, 0), Vector3(0.07, 0.04, 0.07), 2, 6, cols[(variant + i) % cols.size()])


static func _tent(mb: MeshBuilder, variant: int) -> void:
	var c: Color = [Color(0.95, 0.5, 0.2), Color(0.3, 0.6, 0.9), Color(0.4, 0.7, 0.35)][variant % 3]
	var seg := 10
	for i in seg:
		var a0 := PI * i / seg
		var a1 := PI * (i + 1) / seg
		var p0 := Vector3(cos(a0) * 1.5, sin(a0) * 1.6, 0)
		var p1 := Vector3(cos(a1) * 1.5, sin(a1) * 1.6, 0)
		var f := Vector3(0, 0, -1.8)
		var b := Vector3(0, 0, 1.8)
		var n0 := Vector3(cos(a0), sin(a0), 0)
		var n1 := Vector3(cos(a1), sin(a1), 0)
		var col := c if i % 2 == 0 else c.lightened(0.1)
		mb._add(p0 + f, n0, col); mb._add(p1 + f, n1, col); mb._add(p0 + b, n0, col)
		mb._add(p0 + b, n0, col); mb._add(p1 + f, n1, col); mb._add(p1 + b, n1, col)
		mb.tri(Vector3(0, 0, 1.8), p1 + b, p0 + b, c.darkened(0.2))
	mb.box(Vector3(0, 0.02, 0), Vector3(3.0, 0.04, 3.6), Color(0.35, 0.3, 0.25))


static func _log(mb: MeshBuilder) -> void:
	var old := mb.xf
	mb.xf = Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3(1.6, 0.35, 0))
	mb.cylinder(Vector3.ZERO, 3.2, 0.38, 0.34, 9, Color(0.48, 0.32, 0.2), true, Color(0.85, 0.7, 0.45))
	mb.xf = old


static func _fence(mb: MeshBuilder) -> void:
	var w := Color(0.82, 0.68, 0.48)
	for x: float in [0.0, 2.5, 5.0]:
		mb.box(Vector3(x, 0.55, 0), Vector3(0.14, 1.1, 0.14), w.darkened(0.1))
	for y: float in [0.45, 0.85]:
		mb.box(Vector3(2.5, y, 0), Vector3(5.1, 0.12, 0.05), w)


static func _campfire(mb: MeshBuilder) -> void:
	for i in 7:
		var a := TAU * i / 7.0
		mb.sphere(Vector3(cos(a) * 0.55, 0.08, sin(a) * 0.55), Vector3(0.16, 0.12, 0.16), 2, 6, Color(0.5, 0.5, 0.5))
	for i in 4:
		var a := TAU * i / 4.0 + 0.4
		mb.limb(Vector3(cos(a) * 0.35, 0.05, sin(a) * 0.35), Vector3(0, 0.45, 0), 0.06, 0.04, Color(0.45, 0.3, 0.18), 6)
	mb.cylinder(Vector3(0, 0.05, 0), 0.55, 0.22, 0.0, 7, Color(1.0, 0.55, 0.15))
