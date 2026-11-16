class_name LobbyMenu
extends Node3D
## Lobby: the selected outfit idling on a round platform under a bright sky,
## top tabs (LOBBY / LOCKER / SETTINGS / QUIT) and a big yellow PLAY button.
## Drag on the background to spin the character.

var rig: CharacterRig
var _rig_holder: Node3D
var _cam: Camera3D
var _ui: CanvasLayer
var _locker: Control
var _settings: Control
var _skin_label: Label
var _skin_buttons: Array[Button] = []
var _tab_buttons := {}
var _dragging := false
var _spin_vel := 0.0
var _emote_wait := 4.0
var _emote_left := 0.0
var _ring: MeshInstance3D
var _t := 0.0


func _ready() -> void:
	_build_world()
	_build_ui()
	_set_skin(Cfg.selected_skin, false)
	_show_tab("lobby")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


# ------------------------------------------------------------------ 3D scene

func _build_world() -> void:
	var we := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.1, 0.25, 0.75)
	sm.sky_horizon_color = Color(0.55, 0.62, 0.98)
	sm.ground_horizon_color = Color(0.55, 0.62, 0.98)
	sm.ground_bottom_color = Color(0.18, 0.15, 0.45)
	sm.sun_angle_max = 25.0
	sky.sky_material = sm
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_energy = 0.9
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.glow_enabled = true
	e.glow_intensity = 0.6
	e.adjustment_enabled = true
	e.adjustment_saturation = 1.15
	we.environment = e
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-40), deg_to_rad(25), 0)
	sun.light_energy = 1.2
	sun.light_color = Color(1.0, 0.95, 0.88)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 20.0
	add_child(sun)
	var rim := OmniLight3D.new()
	rim.position = Vector3(-1.6, 2.4, -1.4)
	rim.light_color = Color(0.5, 0.65, 1.0)
	rim.light_energy = 2.5
	rim.omni_range = 6.0
	add_child(rim)
	# platform: chunky disc + glowing rim + a lower step
	var mat := MeshBuilder.vc_material(0.5)
	var mb := MeshBuilder.new()
	mb.cylinder(Vector3(0, -0.5, 0), 0.5, 1.75, 1.6, 24, Color(0.2, 0.32, 0.75), true, Color(0.36, 0.48, 0.86))
	mb.cylinder(Vector3(0, -0.85, 0), 0.35, 2.3, 2.15, 24, Color(0.14, 0.2, 0.55), true, Color(0.35, 0.45, 0.9))
	var plat := MeshInstance3D.new()
	plat.mesh = mb.build()
	plat.material_override = mat
	add_child(plat)
	_ring = MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 1.58
	tm.outer_radius = 1.68
	tm.rings = 48
	_ring.mesh = tm
	var rm := StandardMaterial3D.new()
	rm.albedo_color = Color(0.4, 0.85, 1.0)
	rm.emission_enabled = true
	rm.emission = Color(0.35, 0.8, 1.0)
	rm.emission_energy_multiplier = 1.6
	_ring.material_override = rm
	_ring.position.y = -0.02
	add_child(_ring)
	# floaty background islands / clouds so it is not just a gradient
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var cloud := MeshBuilder.new()
	for i in 9:
		var p := Vector3(rng.randf_range(-26, 26), rng.randf_range(-3, 9), rng.randf_range(-40, -18))
		for j in 4:
			cloud.sphere(p + Vector3(j * 1.6 - 2.4, rng.randf_range(-0.3, 0.6), rng.randf_range(-0.6, 0.6)),
				Vector3.ONE * rng.randf_range(1.2, 2.2), 3, 7, Color(0.96, 0.97, 1.0))
	var cl := MeshInstance3D.new()
	cl.mesh = cloud.build()
	cl.material_override = MeshBuilder.vc_material(1.0)
	cl.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(cl)
	_rig_holder = Node3D.new()
	add_child(_rig_holder)
	_cam = Camera3D.new()
	_cam.fov = 40.0
	add_child(_cam)
	_cam.look_at_from_position(Vector3(1.1, 1.35, 5.0), Vector3(1.1, 0.95, 0), Vector3.UP)
	_cam.current = true


func _set_skin(i: int, save := true) -> void:
	i = posmod(i, Skins.count())
	var yaw := _rig_holder.rotation.y
	if rig != null:
		rig.queue_free()
	rig = CharacterRig.new()
	_rig_holder.add_child(rig)
	rig.setup(i)
	rig.rotation.y = PI      # rig faces -Z by default; turn it toward the camera
	rig.hold = "none"
	rig.set_held_mesh("")
	_rig_holder.rotation.y = yaw
	_emote_left = 0.0
	_emote_wait = 3.0
	if save:
		Cfg.selected_skin = i
		Cfg.save_settings()
		# a little wave to show off the new look
		rig.emote = 1
		rig.emote_t = 0.0
		_emote_left = 1.6
	if _skin_label:
		_skin_label.text = Skins.get_def(i).name.to_upper()
	for b in _skin_buttons.size():
		_skin_buttons[b].button_pressed = b == i


func _process(delta: float) -> void:
	_t += delta
	if rig == null:
		return
	if not _dragging:
		_spin_vel = lerpf(_spin_vel, 0.0, minf(1.0, delta * 3.0))
		_rig_holder.rotation.y = lerp_angle(_rig_holder.rotation.y, 0.0, minf(1.0, delta * 0.6)) if absf(_spin_vel) < 0.05 else _rig_holder.rotation.y + _spin_vel * delta
	# occasional emote
	if _emote_left > 0.0:
		_emote_left -= delta
		rig.emote_t += delta
		if _emote_left <= 0.0:
			rig.emote = -1
			_emote_wait = randf_range(6.0, 10.0)
	else:
		_emote_wait -= delta
		if _emote_wait <= 0.0:
			rig.emote = randi() % 4
			rig.emote_t = 0.0
			_emote_left = 2.0 if rig.emote != 2 else 1.4
	_ring.rotation.y += delta * 0.4
	var rm: StandardMaterial3D = _ring.material_override
	rm.emission_energy_multiplier = 1.4 + sin(_t * 2.0) * 0.4


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_dragging = event.pressed
	elif event is InputEventMouseMotion and _dragging:
		_rig_holder.rotation.y += event.relative.x * 0.012
		_spin_vel = event.relative.x * 0.012 / maxf(get_process_delta_time(), 0.001) * 0.5
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
			_play()
		elif event.keycode == KEY_ESCAPE:
			_show_tab("lobby")


# ------------------------------------------------------------------ UI

func _build_ui() -> void:
	_ui = CanvasLayer.new()
	_ui.layer = 10
	add_child(_ui)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(root)
	# top bar
	var bar := ColorRect.new()
	bar.color = Color(0.03, 0.06, 0.2, 0.75)
	bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	bar.offset_bottom = 64
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bar)
	var logo := UiStyle.label("FORTNITE", 40, Color.WHITE, 8)
	logo.position = Vector2(24, 6)
	root.add_child(logo)
	var tag := UiStyle.label("TEMU EDITION", 18, Color(1.0, 0.25, 0.25), 5)
	tag.position = Vector2(30, 38)
	tag.rotation = deg_to_rad(-4)
	root.add_child(tag)
	var tabs := HBoxContainer.new()
	tabs.position = Vector2(240, 10)
	tabs.add_theme_constant_override("separation", 6)
	root.add_child(tabs)
	for t: Array in [["lobby", "LOBBY"], ["locker", "LOCKER"], ["settings", "SETTINGS"], ["quit", "QUIT"]]:
		var b := Button.new()
		b.text = t[1]
		b.custom_minimum_size = Vector2(130, 44)
		b.toggle_mode = t[0] != "quit"
		UiStyle.style_button(b, Color(0, 0, 0, 0), Color.WHITE, 24)
		b.add_theme_stylebox_override("pressed", UiStyle.box(Color(1, 1, 1, 0.18), 4, 0))
		b.add_theme_color_override("font_pressed_color", UiStyle.YELLOW)
		var id: String = t[0]
		b.pressed.connect(func() -> void: Sfx.play("ui"); _show_tab(id))
		tabs.add_child(b)
		_tab_buttons[id] = b
	# V-bucks parody counter top-right
	var bucks := UiStyle.label("0 T-BUCKS", 22, Color(0.85, 0.95, 1.0), 6)
	_place(bucks, Control.PRESET_TOP_RIGHT, Vector2(-200, 16), Vector2(176, 30))
	bucks.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	root.add_child(bucks)
	# outfit name plate under the character
	_skin_label = UiStyle.label("", 34, Color.WHITE, 8)
	_place(_skin_label, Control.PRESET_BOTTOM_LEFT, Vector2(40, -120), Vector2(500, 50))
	root.add_child(_skin_label)
	var hint := UiStyle.label("DRAG TO ROTATE", 16, Color(1, 1, 1, 0.7), 4, UiStyle.bold())
	_place(hint, Control.PRESET_BOTTOM_LEFT, Vector2(42, -74), Vector2(300, 24))
	root.add_child(hint)
	# mode card + PLAY
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UiStyle.box(Color(0.05, 0.1, 0.3, 0.85), 6, 2, Color(0.4, 0.6, 1.0, 0.8)))
	_place(card, Control.PRESET_BOTTOM_RIGHT, Vector2(-344, -216), Vector2(320, 76))
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var cv := VBoxContainer.new()
	cv.add_theme_constant_override("separation", 0)
	cv.add_child(UiStyle.label("BATTLE ROYALE", 26, Color.WHITE, 5))
	cv.add_child(UiStyle.label("SOLO  •  100 PLAYERS  •  BUILD", 16, Color(0.7, 0.85, 1.0), 4, UiStyle.bold()))
	card.add_child(cv)
	root.add_child(card)
	var play := Button.new()
	play.text = "PLAY"
	_place(play, Control.PRESET_BOTTOM_RIGHT, Vector2(-344, -128), Vector2(320, 100))
	UiStyle.style_button(play, UiStyle.YELLOW, Color(0.08, 0.06, 0.02), 64, 8)
	var ps: StyleBoxFlat = play.get_theme_stylebox("normal")
	ps.border_width_bottom = 8
	ps.border_color = UiStyle.YELLOW_DARK
	play.pressed.connect(_play)
	root.add_child(play)
	var keyhint := UiStyle.label("ENTER", 14, Color(0.2, 0.15, 0.0), 0, UiStyle.bold())
	_place(keyhint, Control.PRESET_BOTTOM_RIGHT, Vector2(-100, -54), Vector2(60, 20))
	root.add_child(keyhint)
	_locker = _build_locker()
	root.add_child(_locker)
	_settings = _build_settings()
	root.add_child(_settings)


## Anchors `c` to a preset and sets its rect as an offset from that anchor.
static func _place(c: Control, preset: int, off: Vector2, sz: Vector2) -> void:
	c.set_anchors_preset(preset)
	c.offset_left = off.x
	c.offset_top = off.y
	c.offset_right = off.x + sz.x
	c.offset_bottom = off.y + sz.y


func _panel(title: String) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UiStyle.box(Color(0.03, 0.07, 0.22, 0.9), 8, 2, Color(0.35, 0.55, 1.0, 0.7)))
	p.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	p.offset_left = -760
	p.offset_right = -24
	p.offset_top = 84
	p.offset_bottom = -240
	var v := VBoxContainer.new()
	v.name = "V"
	v.add_theme_constant_override("separation", 10)
	v.add_child(UiStyle.label(title, 40, Color.WHITE, 8))
	p.add_child(v)
	return p


func _build_locker() -> Control:
	var p := _panel("LOCKER — OUTFITS")
	var v: VBoxContainer = p.get_node("V")
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(grid)
	var group := ButtonGroup.new()
	for i in Skins.count():
		var d := Skins.get_def(i)
		var b := Button.new()
		b.toggle_mode = true
		b.button_group = group
		b.custom_minimum_size = Vector2(168, 96)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.text = ""
		b.clip_contents = true
		var rarity := clampi(i % 5, 0, 4)
		var rc: Color = Cfg.RARITY_COLORS[rarity]
		b.add_theme_stylebox_override("normal", UiStyle.box(rc.darkened(0.45), 6, 2, rc))
		b.add_theme_stylebox_override("hover", UiStyle.box(rc.darkened(0.3), 6, 3, Color.WHITE))
		b.add_theme_stylebox_override("pressed", UiStyle.box(rc.darkened(0.2), 6, 4, UiStyle.YELLOW))
		b.add_theme_stylebox_override("focus", UiStyle.box(Color(0, 0, 0, 0), 6))
		var sw := Control.new()
		sw.set_anchors_preset(Control.PRESET_FULL_RECT)
		sw.mouse_filter = Control.MOUSE_FILTER_IGNORE
		sw.draw.connect(_draw_swatch.bind(sw, d))
		b.add_child(sw)
		var nm := UiStyle.label(String(d.name).to_upper(), 17, Color.WHITE, 4)
		nm.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
		nm.offset_top = -28
		nm.offset_left = 8
		b.add_child(nm)
		b.pressed.connect(func() -> void: Sfx.play("ui"); _set_skin(i))
		grid.add_child(b)
		_skin_buttons.append(b)
	return p


## Tiny outfit pictogram: head, torso, legs in the outfit's colours.
func _draw_swatch(c: Control, d: Dictionary) -> void:
	var cx := c.size.x - 34.0
	c.draw_rect(Rect2(cx - 13, 30, 26, 22), d.top)
	c.draw_rect(Rect2(cx - 13, 44, 26, 5), d.accent)
	c.draw_rect(Rect2(cx - 11, 52, 9, 16), d.pants)
	c.draw_rect(Rect2(cx + 2, 52, 9, 16), d.pants)
	c.draw_circle(Vector2(cx, 20), 10.0, d.skin)
	if int(d.hair) != Skins.HAIR_NONE:
		c.draw_rect(Rect2(cx - 10, 9, 20, 6), d.hair_col)


func _build_settings() -> Control:
	var p := _panel("SETTINGS")
	var v: VBoxContainer = p.get_node("V")
	var sens := _slider_row(v, "MOUSE SENSITIVITY", 0.0005, 0.008, 0.0001, Cfg.mouse_sens, func(x: float) -> String: return "%.1f" % (x * 1000.0))
	sens.value_changed.connect(func(x: float) -> void: Cfg.mouse_sens = x; Cfg.save_settings())
	var vol := _slider_row(v, "MASTER VOLUME", 0.0, 1.0, 0.01, Cfg.master_volume, func(x: float) -> String: return "%d%%" % roundi(x * 100.0))
	vol.value_changed.connect(func(x: float) -> void: Cfg.master_volume = x; Cfg.save_settings())
	vol.drag_ended.connect(func(_c: bool) -> void: Sfx.play("ui"))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	var l := UiStyle.label("GRAPHICS QUALITY", 24, Color.WHITE, 4)
	l.custom_minimum_size = Vector2(300, 0)
	row.add_child(l)
	var ob := OptionButton.new()
	for q: String in ["LOW", "MEDIUM", "HIGH"]:
		ob.add_item(q)
	ob.selected = clampi(Cfg.quality, 0, 2)
	ob.custom_minimum_size = Vector2(220, 44)
	ob.add_theme_font_override("font", UiStyle.heavy())
	ob.add_theme_font_size_override("font_size", 22)
	ob.item_selected.connect(func(i: int) -> void:
		Cfg.quality = i
		Cfg.save_settings()
		Game.apply_quality())
	row.add_child(ob)
	v.add_child(row)
	var note := UiStyle.label("Settings save automatically.", 16, Color(0.7, 0.8, 1.0), 0, UiStyle.bold())
	v.add_child(note)
	return p


func _slider_row(parent: Control, title: String, lo: float, hi: float, step: float, val: float, fmt: Callable) -> HSlider:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	var l := UiStyle.label(title, 24, Color.WHITE, 4)
	l.custom_minimum_size = Vector2(300, 0)
	row.add_child(l)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = val
	s.custom_minimum_size = Vector2(280, 32)
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(s)
	var vl := UiStyle.label(fmt.call(val), 24, UiStyle.YELLOW, 4)
	vl.custom_minimum_size = Vector2(80, 0)
	row.add_child(vl)
	s.value_changed.connect(func(x: float) -> void: vl.text = fmt.call(x))
	parent.add_child(row)
	return s


func _show_tab(id: String) -> void:
	if id == "quit":
		get_tree().quit()
		return
	_locker.visible = id == "locker"
	_settings.visible = id == "settings"
	for k: String in _tab_buttons:
		(_tab_buttons[k] as Button).set_pressed_no_signal(k == id)


func _play() -> void:
	Sfx.play("ui")
	Game.start_match()
