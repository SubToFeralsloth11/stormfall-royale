extends Node
## Entry point: shows a loading card, then starts a match.

func _ready() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 50
	add_child(layer)
	var bg := ColorRect.new()
	bg.color = Color(0.12, 0.3, 0.6)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(bg)
	var lbl := Label.new()
	lbl.text = "STORMFALL ROYALE\nBuilding the island..."
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	lbl.add_theme_font_size_override("font_size", 42)
	layer.add_child(lbl)
	await get_tree().process_frame
	await get_tree().process_frame
	var m := Match.new()
	m.loaded.connect(func() -> void: layer.queue_free())
	add_child(m)
