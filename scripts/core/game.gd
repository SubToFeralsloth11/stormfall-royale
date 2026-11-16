extends Node
## App flow owner (autoload `Game`): intro -> lobby menu -> match -> lobby.
## Also hosts the shared offscreen item-icon renderer used by the HUD.

var current_match: Match
var menu: LobbyMenu
var icons: ItemIcons
var _loading: CanvasLayer
var _starting := false


func _ready() -> void:
	icons = ItemIcons.new()
	add_child(icons)
	apply_quality()


## Scenes we create live under the running main scene (boot), or the root.
func _host() -> Node:
	var cs := get_tree().current_scene
	return cs if cs != null else get_tree().root


func play_intro() -> void:
	var intro := IntroScreen.new()
	intro.finished.connect(show_menu, CONNECT_ONE_SHOT)
	_host().add_child(intro)


func show_menu() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if menu != null and is_instance_valid(menu):
		return
	menu = LobbyMenu.new()
	_host().add_child(menu)


func start_match() -> void:
	if _starting or (current_match != null and is_instance_valid(current_match)):
		return
	_starting = true
	_show_loading()
	if menu != null and is_instance_valid(menu):
		menu.queue_free()
	menu = null
	# let the loading card render before the (blocking) world build starts
	await get_tree().process_frame
	await get_tree().process_frame
	current_match = Match.new()
	current_match.loaded.connect(_on_loaded, CONNECT_ONE_SHOT)
	_host().add_child(current_match)


func _on_loaded() -> void:
	_starting = false
	if _loading != null and is_instance_valid(_loading):
		_loading.queue_free()
	_loading = null


func return_to_menu() -> void:
	_starting = false
	Sfx.stop_all_loops()
	if current_match != null and is_instance_valid(current_match):
		current_match.queue_free()
	current_match = null
	if _loading != null and is_instance_valid(_loading):
		_loading.queue_free()
	_loading = null
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	show_menu()


## Cfg.quality 0..2 -> 3D render scale and MSAA on the main viewport.
func apply_quality() -> void:
	var vp := get_viewport()
	var q := clampi(Cfg.quality, 0, 2)
	vp.scaling_3d_scale = [0.67, 0.85, 1.0][q]
	vp.msaa_3d = [Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_4X][q]


func _show_loading() -> void:
	_loading = CanvasLayer.new()
	_loading.layer = 90
	var c := Control.new()
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.draw.connect(_draw_loading.bind(c))
	_loading.add_child(c)
	add_child(_loading)


const TIPS := [
	"Build a ramp to take the high ground. Or don't. We're not your mum.",
	"The storm hurts. Stand in the circle.",
	"Shield potions go in the blue bar. Bandages go in the green one.",
	"Metal is strong but slow to build. Wood is fast but cheap. Like this game.",
	"Free shipping on all Victory Royales over 100 eliminations.",
]


func _draw_loading(c: Control) -> void:
	var s := c.size
	var u := s.y / 900.0
	c.draw_rect(Rect2(Vector2.ZERO, s), Color(0.06, 0.1, 0.34))
	for i in 14:
		var x := s.x * (i / 13.0)
		c.draw_colored_polygon(PackedVector2Array([Vector2(x - 80 * u, s.y), Vector2(x + 30 * u, 0), Vector2(x + 90 * u, 0), Vector2(x - 20 * u, s.y)]),
			Color(0.12, 0.2, 0.5, 0.35))
	UiStyle.text(c, Vector2(60, s.y - 210 * u), "BATTLE ROYALE", int(70 * u), Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, UiStyle.heavy())
	UiStyle.text(c, Vector2(64, s.y - 160 * u), "DROPPING IN... BUILDING THE ISLAND", int(28 * u), UiStyle.YELLOW, HORIZONTAL_ALIGNMENT_LEFT, -1, 6)
	var tip: String = TIPS[Time.get_ticks_msec() / 7 % TIPS.size()]
	UiStyle.text(c, Vector2(64, s.y - 90 * u), "TIP: " + tip, int(22 * u), Color(0.8, 0.9, 1.0), HORIZONTAL_ALIGNMENT_LEFT, -1, 4)
	UiStyle.text(c, Vector2(s.x - 360 * u, 70 * u), "FORTNITE", int(56 * u), Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, UiStyle.heavy())
	UiStyle.text(c, Vector2(s.x - 300 * u, 104 * u), "TEMU EDITION", int(26 * u), Color(1.0, 0.25, 0.25), HORIZONTAL_ALIGNMENT_LEFT, -1, 5)
