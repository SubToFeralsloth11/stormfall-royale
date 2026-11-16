extends SceneTree

func _initialize() -> void:
	var t := Terrain.new()
	root.add_child(t)
	var t0 := Time.get_ticks_msec()
	t.generate(1234)
	print("terrain ms: ", Time.get_ticks_msec() - t0)
	for poi in Terrain.POIS:
		print(poi.name, " h=", t.height_at(poi.pos.x, poi.pos.y), " land=", t.is_land(poi.pos.x, poi.pos.y))
	t.minimap_image.save_png("/tmp/sf_minimap.png")
	quit()
