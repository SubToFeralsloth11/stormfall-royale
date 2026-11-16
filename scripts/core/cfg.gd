extends Node
## Global constants (metres, seconds) and input bindings.
## Measurements follow published battle-royale reference values:
## build tile 5.12 m x 3.84 m (Epic UEFN modeling guidelines),
## run 5.48 m/s, crouch-run 4.18, sprint 7.39, glide 18.5 m/s horizontal,
## auto-deploy 100 m above ground, storm phase table (12 phases).

# --- World ---
const MAP_SIZE := 3000.0            # island square, metres (storm phase 0 radius 1500 m)
const WORLD_HALF := MAP_SIZE * 0.5
const TERRAIN_STEP := 6.0           # heightmap cell size (m)
const SEA_LEVEL := 0.0
const TILE := 5.12                  # build grid width
const LEVEL := 3.84                 # build grid height
const PIECE_THICK := 0.24

# --- Player body ---
const CAPSULE_RADIUS := 0.36
const CAPSULE_HEIGHT := 1.8
const CROUCH_HEIGHT := 1.2
const EYE_HEIGHT := 1.62

# --- Movement ---
const RUN_SPEED := 5.48
const CROUCH_SPEED := 4.18
const SPRINT_SPEED := 7.39
const SWIM_SPEED := 5.49
const WADE_SPEED := 2.5
const BACKPEDAL_MULT := 0.85
const ADS_MULT := 0.7
const GROUND_ACCEL := 60.0
const AIR_ACCEL := 9.0
const GRAVITY := 24.0
const JUMP_VELOCITY := 8.6          # ~1.55 m apex
const MAX_FALL := 37.0
const STAMINA_MAX := 100.0
const STAMINA_DRAIN := 15.0         # per second sprinting (~6.7 s)
const STAMINA_REGEN := 16.0
const SLIDE_MIN_SPEED := 6.0
const SLIDE_FRICTION := 4.5
const MANTLE_MAX := 2.3             # metres above feet you can pull up onto
const FALL_SAFE := 9.0              # fall distance without damage
const FALL_LETHAL := 30.0

# --- Drop ---
const BUS_HEIGHT := 830.0
const BUS_SPEED := 55.0
const DIVE_MAX_VERTICAL := 60.0
const DIVE_MIN_VERTICAL := 25.0
const DIVE_HORIZONTAL := 30.0
const GLIDE_HORIZONTAL := 18.5
const GLIDE_VERTICAL := 12.0
const AUTO_DEPLOY := 100.0

# --- Combat ---
const MAX_HEALTH := 100.0
const MAX_SHIELD := 100.0
const MAX_MATS := 999
const BUILD_COST := 10
const BUILD_RANGE := 7.0
const PICKAXE_STRUCT_DMG := 50.0
const PICKAXE_PLAYER_DMG := 20.0
const INVENTORY_SLOTS := 5

# --- Storm phases: [wait s, shrink s, damage/s, radius m, move m] ---
const STORM_PHASES := [
	[60.0, 0.0, 1.0, 1500.0, 0.0],
	[110.0, 85.0, 1.0, 950.0, 0.0],
	[60.0, 90.0, 1.0, 725.0, 0.0],
	[70.0, 110.0, 1.0, 500.0, 0.0],
	[50.0, 80.0, 1.0, 400.0, 0.0],
	[30.0, 65.0, 1.0, 225.0, 0.0],
	[35.0, 70.0, 2.0, 120.0, 0.0],
	[35.0, 70.0, 5.0, 60.0, 150.0],
	[25.0, 60.0, 8.0, 40.0, 120.0],
	[10.0, 60.0, 10.0, 20.0, 120.0],
	[1.0, 50.0, 10.0, 13.5, 48.0],
	[1.0, 50.0, 10.0, 10.0, 66.0],
	[1.0, 80.0, 10.0, 0.0, 0.0],
]

# --- Rarity ---
enum Rarity { COMMON, UNCOMMON, RARE, EPIC, LEGENDARY }
const RARITY_COLORS := [
	Color(0.62, 0.65, 0.68), Color(0.33, 0.78, 0.25), Color(0.2, 0.55, 1.0),
	Color(0.68, 0.3, 0.95), Color(1.0, 0.62, 0.15),
]
const RARITY_NAMES := ["Common", "Uncommon", "Rare", "Epic", "Legendary"]

# --- Collision layers ---
const L_WORLD := 1        # terrain, props
const L_BUILD := 2        # structures
const L_PAWN := 4
const L_PICKUP := 8
const L_WATER := 16

# --- Settings (persisted) ---
var mouse_sens := 0.0022
var ads_sens_mult := 0.65
var quality := 1      # 0 low, 1 medium, 2 high
var selected_skin := 0
var master_volume := 0.8
const SETTINGS_PATH := "user://settings.cfg"

const BINDINGS := {
	"move_forward": [KEY_W], "move_back": [KEY_S], "move_left": [KEY_A], "move_right": [KEY_D],
	"jump": [KEY_SPACE], "sprint": [KEY_SHIFT], "crouch": [KEY_CTRL, KEY_C],
	"interact": [KEY_E], "reload": [KEY_R], "edit": [KEY_G], "map": [KEY_M],
	"build_wall": [KEY_Q, KEY_F1], "build_floor": [KEY_Z, KEY_F2], "build_stair": [KEY_X, KEY_F3],
	"build_cone": [KEY_V, KEY_F4], "build_toggle": [KEY_B], "cycle_mat": [KEY_T],
	"slot_0": [KEY_1], "slot_1": [KEY_2], "slot_2": [KEY_3], "slot_3": [KEY_4], "slot_4": [KEY_5], "slot_5": [KEY_6],
	"emote": [KEY_H], "pause": [KEY_ESCAPE], "drop_item": [KEY_K],
}


func _ready() -> void:
	_register_inputs()
	load_settings()


func _register_inputs() -> void:
	for action: String in BINDINGS:
		if not InputMap.has_action(action):
			InputMap.add_action(action, 0.2)
		for key: int in BINDINGS[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = key
			InputMap.action_add_event(action, ev)
	_add_mouse("fire", MOUSE_BUTTON_LEFT)
	_add_mouse("aim", MOUSE_BUTTON_RIGHT)


func _add_mouse(action: String, button: int) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	InputMap.action_add_event(action, ev)


func load_settings() -> void:
	var cf := ConfigFile.new()
	if cf.load(SETTINGS_PATH) != OK:
		return
	mouse_sens = cf.get_value("input", "mouse_sens", mouse_sens)
	ads_sens_mult = cf.get_value("input", "ads_sens_mult", ads_sens_mult)
	quality = cf.get_value("video", "quality", quality)
	selected_skin = cf.get_value("player", "skin", selected_skin)
	master_volume = cf.get_value("audio", "volume", master_volume)
	apply_volume()


func save_settings() -> void:
	var cf := ConfigFile.new()
	cf.set_value("input", "mouse_sens", mouse_sens)
	cf.set_value("input", "ads_sens_mult", ads_sens_mult)
	cf.set_value("video", "quality", quality)
	cf.set_value("player", "skin", selected_skin)
	cf.set_value("audio", "volume", master_volume)
	cf.save(SETTINGS_PATH)
	apply_volume()


func apply_volume() -> void:
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(master_volume, 0.001)))


## Grid helpers -------------------------------------------------------------

static func cell_of(p: Vector3) -> Vector3i:
	return Vector3i(floori(p.x / TILE), floori(p.y / LEVEL + 0.001), floori(p.z / TILE))


static func cell_origin(c: Vector3i) -> Vector3:
	return Vector3(c.x * TILE, c.y * LEVEL, c.z * TILE)


static func cell_center(c: Vector3i) -> Vector3:
	return Vector3((c.x + 0.5) * TILE, c.y * LEVEL, (c.z + 0.5) * TILE)
