class_name MeshBuilder
extends RefCounted
## Accumulates low-poly primitives (smooth-shaded curves, flat boxes) with
## vertex colours and optional single-bone skin weights into one ArrayMesh.

var verts := PackedVector3Array()
var norms := PackedVector3Array()
var cols := PackedColorArray()
var bones := PackedInt32Array()
var weights := PackedFloat32Array()
var skinned := false
var bone := 0                 # current bone for appended vertices
var xf := Transform3D.IDENTITY
## Global tessellation multiplier for curved primitives (set while building a mesh set).
static var detail := 1.0


func _add(v: Vector3, n: Vector3, c: Color) -> void:
	verts.append(xf * v)
	norms.append((xf.basis * n).normalized())
	cols.append(c)
	if skinned:
		bones.append_array([bone, 0, 0, 0])
		weights.append_array([1.0, 0.0, 0.0, 0.0])


func tri(a: Vector3, b: Vector3, c: Vector3, col: Color, n: Vector3 = Vector3.ZERO) -> void:
	if n == Vector3.ZERO:
		n = (c - a).cross(b - a).normalized()   # clockwise = front face
	_add(a, n, col)
	_add(b, n, col)
	_add(c, n, col)


func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color) -> void:
	## a-b-c-d counter-clockwise seen from the front; Godot treats clockwise as
	## front-facing, so emit a,c,b / a,d,c.
	var n := (b - a).cross(c - a).normalized()
	tri(a, c, b, col, n)
	tri(a, d, c, col, n)


func box(center: Vector3, size: Vector3, col: Color) -> void:
	var h := size * 0.5
	var p := [
		center + Vector3(-h.x, -h.y, -h.z), center + Vector3(h.x, -h.y, -h.z),
		center + Vector3(h.x, h.y, -h.z), center + Vector3(-h.x, h.y, -h.z),
		center + Vector3(-h.x, -h.y, h.z), center + Vector3(h.x, -h.y, h.z),
		center + Vector3(h.x, h.y, h.z), center + Vector3(-h.x, h.y, h.z),
	]
	quad(p[4], p[5], p[6], p[7], col)   # +z
	quad(p[1], p[0], p[3], p[2], col)   # -z
	quad(p[5], p[1], p[2], p[6], col)   # +x
	quad(p[0], p[4], p[7], p[3], col)   # -x
	quad(p[7], p[6], p[2], p[3], col)   # +y
	quad(p[0], p[1], p[5], p[4], col)   # -y


## Tapered cylinder along +Y from y0 to y1 with radii r0,r1; smooth normals.
func cylinder(base: Vector3, height: float, r0: float, r1: float, seg: int, col: Color, caps := true, col_top: Variant = null) -> void:
	seg = maxi(3, roundi(seg * detail))
	var top := base + Vector3(0, height, 0)
	var slope := (r0 - r1) / maxf(height, 0.001)
	for i in seg:
		var a0 := TAU * i / seg
		var a1 := TAU * (i + 1) / seg
		var d0 := Vector3(cos(a0), 0, sin(a0))
		var d1 := Vector3(cos(a1), 0, sin(a1))
		var n0 := (d0 + Vector3(0, slope, 0)).normalized()
		var n1 := (d1 + Vector3(0, slope, 0)).normalized()
		var b0 := base + d0 * r0
		var b1 := base + d1 * r0
		var t0 := top + d0 * r1
		var t1 := top + d1 * r1
		_add(b0, n0, col); _add(b1, n1, col); _add(t0, n0, col)
		if r1 > 0.0005:
			_add(b1, n1, col); _add(t1, n1, col); _add(t0, n0, col)
		if caps:
			if r1 > 0.0005:
				var ct: Color = col_top if col_top != null else col
				_add(top, Vector3.UP, ct); _add(t0, Vector3.UP, ct); _add(t1, Vector3.UP, ct)
			if r0 > 0.0005:
				_add(base, Vector3.DOWN, col); _add(b1, Vector3.DOWN, col); _add(b0, Vector3.DOWN, col)


## Low-poly UV sphere (ellipsoid via scale) with smooth normals.
func sphere(center: Vector3, radius: Vector3, rings: int, seg: int, col: Color, y_from := 0.0, y_to := 1.0) -> void:
	rings = maxi(1, roundi(rings * detail))
	seg = maxi(3, roundi(seg * detail))
	for r in rings:
		var v0 := lerpf(y_from, y_to, float(r) / rings)
		var v1 := lerpf(y_from, y_to, float(r + 1) / rings)
		var p0 := PI * (1.0 - v0)
		var p1 := PI * (1.0 - v1)
		for s in seg:
			var a0 := TAU * s / seg
			var a1 := TAU * (s + 1) / seg
			var u00 := _sph(p0, a0); var u01 := _sph(p0, a1)
			var u10 := _sph(p1, a0); var u11 := _sph(p1, a1)
			var q := [u00, u10, u11, u01]
			var order := [0, 2, 1, 0, 3, 2]
			for k: int in order:
				var u: Vector3 = q[k]
				_add(center + u * radius, (u / radius).normalized(), col)


static func _sph(polar: float, az: float) -> Vector3:
	return Vector3(sin(polar) * cos(az), cos(polar), sin(polar) * sin(az))


## Capsule between a and b (any direction).
func capsule(a: Vector3, b: Vector3, r: float, col: Color, seg := 8) -> void:
	var dir := b - a
	var length := dir.length()
	var old := xf
	var basis := _basis_from_y(dir.normalized())
	xf = old * Transform3D(basis, a)
	cylinder(Vector3.ZERO, length, r, r, seg, col, false)
	sphere(Vector3(0, length, 0), Vector3.ONE * r, 3, seg, col, 0.5, 1.0)
	sphere(Vector3.ZERO, Vector3.ONE * r, 3, seg, col, 0.0, 0.5)
	xf = old


## Tapered limb (rounded ends) between a and b.
func limb(a: Vector3, b: Vector3, ra: float, rb: float, col: Color, seg := 8) -> void:
	var dir := b - a
	var old := xf
	xf = old * Transform3D(_basis_from_y(dir.normalized()), a)
	cylinder(Vector3.ZERO, dir.length(), ra, rb, seg, col, false)
	sphere(Vector3(0, dir.length(), 0), Vector3.ONE * rb, 2, seg, col, 0.5, 1.0)
	sphere(Vector3.ZERO, Vector3.ONE * ra, 2, seg, col, 0.0, 0.5)
	xf = old


static func _basis_from_y(y: Vector3) -> Basis:
	var x := y.cross(Vector3.FORWARD)
	if x.length_squared() < 0.001:
		x = y.cross(Vector3.RIGHT)
	x = x.normalized()
	var z := x.cross(y).normalized()
	return Basis(x, y, z)


func build(existing: ArrayMesh = null) -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_COLOR] = cols
	if skinned:
		arrays[Mesh.ARRAY_BONES] = bones
		arrays[Mesh.ARRAY_WEIGHTS] = weights
	var m := existing if existing else ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return m


static func vc_material(rough := 0.85, metal := 0.0) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	mat.roughness = rough
	mat.metallic = metal
	return mat
