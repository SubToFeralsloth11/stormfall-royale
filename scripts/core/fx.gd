extends Node
## Visual effects: tracers, muzzle flashes, impacts, debris, explosions and
## the floating damage numbers that make hits read instantly.

var world: Node3D
var _tracer_mat: StandardMaterial3D
var _flash_mat: StandardMaterial3D
var _debris_mat: StandardMaterial3D
var _numbers: Array[Label3D] = []
var _next_number := 0
var _tracer_mesh: CylinderMesh
var _flash_mesh: SphereMesh
var _chunk_mesh: BoxMesh
var _fire_mat: StandardMaterial3D


func _ready() -> void:
	_tracer_mat = StandardMaterial3D.new()
	_tracer_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_tracer_mat.albedo_color = Color(1.0, 0.92, 0.6, 0.9)
	_tracer_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_tracer_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_flash_mat = _tracer_mat.duplicate()
	_flash_mat.albedo_color = Color(1.0, 0.8, 0.4, 1.0)
	_fire_mat = _tracer_mat.duplicate()
	_fire_mat.albedo_color = Color(1.0, 0.55, 0.2, 1.0)
	_debris_mat = MeshBuilder.vc_material(0.9)
	_debris_mat.vertex_color_use_as_albedo = false
	_tracer_mesh = CylinderMesh.new()
	_tracer_mesh.top_radius = 0.018
	_tracer_mesh.bottom_radius = 0.018
	_tracer_mesh.height = 1.0
	_tracer_mesh.radial_segments = 4
	_tracer_mesh.rings = 1
	_flash_mesh = SphereMesh.new()
	_flash_mesh.radius = 0.12
	_flash_mesh.height = 0.24
	_flash_mesh.radial_segments = 6
	_flash_mesh.rings = 3
	_chunk_mesh = BoxMesh.new()
	_chunk_mesh.size = Vector3(0.35, 0.2, 0.08)


func reset(w: Node3D) -> void:
	world = w
	_numbers.clear()
	_next_number = 0


func _ok() -> bool:
	return world != null and is_instance_valid(world)


func tracer(from: Vector3, to: Vector3) -> void:
	if not _ok():
		return
	var length := from.distance_to(to)
	if length < 0.5:
		return
	var mi := MeshInstance3D.new()
	mi.mesh = _tracer_mesh
	mi.material_override = _tracer_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world.add_child(mi)
	var seg := minf(length, 6.0)
	var dir := (to - from).normalized()
	mi.global_transform = Transform3D(MeshBuilder._basis_from_y(dir).scaled(Vector3(1, seg, 1)), from + dir * seg * 0.5)
	var tw := mi.create_tween()
	var dur := clampf(length / 400.0, 0.03, 0.25)
	tw.tween_property(mi, "global_position", to - dir * seg * 0.5, dur)
	tw.tween_callback(mi.queue_free)


func muzzle(pos: Vector3, scale := 1.0) -> void:
	if not _ok():
		return
	var mi := MeshInstance3D.new()
	mi.mesh = _flash_mesh
	mi.material_override = _flash_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world.add_child(mi)
	mi.global_position = pos
	mi.scale = Vector3.ONE * scale * randf_range(0.8, 1.3)
	var tw := mi.create_tween()
	tw.tween_property(mi, "scale", Vector3.ONE * 0.1, 0.05)
	tw.tween_callback(mi.queue_free)


func impact(pos: Vector3, normal: Vector3, col := Color(0.9, 0.85, 0.7)) -> void:
	if not _ok():
		return
	for i in 4:
		var mi := MeshInstance3D.new()
		mi.mesh = _flash_mesh
		var m := StandardMaterial3D.new()
		m.albedo_color = col
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		world.add_child(mi)
		mi.global_position = pos
		mi.scale = Vector3.ONE * 0.35
		var v := (normal + Vector3(randf_range(-0.7, 0.7), randf_range(-0.3, 0.9), randf_range(-0.7, 0.7))).normalized() * randf_range(0.4, 0.9)
		var tw := mi.create_tween()
		tw.set_parallel()
		tw.tween_property(mi, "global_position", pos + v, 0.25)
		tw.tween_property(mi, "scale", Vector3.ONE * 0.05, 0.25)
		tw.chain().tween_callback(mi.queue_free)


func debris(center: Vector3, col: Color, big: bool) -> void:
	if not _ok():
		return
	var n := 8 if big else 5
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = 0.9
	for i in n:
		var mi := MeshInstance3D.new()
		mi.mesh = _chunk_mesh
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		world.add_child(mi)
		var start := center + Vector3(randf_range(-1.5, 1.5), randf_range(-1, 1), randf_range(-1.5, 1.5))
		mi.global_position = start
		mi.rotation = Vector3(randf() * TAU, randf() * TAU, randf() * TAU)
		mi.scale = Vector3.ONE * randf_range(1.0, 2.5)
		var v := Vector3(randf_range(-3, 3), randf_range(2, 6), randf_range(-3, 3))
		var tw := mi.create_tween()
		tw.tween_method(func(t: float) -> void:
			if is_instance_valid(mi):
				mi.global_position = start + v * t + Vector3(0, -12.0 * t * t, 0)
				mi.rotate_x(0.15)
				mi.scale = Vector3.ONE * 2.0 * (1.0 - t) + Vector3.ONE * 0.01, 0.0, 0.7, 0.7)
		tw.tween_callback(mi.queue_free)


func explosion(pos: Vector3, radius: float) -> void:
	if not _ok():
		return
	var mi := MeshInstance3D.new()
	mi.mesh = _flash_mesh
	mi.material_override = _fire_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world.add_child(mi)
	mi.global_position = pos
	mi.scale = Vector3.ONE
	var tw := mi.create_tween()
	tw.tween_property(mi, "scale", Vector3.ONE * radius * 9.0, 0.18).set_ease(Tween.EASE_OUT)
	tw.tween_property(mi, "scale", Vector3.ONE * 0.1, 0.35)
	tw.tween_callback(mi.queue_free)
	var light := OmniLight3D.new()
	light.light_color = Color(1, 0.6, 0.3)
	light.light_energy = 6.0
	light.omni_range = radius * 3.0
	world.add_child(light)
	light.global_position = pos
	var lt := light.create_tween()
	lt.tween_property(light, "light_energy", 0.0, 0.4)
	lt.tween_callback(light.queue_free)
	debris(pos, Color(0.3, 0.3, 0.3), true)


## Floating damage number. kind: 0 health (white), 1 shield (blue), 2 headshot (yellow), 3 build (grey), 4 harvest (green-ish)
func number(pos: Vector3, value: String, kind: int) -> void:
	if not _ok():
		return
	var lbl: Label3D
	if _numbers.size() < 24:
		lbl = Label3D.new()
		lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lbl.no_depth_test = true
		lbl.fixed_size = true
		lbl.pixel_size = 0.0011
		lbl.font_size = 44
		lbl.outline_size = 14
		lbl.outline_modulate = Color(0, 0, 0, 0.85)
		lbl.render_priority = 10
		world.add_child(lbl)
		_numbers.append(lbl)
	else:
		lbl = _numbers[_next_number % _numbers.size()]
		_next_number += 1
		if not is_instance_valid(lbl):
			return
	var cols := [Color(1, 1, 1), Color(0.45, 0.8, 1.0), Color(1.0, 0.88, 0.2), Color(0.8, 0.8, 0.8), Color(0.75, 1.0, 0.6)]
	lbl.modulate = cols[kind]
	lbl.text = value
	lbl.visible = true
	lbl.font_size = 54 if kind == 2 else 44
	var start := pos + Vector3(randf_range(-0.3, 0.3), 0.2, randf_range(-0.3, 0.3))
	lbl.global_position = start
	var tw := lbl.create_tween()
	tw.set_parallel()
	tw.tween_property(lbl, "global_position", start + Vector3(0, 0.9, 0), 0.75).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(lbl, "modulate:a", 0.0, 0.35).set_delay(0.45)
