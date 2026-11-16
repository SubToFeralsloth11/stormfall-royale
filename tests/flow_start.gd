extends Node
## Reproduces the lobby PLAY path: menu -> Game.start_match(), runs 25 s.

func _ready() -> void:
	get_tree().create_timer(60.0).timeout.connect(get_tree().quit)
	var args := OS.get_cmdline_user_args()
	if args.size() >= 2:
		Cfg.quality = int(args[0])
		Cfg.selected_skin = int(args[1])
		Game.apply_quality()
	Game.show_menu()
	await get_tree().create_timer(1.0).timeout
	print("FLOW start_match")
	Game.start_match()
	while Game.current_match == null or Game.current_match.player == null:
		await get_tree().process_frame
	print("FLOW loaded, mem MB=", OS.get_static_memory_usage() / 1048576)
	for i in 4:
		await get_tree().create_timer(5.0).timeout
		print("FLOW t=", (i + 1) * 5, " mem MB=", OS.get_static_memory_usage() / 1048576, " fps=", Engine.get_frames_per_second())
	print("FLOW ok")
	get_tree().quit()
