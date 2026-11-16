extends Node
## Runs a real match for a while: auto-jumps the player, logs alive count,
## FPS and bot states, saves screenshots to /tmp/sf_match_*.png, then quits.

var m: Match
var t := 0.0
var shots := 0
var duration := 110.0

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		duration = float(args[0])
	get_tree().create_timer(duration + 60.0).timeout.connect(get_tree().quit)
	m = Match.new()
	add_child(m)
	await m.loaded
	print("loaded at ", Time.get_ticks_msec())

func _process(delta: float) -> void:
	if m == null or m.player == null:
		return
	t += delta
	if m.player.mode == Pawn.Mode.BUS and m.can_jump() and m.bus_progress() > 0.35:
		m.eject(m.player)
	if m.player.mode in [Pawn.Mode.SKYDIVE, Pawn.Mode.GLIDE]:
		m.player.in_move = Vector2(0, 1)
		m.player.pitch = -1.0
	if int(t) % 10 == 0 and int(t) != int(t - delta):
		var modes := {}
		for pw in m.pawns:
			modes[pw.mode] = modes.get(pw.mode, 0) + 1
		var states := {}
		for b in m.brains:
			states[b.state] = states.get(b.state, 0) + 1
		print("t=%d alive=%d fps=%d modes=%s states=%s storm=%s r=%d player=%s" % [t, m.alive_count(), Engine.get_frames_per_second(), modes, states, m.storm.label(), m.storm.radius, m.player.global_position])
	if t > 8.0 * (shots + 1) and shots < 12:
		shots += 1
		get_viewport().get_texture().get_image().save_png("/tmp/sf_match_%d.png" % shots)
	if t > duration:
		get_tree().quit()
