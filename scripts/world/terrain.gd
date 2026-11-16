class_name Terrain
extends Node3D
## Procedural 3 km island: heightmap, chunked smooth-shaded mesh with LOD,
## HeightMapShape3D collision, POI pads, lake, river, roads, sea.

const EXTENT := 3600.0                       # heightmap covers +-1800 m (island + sea)
const N := int(EXTENT / Cfg.TERRAIN_STEP) + 1 # 601 samples per side
const CHUNK := 50                            # cells per chunk side
const COAST_R := 1390.0

## Named locations. type drives what island_builder places.
const POIS := [
	{"name": "Skyline Plaza", "pos": Vector2(-120, 80), "r": 150.0, "type": "city"},
	{"name": "Pinecrest", "pos": Vector2(-720, -640), "r": 130.0, "type": "suburb"},
	{"name": "Copper Crossing", "pos": Vector2(640, -460), "r": 120.0, "type": "town"},
	{"name": "Marigold Meadows", "pos": Vector2(-860, 420), "r": 130.0, "type": "farm"},
	{"name": "Fizzbang Factory", "pos": Vector2(820, 300), "r": 130.0, "type": "factory"},
	{"name": "Coral Cove", "pos": Vector2(120, 1080), "r": 110.0, "type": "beach"},
	{"name": "Frostcap Lodge", "pos": Vector2(1000, -930), "r": 70.0, "type": "cabin"},
	{"name": "Crimson Quarry", "pos": Vector2(-1080, -120), "r": 110.0, "type": "quarry"},
	{"name": "Lighthouse Point", "pos": Vector2(1050, 820), "r": 70.0, "type": "lighthouse"},
	{"name": "Tumbleweed Junction", "pos": Vector2(260, -1040), "r": 110.0, "type": "town"},
	{"name": "Willow Lakes", "pos": Vector2(-360, 690), "r": 120.0, "type": "suburb"},
	{"name": "Ranger Ridge", "pos": Vector2(-920, -930), "r": 80.0, "type": "cabin"},
	{"name": "Sunburst Stadium", "pos": Vector2(380, 520), "r": 110.0, "type": "stadium"},
]
const LAKE := {"pos": Vector2(-280, 920), "r": 95.0}
const RIVER := [Vector2(-280, 920), Vector2(-520, 1000), Vector2(-640, 1200), Vector2(-700, 1500)]
const ROADS := [
	[0, 2], [0, 4], [0, 3], [0, 1], [0, 12], [12, 5], [12, 4], [2, 9], [2, 6], [4, 8],
	[1, 7], [3, 7], [1, 11], [10, 3], [10, 5], [9, 1],
]

var heights := PackedFloat32Array()
var colors := PackedColorArray()
var pad_heights: Array[float] = []
var _noise := FastNoiseLite.new()
var _detail := FastNoiseLite.new()
var _coast := FastNoiseLite.new()
var minimap_image: Image


func generate(seed_value: int) -> void:
	_noise.seed = seed_value
	_noise.frequency = 0.0016
	_noise.fractal_octaves = 4
	_detail.seed = seed_value + 7
	_detail.frequency = 0.012
	_coast.seed = seed_value + 13
	_coast.frequency = 0.0022
	_coast.fractal_octaves = 3
	pad_heights.clear()
	for poi: Dictionary in POIS:
		var raw := _raw_height(poi.pos.x, poi.pos.y)
		pad_heights.append(maxf(Cfg.LEVEL, roundf(raw / Cfg.LEVEL) * Cfg.LEVEL))
	heights.resize(N * N)
	for iz in N:
		var z := -EXTENT * 0.5 + iz * Cfg.TERRAIN_STEP
		for ix in N:
			var x := -EXTENT * 0.5 + ix * Cfg.TERRAIN_STEP
			heights[iz * N + ix] = _final_height(x, z)
	_compute_colors()
	_build_meshes()
	_build_collision()
	_build_roads()
	_build_minimap()


# ---------------------------------------------------------------- height model

func _raw_height(x: float, z: float) -> float:
	var n := (_noise.get_noise_2d(x, z) + 1.0) * 0.5           # 0..1
	var h := 5.0 + n * n * 46.0
	h += _detail.get_noise_2d(x, z) * 1.6
	# Frostcap mountain + ridge
	h += 150.0 * _bump(x, z, Vector2(1060, -1010), 260.0)
	h += 55.0 * _bump(x, z, Vector2(760, -1180), 170.0)
	h += 70.0 * _bump(x, z, Vector2(-1120, -1080), 200.0)
	h += 40.0 * _bump(x, z, Vector2(-1180, 260), 160.0)
	h += 30.0 * _bump(x, z, Vector2(1180, 120), 180.0)
	return h


static func _bump(x: float, z: float, c: Vector2, r: float) -> float:
	var d2 := (Vector2(x, z) - c).length_squared()
	return exp(-d2 / (2.0 * r * r))


func coast_distance(x: float, z: float) -> float:
	## <0 inside island. Superellipse so the island fills the square like BR maps.
	var ax := absf(x)
	var az := absf(z)
	var d := pow(pow(ax, 3.0) + pow(az, 3.0), 1.0 / 3.0)
	return d - (COAST_R + _coast.get_noise_2d(x, z) * 110.0)


func _final_height(x: float, z: float) -> float:
	var h := _raw_height(x, z)
	var p := Vector2(x, z)
	# lake + river
	var dl := p.distance_to(LAKE.pos)
	h = lerpf(h, -5.0, 1.0 - smoothstep(LAKE.r * 0.7, LAKE.r * 1.25, dl))
	var dr := _dist_polyline(p, RIVER)
	h = lerpf(h, -3.5, 1.0 - smoothstep(9.0, 34.0, dr))
	# gentle beaches: cap height near the coastline
	var cd := coast_distance(x, z)
	if cd > -160.0:
		h = minf(h, 1.6 + maxf(0.0, -cd) * 0.3)
	# POI pads (flat, on build-grid levels so buildings sit cleanly)
	for i in POIS.size():
		var poi: Dictionary = POIS[i]
		var d := p.distance_to(poi.pos)
		var w := 1.0 - smoothstep(poi.r, poi.r + 70.0, d)
		if w > 0.0:
			h = lerpf(h, pad_heights[i], w)
	# fall off into the sea floor
	h = lerpf(h, -22.0, smoothstep(-5.0, 70.0, cd))
	return h


static func _dist_polyline(p: Vector2, pts: Array) -> float:
	var best := INF
	for i in pts.size() - 1:
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[i + 1]
		var ab := b - a
		var t := clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
		best = minf(best, p.distance_to(a + ab * t))
	return best


## Bilinear height at world x,z (matches HeightMapShape within a few cm).
func height_at(x: float, z: float) -> float:
	var fx := (x + EXTENT * 0.5) / Cfg.TERRAIN_STEP
	var fz := (z + EXTENT * 0.5) / Cfg.TERRAIN_STEP
	fx = clampf(fx, 0.0, N - 1.001)
	fz = clampf(fz, 0.0, N - 1.001)
	var ix := int(fx)
	var iz := int(fz)
	var tx := fx - ix
	var tz := fz - iz
	var i := iz * N + ix
	var h00 := heights[i]
	var h10 := heights[i + 1]
	var h01 := heights[i + N]
	var h11 := heights[i + N + 1]
	# split along the same diagonal as HeightMapShape3D triangles
	if tx + tz <= 1.0:
		return h00 + (h10 - h00) * tx + (h01 - h00) * tz
	return h11 + (h01 - h11) * (1.0 - tx) + (h10 - h11) * (1.0 - tz)


func normal_at(x: float, z: float) -> Vector3:
	var e := 2.0
	return Vector3(height_at(x - e, z) - height_at(x + e, z), 2.0 * e, height_at(x, z - e) - height_at(x, z + e)).normalized()


func is_land(x: float, z: float) -> bool:
	return height_at(x, z) > 0.6


func poi_at(p: Vector2) -> int:
	for i in POIS.size():
		if p.distance_to(POIS[i].pos) < POIS[i].r + 40.0:
			return i
	return -1


# ---------------------------------------------------------------- colours

func _compute_colors() -> void:
	colors.resize(N * N)
	var sand := Color(0.95, 0.86, 0.6)
	var wet_sand := Color(0.78, 0.7, 0.5)
	var grass_a := Color(0.33, 0.67, 0.22)
	var grass_b := Color(0.47, 0.76, 0.27)
	var dry := Color(0.82, 0.7, 0.42)
	var rock := Color(0.52, 0.5, 0.5)
	var snow := Color(0.95, 0.97, 1.0)
	var dirt := Color(0.55, 0.42, 0.28)
	for iz in N:
		var z := -EXTENT * 0.5 + iz * Cfg.TERRAIN_STEP
		for ix in N:
			var x := -EXTENT * 0.5 + ix * Cfg.TERRAIN_STEP
			var i := iz * N + ix
			var h := heights[i]
			var hx := heights[i + 1] if ix < N - 1 else h
			var hz := heights[i + N] if iz < N - 1 else h
			var slope := Vector2(hx - h, hz - h).length() / Cfg.TERRAIN_STEP
			var c: Color
			if h < 0.3:
				c = wet_sand
			elif h < 2.6:
				c = sand
			else:
				var t := (_detail.get_noise_2d(x * 0.4, z * 0.4) + 1.0) * 0.5
				c = grass_a.lerp(grass_b, t)
				# dry south-east desert band around Tumbleweed Junction
				var desert := 1.0 - smoothstep(180.0, 420.0, Vector2(x, z).distance_to(Vector2(260, -1040)))
				c = c.lerp(dry, desert)
				var quarry := 1.0 - smoothstep(80.0, 170.0, Vector2(x, z).distance_to(Vector2(-1080, -120)))
				c = c.lerp(Color(0.72, 0.36, 0.25), quarry * 0.85)
				if slope > 0.55:
					c = c.lerp(rock, clampf((slope - 0.55) * 3.0, 0.0, 1.0))
				if h > 95.0:
					c = c.lerp(snow, clampf((h - 95.0) / 12.0, 0.0, 1.0))
				var pi := poi_at(Vector2(x, z))
				if pi >= 0 and POIS[pi].type in ["farm"]:
					var stripe := int(floor(x / 9.0)) % 2 == 0
					c = c.lerp(dirt if stripe else Color(0.86, 0.75, 0.3), 0.55)
			colors[i] = c


# ---------------------------------------------------------------- meshes

func _build_meshes() -> void:
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.95
	mat.metallic_specular = 0.2
	var chunks := (N - 1) / CHUNK
	for cz in chunks:
		for cx in chunks:
			for lod in 2:
				var step := 1 if lod == 0 else 4
				var mi := MeshInstance3D.new()
				mi.mesh = _chunk_mesh(cx * CHUNK, cz * CHUNK, step)
				mi.material_override = mat
				if lod == 0:
					mi.visibility_range_end = 900.0
					mi.visibility_range_end_margin = 40.0
				else:
					mi.visibility_range_begin = 900.0
					mi.visibility_range_begin_margin = 40.0
					mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
				add_child(mi)


func _chunk_mesh(x0: int, z0: int, step: int) -> ArrayMesh:
	var count := CHUNK / step + 1
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	verts.resize(count * count)
	norms.resize(count * count)
	cols.resize(count * count)
	var half := EXTENT * 0.5
	for j in count:
		var iz := z0 + j * step
		for i in count:
			var ix := x0 + i * step
			var k := j * count + i
			var h := heights[iz * N + ix]
			verts[k] = Vector3(-half + ix * Cfg.TERRAIN_STEP, h, -half + iz * Cfg.TERRAIN_STEP)
			var hl := heights[iz * N + maxi(ix - 1, 0)]
			var hr := heights[iz * N + mini(ix + 1, N - 1)]
			var hd := heights[maxi(iz - 1, 0) * N + ix]
			var hu := heights[mini(iz + 1, N - 1) * N + ix]
			norms[k] = Vector3(hl - hr, 2.0 * Cfg.TERRAIN_STEP, hd - hu).normalized()
			cols[k] = colors[iz * N + ix]
	for j in count - 1:
		for i in count - 1:
			var a := j * count + i
			var b := a + 1
			var c := a + count
			var d := c + 1
			idx.append_array([a, b, c, b, d, c])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return m


func _build_collision() -> void:
	var body := StaticBody3D.new()
	body.collision_layer = Cfg.L_WORLD
	body.collision_mask = 0
	body.set_meta("terrain", true)
	var shape := HeightMapShape3D.new()
	shape.map_width = N
	shape.map_depth = N
	shape.map_data = heights
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.scale = Vector3(Cfg.TERRAIN_STEP, 1.0, Cfg.TERRAIN_STEP)
	body.add_child(cs)
	add_child(body)


func _build_roads() -> void:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var asphalt := Color(0.3, 0.31, 0.33)
	var line := Color(0.95, 0.85, 0.3)
	for r: Array in ROADS:
		var a: Vector2 = POIS[r[0]].pos
		var b: Vector2 = POIS[r[1]].pos
		var dir := (b - a).normalized()
		var side := Vector2(-dir.y, dir.x)
		var length := a.distance_to(b)
		var steps := int(length / 6.0)
		for s in steps:
			var p0 := a + dir * (s * 6.0)
			var p1 := a + dir * minf((s + 1) * 6.0, length)
			if height_at(p0.x, p0.y) < 0.4 or height_at(p1.x, p1.y) < 0.4:
				continue
			_road_quad(verts, norms, cols, p0, p1, side, 4.0, asphalt, 0.12)
			if s % 2 == 0:
				_road_quad(verts, norms, cols, p0, p0.lerp(p1, 0.6), side, 0.15, line, 0.16)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_COLOR] = cols
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.8
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


func _road_quad(v: PackedVector3Array, n: PackedVector3Array, c: PackedColorArray, p0: Vector2, p1: Vector2, side: Vector2, w: float, col: Color, lift: float) -> void:
	var pts := [p0 + side * w, p0 - side * w, p1 + side * w, p1 - side * w]
	var p3: Array[Vector3] = []
	for p: Vector2 in pts:
		p3.append(Vector3(p.x, height_at(p.x, p.y) + lift, p.y))
	for k: int in [0, 2, 1, 1, 2, 3]:
		v.append(p3[k])
		n.append(Vector3.UP)
		c.append(col)


func _build_minimap() -> void:
	var size := 512
	minimap_image = Image.create(size, size, false, Image.FORMAT_RGB8)
	var water := Color(0.22, 0.55, 0.85)
	for py in size:
		for px in size:
			var x := (px + 0.5) / size * Cfg.MAP_SIZE * 1.2 - Cfg.MAP_SIZE * 0.6
			var z := (py + 0.5) / size * Cfg.MAP_SIZE * 1.2 - Cfg.MAP_SIZE * 0.6
			var h := height_at(x, z)
			var c: Color
			if h < 0.0:
				c = water.darkened(clampf(-h / 40.0, 0.0, 0.4))
			else:
				var fx := clampi(int((x + EXTENT * 0.5) / Cfg.TERRAIN_STEP), 0, N - 1)
				var fz := clampi(int((z + EXTENT * 0.5) / Cfg.TERRAIN_STEP), 0, N - 1)
				c = colors[fz * N + fx]
				c = c.lightened(clampf(h / 300.0, 0.0, 0.3))
			minimap_image.set_pixel(px, py, c)


## Map image covers +-0.6*MAP_SIZE; convert world xz to 0..1 map uv.
static func world_to_map_uv(p: Vector2) -> Vector2:
	return (p + Vector2.ONE * Cfg.MAP_SIZE * 0.6) / (Cfg.MAP_SIZE * 1.2)


static func map_uv_to_world(uv: Vector2) -> Vector2:
	return uv * Cfg.MAP_SIZE * 1.2 - Vector2.ONE * Cfg.MAP_SIZE * 0.6
