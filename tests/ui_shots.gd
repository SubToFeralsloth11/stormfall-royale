extends Node
## Visual check of the UI flow: intro -> lobby (locker, settings) -> match HUD
## (inventory, build mode, map, end screen) -> back to lobby. Saves
## /tmp/ftemu_*.png and quits. Run windowed:
##   godot --path . res://tests/ui_shots.tscn

var _fake_storm := false


func _ready() -> void:
	process_priority = 100     # run after the HUD so the fake storm info is what gets drawn
	get_tree().create_timer(150.0).timeout.connect(get_tree().quit)
	Game.play_intro()
	await _wait(0.9)
	await _shot("intro_title")
	await _wait(0.75)
	await _shot("intro_stamp")
	await _wait(0.6)
	await _shot("intro_stamp_hold")
	await _wait(1.8)
	await _shot("lobby")
	var menu: LobbyMenu = Game.menu
	menu._show_tab("locker")
	menu._set_skin(7)
	await _wait(0.6)
	await _shot("locker")
	menu._show_tab("settings")
	await _wait(0.3)
	await _shot("settings")
	menu._show_tab("lobby")
	menu._set_skin(0)
	Game.start_match()
	await _wait(0.05)
	await _shot("loading")
	while Game.current_match == null or Game.current_match.player == null or Game.current_match.controller == null or Game.current_match.controller.hud == null:
		await get_tree().process_frame
	await _wait(1.0)
	await _shot("hud_skydive")
	var p := Game.current_match.player
	var hud := Game.current_match.controller.hud
	p.inventory = [Items.make_weapon("ar", 3), Items.make_weapon("pump", 2), {"id": "shieldpot", "rarity": 2, "count": 2}, Items.make_weapon("smg", 4), {}]
	p.mats = [230, 120, 45]
	p.ammo = {"light": 120, "medium": 210, "heavy": 6, "shells": 24, "rockets": 0}
	p.shield = 75.0
	p.health = 82.0
	p.stamina = 60.0
	p.kills = 3
	hud.push_kill("You eliminated Bot 12 with Assault Rifle")
	hud.push_kill("Bot 40 eliminated Bot 7 with Pump Shotgun")
	hud.set_hint("[E] Open chest")
	_fake_storm = true
	while p.mode != Pawn.Mode.GROUND:
		await get_tree().process_frame
		if p.mode == Pawn.Mode.SKYDIVE and p.height_above_ground() > 200.0:
			p.global_position.y -= 6.0
	p.select_slot(1)
	await _wait(1.0)
	hud.hit_marker(true)
	hud.flash_damage(30.0)
	await _wait(0.05)
	await _shot("hud_ground")
	p.set_build_mode(true, PieceMeshes.Kind.RAMP)
	p.build_mat = 1
	await _wait(0.3)
	await _shot("hud_build")
	p.set_build_mode(false)
	var ev := InputEventAction.new()
	ev.action = "map"
	ev.pressed = true
	Input.parse_input_event(ev)
	await _wait(0.4)
	await _shot("map")
	Input.parse_input_event(ev)
	await _wait(0.2)
	hud.show_end(1, 7, true)
	await _wait(0.8)
	await _shot("victory")
	Game.return_to_menu()
	await _wait(1.0)
	await _shot("lobby_return")
	get_tree().quit()


func _process(_d: float) -> void:
	if not _fake_storm or Game.current_match == null or not is_instance_valid(Game.current_match):
		return
	var m := Game.current_match
	if m.controller == null or m.controller.hud == null:
		return
	var pp := Vector2(m.player.global_position.x, m.player.global_position.z)
	var info: Dictionary = m.controller.hud._info
	info.merge({"phase": 2, "storm_label": "Storm closing 1:25", "storm_center": pp + Vector2(160, 90),
		"storm_radius": 260.0, "next_center": pp + Vector2(120, -40), "next_radius": 110.0,
		"bus_path": [Vector2(-1400, -900), Vector2(1300, 1100)], "in_storm": false}, true)


func _wait(t: float) -> void:
	await get_tree().create_timer(t).timeout


func _shot(n: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("/tmp/ftemu_%s.png" % n)
	print("shot ", n)
