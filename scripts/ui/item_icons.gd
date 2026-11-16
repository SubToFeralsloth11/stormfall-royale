class_name ItemIcons
extends Node
## Renders ItemMeshes into small offscreen SubViewports and caches the result
## as ImageTextures (one render per id+rarity, shared across HUD instances).
## get_icon() returns null until the icon is ready.

const SIZE := 128

static var _cache := {}      # key -> ImageTexture
var _pending := {}           # key -> SubViewport


func get_icon(id: String, rarity: int) -> Texture2D:
	var key := "%s_%d" % [id, rarity]
	if _cache.has(key):
		return _cache[key]
	if not _pending.has(key):
		_start(key, id, rarity)
	return null


func _start(key: String, id: String, rarity: int) -> void:
	var vp := SubViewport.new()
	vp.size = Vector2i(SIZE, SIZE)
	vp.own_world_3d = true
	vp.transparent_bg = true
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	var we := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_CLEAR_COLOR
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(1, 1, 1)
	e.ambient_light_energy = 0.55
	we.environment = e
	vp.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-40), deg_to_rad(-60), 0)
	sun.light_energy = 1.3
	vp.add_child(sun)
	var mi := MeshInstance3D.new()
	mi.mesh = ItemMeshes.get_mesh(id, rarity)
	mi.material_override = MeshBuilder.vc_material(0.6)
	vp.add_child(mi)
	var aabb := mi.mesh.get_aabb()
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	# weapons point along -Z: look from -X so the barrel points left, slightly from above
	var dir := Vector3(-1.0, 0.35, 0.2).normalized()
	if not Items.WEAPONS.has(id) and id != "pickaxe":
		dir = Vector3(-0.6, 0.55, 0.75).normalized()
	var c := aabb.get_center()
	cam.size = maxf(aabb.size.length() * 0.78, 0.05)
	cam.near = 0.01
	cam.far = 20.0
	vp.add_child(cam)
	cam.look_at_from_position(c + dir * 5.0, c, Vector3.UP)
	cam.current = true
	_pending[key] = vp
	_harvest(key, vp)


func _harvest(key: String, vp: SubViewport) -> void:
	for i in 3:
		await RenderingServer.frame_post_draw
		if not is_instance_valid(vp):
			_pending.erase(key)
			return
	var img := vp.get_texture().get_image()
	if img != null and not img.is_empty():
		_cache[key] = ImageTexture.create_from_image(img)
	else:
		_cache[key] = null      # headless / dummy renderer: HUD falls back to text
	_pending.erase(key)
	vp.queue_free()
