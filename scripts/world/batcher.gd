class_name Batcher
extends Node3D
## Static instanced rendering: one MultiMeshInstance3D per (mesh, spatial chunk).
## Instances can later be hidden (destroyed) or recoloured cheaply.

const CHUNK := 160.0

class Group:
	var mesh: Mesh
	var mat: Material
	var xforms: Array[Transform3D] = []
	var colors: Array[Color] = []
	var vis_end := 1200.0
	var shadow := true
	var mmi: MultiMeshInstance3D

var _groups: Array[Group] = []
var _index := {}   # "key|cx|cz" -> group idx


## Returns a handle (group << 20 | instance).
func add(key: String, mesh: Mesh, mat: Material, xf: Transform3D, color: Color, vis_end := 1200.0, shadow := true) -> int:
	var cx := floori(xf.origin.x / CHUNK)
	var cz := floori(xf.origin.z / CHUNK)
	var gk := "%s|%d|%d" % [key, cx, cz]
	var gi: int
	if _index.has(gk):
		gi = _index[gk]
	else:
		var g := Group.new()
		g.mesh = mesh
		g.mat = mat
		g.vis_end = vis_end
		g.shadow = shadow
		gi = _groups.size()
		_groups.append(g)
		_index[gk] = gi
	var grp: Group = _groups[gi]
	grp.xforms.append(xf)
	grp.colors.append(color)
	return (gi << 20) | (grp.xforms.size() - 1)


func finalize() -> void:
	for g in _groups:
		if g.mmi:
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = g.mesh
		mm.instance_count = g.xforms.size()
		for i in g.xforms.size():
			mm.set_instance_transform(i, g.xforms[i])
			mm.set_instance_color(i, g.colors[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = g.mat
		mmi.visibility_range_end = g.vis_end
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if g.shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mmi)
		g.mmi = mmi


func hide_instance(handle: int) -> void:
	var g := _groups[handle >> 20]
	var i := handle & 0xFFFFF
	g.xforms[i] = Transform3D(Basis().scaled(Vector3.ZERO), g.xforms[i].origin)
	if g.mmi:
		g.mmi.multimesh.set_instance_transform(i, g.xforms[i])


func set_instance_transform(handle: int, xf: Transform3D) -> void:
	var g := _groups[handle >> 20]
	var i := handle & 0xFFFFF
	g.xforms[i] = xf
	if g.mmi:
		g.mmi.multimesh.set_instance_transform(i, xf)


func instance_transform(handle: int) -> Transform3D:
	return _groups[handle >> 20].xforms[handle & 0xFFFFF]
