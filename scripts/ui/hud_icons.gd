class_name HudIcons
extends RefCounted
## Original hand-drawn HUD icons, drawn with CanvasItem primitives into a
## target rect. All functions take the CanvasItem that is currently drawing.

const OUTLINE := Color(0.05, 0.04, 0.06, 0.9)


static func _poly(ci: CanvasItem, pts: PackedVector2Array, fill: Color, outline := OUTLINE, w := 2.0) -> void:
	ci.draw_colored_polygon(pts, fill)
	var closed := pts.duplicate()
	closed.append(pts[0])
	ci.draw_polyline(closed, outline, w, true)


static func _pts(r: Rect2, rel: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p: Vector2 in rel:
		out.append(r.position + p * r.size)
	return out


## Wood: a chunky plank seen at an angle, end grain rings and wavy grain lines.
static func wood(ci: CanvasItem, r: Rect2, dim := false) -> void:
	var k := 0.55 if dim else 1.0
	var face := Color(0.66, 0.42, 0.2) * k
	var top := Color(0.8, 0.55, 0.3) * k
	var endc := Color(0.86, 0.66, 0.4) * k
	face.a = 1.0
	top.a = 1.0
	endc.a = 1.0
	# top face, front face, end cap
	_poly(ci, _pts(r, [Vector2(0.22, 0.22), Vector2(0.95, 0.22), Vector2(0.8, 0.4), Vector2(0.07, 0.4)]), top)
	_poly(ci, _pts(r, [Vector2(0.07, 0.4), Vector2(0.8, 0.4), Vector2(0.8, 0.8), Vector2(0.07, 0.8)]), face)
	_poly(ci, _pts(r, [Vector2(0.8, 0.4), Vector2(0.95, 0.22), Vector2(0.95, 0.62), Vector2(0.8, 0.8)]), endc)
	var grain := Color(0.4, 0.22, 0.08, 0.9) * Color(k, k, k, 1)
	for i in 3:
		var y := 0.48 + i * 0.1
		var line := PackedVector2Array()
		for s in 9:
			var t := s / 8.0
			line.append(r.position + Vector2(0.1 + t * 0.66, y + sin(t * 9.0 + i * 1.7) * 0.025) * r.size)
		ci.draw_polyline(line, grain, 1.4, true)
	# knot
	ci.draw_circle(r.position + Vector2(0.52, 0.6) * r.size, r.size.x * 0.035, grain)
	# end-grain rings
	var c := r.position + Vector2(0.875, 0.51) * r.size
	ci.draw_arc(c, r.size.x * 0.05, 0, TAU, 12, grain, 1.2, true)
	ci.draw_arc(c, r.size.x * 0.025, 0, TAU, 8, grain, 1.2, true)


## Stone: grey block drawn in perspective with staggered mortar lines.
static func stone(ci: CanvasItem, r: Rect2, dim := false) -> void:
	var k := 0.55 if dim else 1.0
	var face := Color(0.6 * k, 0.61 * k, 0.64 * k)
	var top := Color(0.75 * k, 0.76 * k, 0.79 * k)
	var side := Color(0.48 * k, 0.49 * k, 0.52 * k)
	_poly(ci, _pts(r, [Vector2(0.2, 0.16), Vector2(0.92, 0.16), Vector2(0.78, 0.32), Vector2(0.06, 0.32)]), top)
	_poly(ci, _pts(r, [Vector2(0.06, 0.32), Vector2(0.78, 0.32), Vector2(0.78, 0.86), Vector2(0.06, 0.86)]), face)
	_poly(ci, _pts(r, [Vector2(0.78, 0.32), Vector2(0.92, 0.16), Vector2(0.92, 0.7), Vector2(0.78, 0.86)]), side)
	var mortar := Color(0.28 * k, 0.28 * k, 0.3 * k)
	var rows := [0.32, 0.5, 0.68, 0.86]
	for i in 3:
		var y0: float = rows[i]
		var y1: float = rows[i + 1]
		if i > 0:
			ci.draw_line(r.position + Vector2(0.06, y0) * r.size, r.position + Vector2(0.78, y0) * r.size, mortar, 1.6)
		var xs := [0.42] if i % 2 == 0 else [0.24, 0.6]
		for x: float in xs:
			ci.draw_line(r.position + Vector2(x, y0) * r.size, r.position + Vector2(x, y1) * r.size, mortar, 1.6)
	# chips / speckle
	for p: Vector2 in [Vector2(0.15, 0.42), Vector2(0.55, 0.6), Vector2(0.3, 0.77), Vector2(0.68, 0.4)]:
		ci.draw_circle(r.position + p * r.size, r.size.x * 0.018, mortar)


## Metal: steel I-beam in perspective with a bright sheen stripe.
static func metal(ci: CanvasItem, r: Rect2, dim := false) -> void:
	var k := 0.55 if dim else 1.0
	var steel := Color(0.58 * k, 0.64 * k, 0.72 * k)
	var lite := Color(0.82 * k, 0.87 * k, 0.93 * k)
	var dark := Color(0.36 * k, 0.4 * k, 0.47 * k)
	var d := Vector2(0.14, -0.12)   # extrusion direction
	# end profile (I shape) at left, extruded to upper right
	var prof := [
		Vector2(0.06, 0.48), Vector2(0.56, 0.48), Vector2(0.56, 0.56), Vector2(0.37, 0.56),
		Vector2(0.37, 0.76), Vector2(0.56, 0.76), Vector2(0.56, 0.84), Vector2(0.06, 0.84),
		Vector2(0.06, 0.76), Vector2(0.25, 0.76), Vector2(0.25, 0.56), Vector2(0.06, 0.56),
	]
	# top flange surface
	_poly(ci, _pts(r, [Vector2(0.06, 0.48), Vector2(0.56, 0.48), Vector2(0.56, 0.48) + d * 2.6, Vector2(0.06, 0.48) + d * 2.6]), lite)
	# right side of flanges/web
	_poly(ci, _pts(r, [Vector2(0.56, 0.48), Vector2(0.56, 0.48) + d * 2.6, Vector2(0.56, 0.56) + d * 2.6, Vector2(0.56, 0.56)]), dark)
	_poly(ci, _pts(r, [Vector2(0.37, 0.56), Vector2(0.37, 0.56) + d * 2.6, Vector2(0.37, 0.76) + d * 2.6, Vector2(0.37, 0.76)]), dark)
	_poly(ci, _pts(r, [Vector2(0.56, 0.76), Vector2(0.56, 0.76) + d * 2.6, Vector2(0.56, 0.84) + d * 2.6, Vector2(0.56, 0.84)]), dark)
	_poly(ci, _pts(r, prof), steel)
	# sheen across the top flange and the face
	ci.draw_line(r.position + Vector2(0.14, 0.46) * r.size, r.position + (Vector2(0.14, 0.46) + d * 2.5) * r.size, Color(1, 1, 1, 0.85 * k), 2.0)
	ci.draw_line(r.position + Vector2(0.1, 0.82) * r.size, r.position + Vector2(0.22, 0.5) * r.size, Color(1, 1, 1, 0.55 * k), 2.0)
	# rivets
	for p: Vector2 in [Vector2(0.31, 0.62), Vector2(0.31, 0.7)]:
		ci.draw_circle(r.position + p * r.size, r.size.x * 0.02, lite)


static func material(ci: CanvasItem, idx: int, r: Rect2, dim := false) -> void:
	match idx:
		0: wood(ci, r, dim)
		1: stone(ci, r, dim)
		_: metal(ci, r, dim)


static func shield(ci: CanvasItem, r: Rect2) -> void:
	var p := _pts(r, [Vector2(0.5, 0.06), Vector2(0.9, 0.2), Vector2(0.84, 0.6), Vector2(0.5, 0.95), Vector2(0.16, 0.6), Vector2(0.1, 0.2)])
	_poly(ci, p, UiStyle.SHIELD)
	_poly(ci, _pts(r, [Vector2(0.5, 0.18), Vector2(0.76, 0.27), Vector2(0.72, 0.56), Vector2(0.5, 0.8)]), Color(0.75, 0.9, 1.0), Color(0, 0, 0, 0), 0.0)


static func health(ci: CanvasItem, r: Rect2) -> void:
	var p := _pts(r, [
		Vector2(0.36, 0.08), Vector2(0.64, 0.08), Vector2(0.64, 0.36), Vector2(0.92, 0.36),
		Vector2(0.92, 0.64), Vector2(0.64, 0.64), Vector2(0.64, 0.92), Vector2(0.36, 0.92),
		Vector2(0.36, 0.64), Vector2(0.08, 0.64), Vector2(0.08, 0.36), Vector2(0.36, 0.36)])
	_poly(ci, p, UiStyle.HEALTH)


static func person(ci: CanvasItem, r: Rect2, col := Color.WHITE) -> void:
	ci.draw_circle(r.position + Vector2(0.5, 0.28) * r.size, r.size.x * 0.2, col)
	ci.draw_colored_polygon(_pts(r, [Vector2(0.16, 0.95), Vector2(0.22, 0.6), Vector2(0.5, 0.52), Vector2(0.78, 0.6), Vector2(0.84, 0.95)]), col)


static func skull(ci: CanvasItem, r: Rect2, col := Color.WHITE) -> void:
	ci.draw_circle(r.position + Vector2(0.5, 0.42) * r.size, r.size.x * 0.36, col)
	ci.draw_rect(Rect2(r.position + Vector2(0.3, 0.6) * r.size, Vector2(0.4, 0.3) * r.size), col)
	var hole := Color(0.05, 0.05, 0.1)
	ci.draw_circle(r.position + Vector2(0.36, 0.44) * r.size, r.size.x * 0.1, hole)
	ci.draw_circle(r.position + Vector2(0.64, 0.44) * r.size, r.size.x * 0.1, hole)
	ci.draw_line(r.position + Vector2(0.43, 0.78) * r.size, r.position + Vector2(0.43, 0.9) * r.size, hole, 1.5)
	ci.draw_line(r.position + Vector2(0.57, 0.78) * r.size, r.position + Vector2(0.57, 0.9) * r.size, hole, 1.5)


static func storm(ci: CanvasItem, r: Rect2) -> void:
	var c := r.get_center()
	ci.draw_circle(c, r.size.x * 0.46, UiStyle.STORM)
	ci.draw_arc(c, r.size.x * 0.3, 0.3, 4.6, 12, Color(0.92, 0.85, 1.0), 2.0, true)
	ci.draw_arc(c, r.size.x * 0.14, 2.2, 6.0, 10, Color(0.92, 0.85, 1.0), 2.0, true)


static func clock(ci: CanvasItem, r: Rect2, col := Color.WHITE) -> void:
	var c := r.get_center()
	ci.draw_arc(c, r.size.x * 0.42, 0, TAU, 16, col, 2.0, true)
	ci.draw_line(c, c + Vector2(0, -r.size.y * 0.28), col, 2.0)
	ci.draw_line(c, c + Vector2(r.size.x * 0.2, 0), col, 2.0)


static func bullet(ci: CanvasItem, r: Rect2, col: Color) -> void:
	var body := Rect2(r.position + Vector2(0.3, 0.38) * r.size, Vector2(0.4, 0.52) * r.size)
	ci.draw_rect(body, col.darkened(0.2))
	ci.draw_colored_polygon(_pts(r, [Vector2(0.3, 0.38), Vector2(0.5, 0.06), Vector2(0.7, 0.38)]), col)
	ci.draw_rect(Rect2(r.position + Vector2(0.26, 0.82) * r.size, Vector2(0.48, 0.1) * r.size), col.darkened(0.45))


## Build piece pictograms: 0 wall, 1 floor, 2 ramp, 3 cone (matches PieceMeshes.Kind order).
static func piece(ci: CanvasItem, kind: int, r: Rect2, col: Color) -> void:
	var dark := col.darkened(0.45)
	match kind:
		0:
			var p := _pts(r, [Vector2(0.18, 0.2), Vector2(0.82, 0.2), Vector2(0.82, 0.82), Vector2(0.18, 0.82)])
			_poly(ci, p, col, dark)
			ci.draw_line(r.position + Vector2(0.18, 0.51) * r.size, r.position + Vector2(0.82, 0.51) * r.size, dark, 2.0)
			ci.draw_line(r.position + Vector2(0.5, 0.2) * r.size, r.position + Vector2(0.5, 0.82) * r.size, dark, 2.0)
		1:
			_poly(ci, _pts(r, [Vector2(0.3, 0.38), Vector2(0.92, 0.38), Vector2(0.7, 0.7), Vector2(0.08, 0.7)]), col, dark)
			_poly(ci, _pts(r, [Vector2(0.08, 0.7), Vector2(0.7, 0.7), Vector2(0.7, 0.77), Vector2(0.08, 0.77)]), dark, dark)
		2:
			_poly(ci, _pts(r, [Vector2(0.12, 0.82), Vector2(0.88, 0.82), Vector2(0.88, 0.2)]), col, dark)
			for i in 4:
				var t := (i + 1) / 5.0
				var a := r.position + Vector2(0.12 + t * 0.76, 0.82 - t * 0.62) * r.size
				ci.draw_line(a, Vector2(a.x, r.position.y + 0.82 * r.size.y), dark, 1.5)
		_:
			_poly(ci, _pts(r, [Vector2(0.5, 0.18), Vector2(0.9, 0.7), Vector2(0.5, 0.86)]), col.darkened(0.2), dark)
			_poly(ci, _pts(r, [Vector2(0.5, 0.18), Vector2(0.5, 0.86), Vector2(0.1, 0.7)]), col, dark)
