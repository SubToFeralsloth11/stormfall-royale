class_name CharacterRig
extends Node3D
## Procedurally built skinned character (one draw call) with a code-driven
## animation layer: locomotion, crouch, slide, jump, skydive, glide, swim,
## weapon holds, pickaxe swing, building, healing, reload, hit flinch, emotes.
## Character faces -Z; its right side is +X.

enum Pose { GROUND, AIR, SKYDIVE, GLIDE, SWIM, SLIDE, DEAD }

const BONES := [
	# name, parent, rest offset from parent
	["root", -1, Vector3(0, 0, 0)],
	["hips", 0, Vector3(0, 0.95, 0)],
	["spine", 1, Vector3(0, 0.16, 0)],
	["chest", 2, Vector3(0, 0.2, 0)],
	["neck", 3, Vector3(0, 0.2, 0)],
	["head", 4, Vector3(0, 0.08, 0)],
	["l_arm", 3, Vector3(-0.24, 0.08, 0)],
	["l_fore", 6, Vector3(0, -0.28, 0)],
	["l_hand", 7, Vector3(0, -0.25, 0)],
	["r_arm", 3, Vector3(0.24, 0.08, 0)],
	["r_fore", 9, Vector3(0, -0.28, 0)],
	["r_hand", 10, Vector3(0, -0.25, 0)],
	["l_thigh", 1, Vector3(-0.1, -0.04, 0)],
	["l_shin", 12, Vector3(0, -0.43, 0)],
	["l_foot", 13, Vector3(0, -0.42, 0)],
	["r_thigh", 1, Vector3(0.1, -0.04, 0)],
	["r_shin", 15, Vector3(0, -0.43, 0)],
	["r_foot", 16, Vector3(0, -0.42, 0)],
]
const B_ROOT := 0
const B_HIPS := 1
const B_SPINE := 2
const B_CHEST := 3
const B_NECK := 4
const B_HEAD := 5
const B_LARM := 6
const B_LFORE := 7
const B_LHAND := 8
const B_RARM := 9
const B_RFORE := 10
const B_RHAND := 11
const B_LTHIGH := 12
const B_LSHIN := 13
const B_LFOOT := 14
const B_RTHIGH := 15
const B_RSHIN := 16
const B_RFOOT := 17

static var _mesh_cache := {}
static var _material: StandardMaterial3D

var skeleton: Skeleton3D
var body: MeshInstance3D
var hand_attach: BoneAttachment3D
var back_attach: BoneAttachment3D
var held: MeshInstance3D
var glider: MeshInstance3D
var skin_index := 0

# --- animation inputs (written by the pawn every frame) ---
var pose := Pose.GROUND
var move_local := Vector2.ZERO   # x = right, y = forward, in m/s
var sprinting := false
var crouching := false
var hold := "pickaxe"            # pickaxe, rifle, pistol, shotgun, sniper, rocket, consumable, build, none
var aim_pitch := 0.0             # radians, + looks up
var dive := 0.0                  # 0..1 skydive pitch
var swing_t := -1.0              # pickaxe swing progress (0..1) or <0
var fire_kick := 0.0
var reload_t := -1.0
var heal_t := -1.0
var build_t := -1.0
var flinch := 0.0
var emote := -1
var emote_t := 0.0
var lod_skip := 0                # frames to skip (set by owner for far characters)

var swing_combo := 0             # alternates forehand / backhand pickaxe swings
var land_t := -1.0               # landing squash timer
var ads := false

var _phase := 0.0
var _cur := {}                   # bone -> Vector3 euler (smoothed)
var _hip_y := 0.0
var _frame := 0
var _hand_r := {}                # smoothed IK targets: pos, fwd, up (aim-frame space)
var _hand_l := {}
var _ik_w_r := 0.0
var _ik_w_l := 0.0
var _trail: MeshInstance3D
var _trail_pts: Array[Vector3] = []


static func _mat() -> StandardMaterial3D:
	if _material == null:
		_material = MeshBuilder.vc_material(0.7)
	return _material


func setup(skin: int) -> void:
	skin_index = posmod(skin, Skins.count())
	skeleton = Skeleton3D.new()
	add_child(skeleton)
	for b: Array in BONES:
		var idx := skeleton.add_bone(b[0])
		if b[1] >= 0:
			skeleton.set_bone_parent(idx, b[1])
		skeleton.set_bone_rest(idx, Transform3D(Basis.IDENTITY, b[2]))
	skeleton.reset_bone_poses()
	body = MeshInstance3D.new()
	body.mesh = _skin_mesh(skin_index)
	body.material_override = _mat()
	skeleton.add_child(body)
	body.skeleton = NodePath("..")
	body.skin = skeleton.create_skin_from_rest_transforms()
	body.visibility_range_end = 900.0
	hand_attach = BoneAttachment3D.new()
	skeleton.add_child(hand_attach)
	hand_attach.bone_name = "r_hand"
	held = MeshInstance3D.new()
	held.material_override = _mat()
	held.rotation = Vector3(-PI * 0.5, 0, 0)
	held.position = Vector3(0, -0.06, 0)
	held.visibility_range_end = 300.0
	hand_attach.add_child(held)
	back_attach = BoneAttachment3D.new()
	skeleton.add_child(back_attach)
	back_attach.bone_name = "chest"
	glider = MeshInstance3D.new()
	glider.mesh = ItemMeshes.get_mesh("glider", skin_index)
	var gm := MeshBuilder.vc_material(0.7)
	gm.cull_mode = BaseMaterial3D.CULL_DISABLED
	glider.material_override = gm
	glider.visible = false
	glider.position = Vector3(0, -0.3, 0)
	add_child(glider)
	for i in BONES.size():
		_cur[i] = Vector3.ZERO


func set_held_mesh(mesh_id: String, rarity := 0) -> void:
	if mesh_id == "":
		held.mesh = null
		return
	held.mesh = ItemMeshes.get_mesh(mesh_id, rarity)
	if mesh_id == "pickaxe":
		held.rotation = Vector3(-PI * 0.5, 0, 0)   # handle runs along the hand's -Z ("up") axis
		held.position = Vector3(0, -0.07, 0.12)
	elif Items.CONSUMABLES.has(mesh_id):
		held.rotation = Vector3.ZERO
		held.position = Vector3(0, -0.12, 0)
	else:
		held.rotation = Vector3(-PI * 0.5, 0, 0)
		held.position = Vector3(0, -0.06, 0.02)


# ------------------------------------------------------------------ mesh

static func _skin_mesh(i: int) -> ArrayMesh:
	if _mesh_cache.has(i):
		return _mesh_cache[i]
	var s: Dictionary = Skins.get_def(i)
	var mb := MeshBuilder.new()
	MeshBuilder.detail = 2.0
	mb.skinned = true
	var w: float = s.build
	var skin: Color = s.skin
	var top: Color = s.top
	var acc: Color = s.accent
	var pants: Color = s.pants
	var shoes: Color = s.shoes
	var gloves: Color = s.gloves
	var fur: bool = s.extra == "fur"
	# hips / pelvis
	mb.bone = B_HIPS
	mb.sphere(Vector3(0, 0.93, 0), Vector3(0.185 * w, 0.14, 0.135 * w), 4, 10, pants)
	mb.cylinder(Vector3(0, 0.98, 0), 0.06, 0.165 * w, 0.165 * w, 10, acc, false)   # belt
	# torso
	mb.bone = B_SPINE
	mb.cylinder(Vector3(0, 1.0, 0), 0.22, 0.17 * w, 0.19 * w, 10, top, false)
	mb.bone = B_CHEST
	mb.sphere(Vector3(0, 1.28, 0), Vector3(0.225 * w, 0.18, 0.15 * w), 5, 10, top)
	mb.sphere(Vector3(0, 1.3, -0.02), Vector3(0.12 * w, 0.1, 0.12 * w), 3, 8, acc)  # chest panel
	if s.extra == "overalls":
		mb.box(Vector3(0, 1.2, -0.125 * w), Vector3(0.2, 0.25, 0.03), pants)
		for x: float in [-0.08, 0.08]:
			mb.box(Vector3(x, 1.33, -0.12 * w), Vector3(0.04, 0.2, 0.03), pants)
	if s.extra == "scarf":
		mb.cylinder(Vector3(0, 1.38, 0), 0.08, 0.12, 0.1, 10, acc)
	if fur:
		mb.sphere(Vector3(0, 1.22, 0), Vector3(0.25 * w, 0.24, 0.17 * w), 4, 10, top)
	# neck + head
	mb.bone = B_NECK
	mb.cylinder(Vector3(0, 1.38, 0), 0.1, 0.055, 0.05, 8, skin)
	mb.bone = B_HEAD
	_head(mb, s)
	# arms
	for side: float in [-1.0, 1.0]:
		var sh := Vector3(0.24 * side * w, 1.39, 0)
		var el := sh + Vector3(0.0, -0.28, 0)
		var wr := el + Vector3(0, -0.25, 0)
		var sleeve: Color = top if s.sleeves == "long" else skin
		mb.bone = B_LARM if side < 0 else B_RARM
		mb.sphere(sh + Vector3(-0.02 * side, 0.01, 0), Vector3(0.095, 0.08, 0.085) * w, 3, 8, top)
		mb.limb(sh, el, 0.078 * w, 0.066 * w, sleeve if s.sleeves == "long" else skin, 8)
		if s.sleeves == "short":
			mb.cylinder(sh + Vector3(0, -0.1, 0), 0.1, 0.075 * w, 0.075 * w, 8, top, false)
		if s.extra == "pauldrons":
			mb.sphere(sh + Vector3(0.03 * side, 0.02, 0), Vector3(0.11, 0.08, 0.11) * w, 3, 8, acc)
		mb.bone = B_LFORE if side < 0 else B_RFORE
		mb.limb(el, wr, 0.066 * w, 0.055 * w, top if s.sleeves == "long" else skin, 8)
		mb.cylinder(wr + Vector3(0, 0.02, 0), 0.06, 0.05 * w, 0.05 * w, 8, gloves, false)
		mb.bone = B_LHAND if side < 0 else B_RHAND
		mb.sphere(wr + Vector3(0, -0.06, 0), Vector3(0.055, 0.07, 0.045) * w, 3, 8, gloves)
	# legs
	for side: float in [-1.0, 1.0]:
		var hp := Vector3(0.1 * side * w, 0.91, 0)
		var kn := Vector3(0.1 * side * w, 0.48, 0)
		var an := Vector3(0.1 * side * w, 0.08, 0)
		mb.bone = B_LTHIGH if side < 0 else B_RTHIGH
		mb.limb(hp, kn, 0.1 * w, 0.078 * w, pants, 8)
		mb.bone = B_LSHIN if side < 0 else B_RSHIN
		mb.limb(kn, an, 0.078 * w, 0.06 * w, pants, 8)
		mb.cylinder(an + Vector3(0, 0.05, 0), 0.12, 0.075 * w, 0.08 * w, 8, shoes)
		mb.bone = B_LFOOT if side < 0 else B_RFOOT
		mb.sphere(an + Vector3(0, -0.02, -0.06), Vector3(0.078 * w, 0.065, 0.14), 3, 8, shoes)
	# back bling (on chest bone)
	mb.bone = B_CHEST
	_back(mb, s)
	MeshBuilder.detail = 1.0
	var m := mb.build()
	_mesh_cache[i] = m
	return m


static func _head(mb: MeshBuilder, s: Dictionary) -> void:
	var c := Vector3(0, 1.62, 0)
	var skin: Color = s.skin
	var hc: Color = s.hair_col
	var hat: String = s.hat
	if hat == "robot":
		mb.sphere(c, Vector3(0.15, 0.15, 0.15), 5, 12, Color(0.6, 0.62, 0.66))
		mb.box(c + Vector3(0, 0.01, -0.13), Vector3(0.2, 0.06, 0.05), s.accent)
		mb.limb(c + Vector3(0, 0.14, 0), c + Vector3(0, 0.27, 0), 0.012, 0.012, Color(0.3, 0.3, 0.3), 4)
		mb.sphere(c + Vector3(0, 0.28, 0), Vector3.ONE * 0.03, 2, 6, s.accent)
		return
	mb.sphere(c, Vector3(0.135, 0.15, 0.14), 5, 12, skin)
	mb.sphere(c + Vector3(0, -0.07, -0.02), Vector3(0.11, 0.08, 0.11), 3, 10, skin)   # jaw
	# face
	var eye := Color(0.08, 0.08, 0.1)
	for side: float in [-1.0, 1.0]:
		mb.sphere(c + Vector3(0.05 * side, 0.015, -0.125), Vector3(0.022, 0.028, 0.012), 2, 6, Color(0.98, 0.98, 0.98))
		mb.sphere(c + Vector3(0.05 * side, 0.012, -0.133), Vector3(0.012, 0.016, 0.008), 2, 6, eye)
		mb.box(c + Vector3(0.05 * side, 0.06, -0.128), Vector3(0.045, 0.012, 0.012), hc if int(s.hair) != Skins.HAIR_NONE else Color(0.25, 0.18, 0.12))
	mb.sphere(c + Vector3(0, -0.02, -0.14), Vector3(0.018, 0.022, 0.02), 2, 6, skin.darkened(0.08))
	mb.box(c + Vector3(0, -0.07, -0.128), Vector3(0.05, 0.01, 0.01), Color(0.5, 0.25, 0.22))
	match s.extra:
		"beard":
			mb.sphere(c + Vector3(0, -0.09, -0.05), Vector3(0.12, 0.09, 0.1), 3, 10, hc if s.hair != 0 else Color(0.3, 0.2, 0.12))
		"goggles":
			for side: float in [-1.0, 1.0]:
				mb.cylinder(c + Vector3(0.05 * side, 0.015, -0.145), 0.02, 0.035, 0.035, 8, Color(0.2, 0.75, 0.95))
			mb.cylinder(c + Vector3(0, 0.0, 0), 0.03, 0.142, 0.142, 12, Color(0.15, 0.15, 0.15), false)
		"mask":
			mb.sphere(c + Vector3(0, -0.06, -0.06), Vector3(0.125, 0.07, 0.1), 3, 10, s.top.darkened(0.2))
		"bandana":
			mb.sphere(c + Vector3(0, -0.07, -0.05), Vector3(0.125, 0.065, 0.1), 3, 10, Color(0.8, 0.15, 0.15))
	_hair(mb, s, c)
	_hat(mb, s, c)



static func _hair(mb: MeshBuilder, s: Dictionary, c: Vector3) -> void:
	var hc: Color = s.hair_col
	var hidden: bool = s.hat in ["hood", "foxhood", "space", "knight", "hardhat"]
	if hidden:
		return
	match int(s.hair):
		Skins.HAIR_SHORT:
			mb.sphere(c + Vector3(0, 0.035, 0.01), Vector3(0.145, 0.135, 0.15), 4, 12, hc, 0.45, 1.0)
		Skins.HAIR_LONG:
			mb.sphere(c + Vector3(0, 0.035, 0.01), Vector3(0.15, 0.14, 0.155), 4, 12, hc, 0.4, 1.0)
			mb.sphere(c + Vector3(0, -0.12, 0.07), Vector3(0.15, 0.2, 0.09), 4, 10, hc)
		Skins.HAIR_BUN:
			mb.sphere(c + Vector3(0, 0.035, 0.01), Vector3(0.145, 0.135, 0.15), 4, 12, hc, 0.45, 1.0)
			mb.sphere(c + Vector3(0, 0.17, 0.05), Vector3.ONE * 0.075, 3, 10, hc)
		Skins.HAIR_MOHAWK:
			for k in 5:
				var z := -0.1 + k * 0.05
				mb.cylinder(c + Vector3(0, 0.1, z), 0.12 - absf(k - 2) * 0.02, 0.03, 0.0, 6, hc)
		Skins.HAIR_PONY:
			mb.sphere(c + Vector3(0, 0.035, 0.01), Vector3(0.145, 0.135, 0.15), 4, 12, hc, 0.45, 1.0)
			mb.limb(c + Vector3(0, 0.05, 0.14), c + Vector3(0, -0.2, 0.2), 0.05, 0.03, hc, 6)
		Skins.HAIR_CURLY:
			for k in 9:
				var a := TAU * k / 9.0
				mb.sphere(c + Vector3(cos(a) * 0.11, 0.08 + sin(k * 1.7) * 0.02, sin(a) * 0.11 + 0.02), Vector3.ONE * 0.075, 3, 7, hc)
			mb.sphere(c + Vector3(0, 0.13, 0.01), Vector3.ONE * 0.1, 3, 8, hc)
		Skins.HAIR_SPIKY:
			mb.sphere(c + Vector3(0, 0.03, 0.01), Vector3(0.143, 0.13, 0.148), 4, 12, hc, 0.5, 1.0)
			for k in 7:
				var a := TAU * k / 7.0
				var base := c + Vector3(cos(a) * 0.07, 0.11, sin(a) * 0.07 + 0.02)
				var tip := base + Vector3(cos(a) * 0.08, 0.1, sin(a) * 0.08)
				mb.limb(base, tip, 0.035, 0.005, hc, 5)


static func _hat(mb: MeshBuilder, s: Dictionary, c: Vector3) -> void:
	var acc: Color = s.accent
	match String(s.hat):
		"hood":
			mb.sphere(c + Vector3(0, 0.03, 0.02), Vector3(0.17, 0.18, 0.18), 5, 12, s.top, 0.25, 1.0)
		"foxhood":
			mb.sphere(c + Vector3(0, 0.03, 0.02), Vector3(0.17, 0.18, 0.18), 5, 12, acc, 0.25, 1.0)
			for side: float in [-1.0, 1.0]:
				mb.cylinder(c + Vector3(0.09 * side, 0.15, 0.02), 0.13, 0.05, 0.0, 6, acc)
		"cowboy":
			mb.cylinder(c + Vector3(0, 0.1, 0), 0.02, 0.27, 0.27, 14, Color(0.55, 0.36, 0.2))
			mb.cylinder(c + Vector3(0, 0.1, 0), 0.13, 0.13, 0.11, 12, Color(0.55, 0.36, 0.2))
		"straw":
			mb.cylinder(c + Vector3(0, 0.1, 0), 0.02, 0.26, 0.26, 14, Color(0.95, 0.85, 0.5))
			mb.sphere(c + Vector3(0, 0.12, 0), Vector3(0.13, 0.09, 0.13), 3, 12, Color(0.95, 0.85, 0.5), 0.5, 1.0)
		"beanie":
			mb.sphere(c + Vector3(0, 0.05, 0.01), Vector3(0.15, 0.14, 0.155), 4, 12, acc, 0.5, 1.0)
			mb.sphere(c + Vector3(0, 0.2, 0.01), Vector3.ONE * 0.04, 2, 6, acc.lightened(0.3))
		"hardhat":
			mb.sphere(c + Vector3(0, 0.06, 0), Vector3(0.16, 0.13, 0.17), 4, 12, Color(1.0, 0.85, 0.15), 0.5, 1.0)
			mb.cylinder(c + Vector3(0, 0.06, -0.02), 0.015, 0.2, 0.2, 12, Color(1.0, 0.85, 0.15))
		"space":
			mb.sphere(c, Vector3.ONE * 0.22, 6, 14, Color(0.75, 0.88, 1.0))
			mb.cylinder(c + Vector3(0, -0.2, 0), 0.05, 0.14, 0.14, 12, Color(0.9, 0.9, 0.92))
		"knight":
			mb.sphere(c + Vector3(0, 0.02, 0), Vector3(0.17, 0.19, 0.18), 5, 12, Color(0.7, 0.72, 0.76))
			mb.box(c + Vector3(0, 0.01, -0.17), Vector3(0.18, 0.025, 0.02), Color(0.1, 0.1, 0.1))
			mb.limb(c + Vector3(0, 0.18, 0.03), c + Vector3(0, 0.25, 0.2), 0.04, 0.02, acc, 6)
		"visor":
			mb.sphere(c + Vector3(0, 0.03, 0), Vector3(0.155, 0.15, 0.16), 4, 12, s.top, 0.45, 1.0)
			mb.sphere(c + Vector3(0, 0.02, -0.06), Vector3(0.15, 0.06, 0.11), 3, 12, Color(0.2, 0.2, 0.25))
		"crown":
			mb.cylinder(c + Vector3(0, 0.11, 0), 0.06, 0.12, 0.13, 10, acc, false)
			for k in 6:
				var a := TAU * k / 6.0
				mb.cylinder(c + Vector3(cos(a) * 0.12, 0.17, sin(a) * 0.12), 0.07, 0.025, 0.0, 5, acc)


static func _back(mb: MeshBuilder, s: Dictionary) -> void:
	var acc: Color = s.accent
	var b := Vector3(0, 1.25, 0.16 * float(s.build))
	match String(s.back):
		"backpack":
			mb.sphere(b + Vector3(0, 0, 0.04), Vector3(0.16, 0.2, 0.09), 4, 10, acc)
			mb.box(b + Vector3(0, -0.08, 0.12), Vector3(0.18, 0.08, 0.04), acc.darkened(0.2))
		"jetpack":
			for side: float in [-1.0, 1.0]:
				mb.cylinder(b + Vector3(0.08 * side, -0.2, 0.06), 0.36, 0.065, 0.065, 10, Color(0.6, 0.62, 0.66))
				mb.cylinder(b + Vector3(0.08 * side, 0.16, 0.06), 0.06, 0.065, 0.0, 10, acc)
		"cape":
			mb.quad(b + Vector3(-0.2, 0.15, 0.0), b + Vector3(0.2, 0.15, 0.0), b + Vector3(0.28, -0.75, 0.12), b + Vector3(-0.28, -0.75, 0.12), acc)
			mb.quad(b + Vector3(0.2, 0.15, -0.01), b + Vector3(-0.2, 0.15, -0.01), b + Vector3(-0.28, -0.75, 0.11), b + Vector3(0.28, -0.75, 0.11), acc.darkened(0.25))
		"tanks":
			for side: float in [-1.0, 1.0]:
				mb.cylinder(b + Vector3(0.08 * side, -0.2, 0.05), 0.42, 0.07, 0.07, 10, acc)
				mb.sphere(b + Vector3(0.08 * side, 0.22, 0.05), Vector3.ONE * 0.07, 3, 10, acc, 0.5, 1.0)
		"quiver":
			mb.limb(b + Vector3(-0.12, -0.2, 0.04), b + Vector3(0.12, 0.25, 0.04), 0.06, 0.07, Color(0.5, 0.33, 0.18), 8)
		"lollipop":
			mb.limb(b + Vector3(0, -0.1, 0.04), b + Vector3(0.12, 0.35, 0.06), 0.015, 0.015, Color(0.95, 0.95, 0.95), 5)
			mb.cylinder(b + Vector3(0.12, 0.35, 0.02), 0.04, 0.16, 0.16, 12, acc)
		"surfboard":
			mb.sphere(b + Vector3(0, 0.0, 0.06), Vector3(0.17, 0.55, 0.03), 4, 12, acc)
		"shield":
			mb.sphere(b + Vector3(0, 0, 0.04), Vector3(0.24, 0.27, 0.04), 4, 12, acc)
			mb.sphere(b + Vector3(0, 0, 0.07), Vector3(0.08, 0.08, 0.03), 3, 8, Color(1, 0.85, 0.3))
		"tail":
			mb.limb(Vector3(0, 0.95, 0.12), Vector3(0, 0.6, 0.45), 0.07, 0.11, acc, 8)
			mb.sphere(Vector3(0, 0.55, 0.5), Vector3.ONE * 0.1, 3, 8, Color(0.95, 0.95, 0.95))


# ------------------------------------------------------------------ animation
# Body bones are posed procedurally (FK); arms holding something are solved
# with two-bone IK toward hand targets expressed in an "aim frame" (origin at
# the chest, forward -Z pitched by aim) so weapons stay gripped and on target.

const UPPER_LEN := 0.28
const FORE_LEN := 0.25
const SHOULDER_R := Vector3(0.24, 0.08, 0)
const SHOULDER_L := Vector3(-0.24, 0.08, 0)

## Pickaxe combo keys: [t, hand pos (chest frame), handle dir, torso twist, lean]
const SWING_A := [
	[0.0, Vector3(0.26, -0.36, -0.2), Vector3(0.1, 0.55, -1.0), 0.0, 0.0],
	[0.28, Vector3(0.34, 0.22, 0.02), Vector3(0.35, 1.0, 0.55), 0.55, 0.05],
	[0.46, Vector3(0.02, -0.08, -0.52), Vector3(-0.45, -0.15, -1.0), -0.35, -0.22],
	[0.7, Vector3(-0.22, -0.32, -0.3), Vector3(-1.0, -0.55, -0.2), -0.5, -0.12],
	[1.0, Vector3(0.26, -0.36, -0.2), Vector3(0.1, 0.55, -1.0), 0.0, 0.0],
]
const SWING_B := [
	[0.0, Vector3(0.26, -0.36, -0.2), Vector3(0.1, 0.55, -1.0), 0.0, 0.0],
	[0.28, Vector3(-0.12, 0.08, -0.12), Vector3(-0.9, 0.85, 0.15), -0.45, 0.0],
	[0.46, Vector3(0.14, -0.12, -0.52), Vector3(0.55, -0.1, -1.0), 0.35, -0.2],
	[0.7, Vector3(0.36, -0.26, -0.26), Vector3(1.0, -0.45, -0.15), 0.5, -0.1],
	[1.0, Vector3(0.26, -0.36, -0.2), Vector3(0.1, 0.55, -1.0), 0.0, 0.0],
]


func _process(delta: float) -> void:
	if skeleton == null or not visible:
		return
	_frame += 1
	if lod_skip > 0 and _frame % (lod_skip + 1) != 0:
		return
	delta *= (lod_skip + 1)
	_animate(minf(delta, 0.1))


func _animate(delta: float) -> void:
	var t := {}
	var hip_y := 0.0
	var root_rot := Vector3.ZERO
	var speed := move_local.length()
	var stride := 2.5 if sprinting else (1.6 if crouching else 2.0)
	_phase = fmod(_phase + delta * speed / stride * TAU, TAU * 100.0)
	var ph := _phase
	var now := Time.get_ticks_msec() * 0.001
	glider.visible = pose == Pose.GLIDE
	var use_ik := false
	match pose:
		Pose.SKYDIVE:
			root_rot.x = -lerpf(1.2, 1.5, dive)
			var flap := sin(now * 9.0) * 0.05
			t[B_LARM] = Vector3(lerpf(0.0, -0.5, dive), 0, -lerpf(1.35, 0.35, dive) + flap)
			t[B_RARM] = Vector3(lerpf(0.0, -0.5, dive), 0, lerpf(1.35, 0.35, dive) - flap)
			t[B_LFORE] = Vector3(0, 0, -lerpf(0.6, 0.1, dive))
			t[B_RFORE] = Vector3(0, 0, lerpf(0.6, 0.1, dive))
			t[B_LTHIGH] = Vector3(-0.2, 0, -lerpf(0.35, 0.06, dive))
			t[B_RTHIGH] = Vector3(-0.2, 0, lerpf(0.35, 0.06, dive))
			t[B_LSHIN] = Vector3(-lerpf(0.9, 0.15, dive), 0, 0)
			t[B_RSHIN] = Vector3(-lerpf(0.9, 0.15, dive), 0, 0)
			t[B_HEAD] = Vector3(lerpf(1.0, 0.6, dive), 0, 0)
			t[B_SPINE] = Vector3(0.15, 0, -move_local.x * 0.03)
		Pose.GLIDE:
			t[B_LARM] = Vector3(0.15, 0, -2.75)
			t[B_RARM] = Vector3(0.15, 0, 2.75)
			t[B_LFORE] = Vector3(0, 0, -0.45)
			t[B_RFORE] = Vector3(0, 0, 0.45)
			var sway := sin(now * 3.5) * 0.15
			t[B_LTHIGH] = Vector3(0.45 + sway + move_local.y * 0.02, 0, -0.08)
			t[B_RTHIGH] = Vector3(0.3 - sway + move_local.y * 0.02, 0, 0.08)
			t[B_LSHIN] = Vector3(-0.7 - sway * 0.5, 0, 0)
			t[B_RSHIN] = Vector3(-0.5 + sway * 0.5, 0, 0)
			root_rot.z = -move_local.x * 0.025
			root_rot.x = -move_local.y * 0.008
		Pose.SWIM:
			root_rot.x = -1.0
			var sw := now * 5.0
			t[B_LARM] = Vector3(sin(sw) * 1.8 + 1.4, 0, -0.35)
			t[B_RARM] = Vector3(sin(sw + PI) * 1.8 + 1.4, 0, 0.35)
			t[B_LFORE] = Vector3(0.4, 0, 0)
			t[B_RFORE] = Vector3(0.4, 0, 0)
			t[B_LTHIGH] = Vector3(sin(sw * 2.0) * 0.45, 0, -0.08)
			t[B_RTHIGH] = Vector3(-sin(sw * 2.0) * 0.45, 0, 0.08)
			t[B_HEAD] = Vector3(0.7, 0, 0)
			hip_y = -0.55
		Pose.SLIDE:
			hip_y = -0.58
			root_rot.x = 0.3
			t[B_LTHIGH] = Vector3(1.35, 0, -0.12)
			t[B_RTHIGH] = Vector3(0.35, 0, 0.2)
			t[B_LSHIN] = Vector3(-0.2, 0, 0)
			t[B_RSHIN] = Vector3(-1.7, 0, 0)
			t[B_SPINE] = Vector3(-0.3, 0, 0)
			use_ik = true
		Pose.AIR:
			t[B_LTHIGH] = Vector3(0.75, 0, -0.08)
			t[B_RTHIGH] = Vector3(0.25, 0, 0.08)
			t[B_LSHIN] = Vector3(-1.3, 0, 0)
			t[B_RSHIN] = Vector3(-0.6, 0, 0)
			t[B_LFOOT] = Vector3(0.3, 0, 0)
			t[B_SPINE] = Vector3(-0.08, 0, 0)
			use_ik = true
		Pose.DEAD:
			root_rot.x = 1.45
			hip_y = -0.8
			t[B_LARM] = Vector3(0, 0, -1.2)
			t[B_RARM] = Vector3(0, 0, 1.2)
		_:
			hip_y = _locomotion(t, ph, speed, now)
			use_ik = true
	if land_t >= 0.0:
		land_t += delta
		var k := sin(clampf(land_t / 0.22, 0.0, 1.0) * PI)
		hip_y -= k * 0.14
		t[B_LTHIGH] = t.get(B_LTHIGH, Vector3.ZERO) + Vector3(0.35 * k, 0, 0)
		t[B_RTHIGH] = t.get(B_RTHIGH, Vector3.ZERO) + Vector3(0.35 * k, 0, 0)
		t[B_LSHIN] = t.get(B_LSHIN, Vector3.ZERO) + Vector3(-0.6 * k, 0, 0)
		t[B_RSHIN] = t.get(B_RSHIN, Vector3.ZERO) + Vector3(-0.6 * k, 0, 0)
		if land_t > 0.22:
			land_t = -1.0
	var emoting := emote >= 0 and pose == Pose.GROUND
	if emoting:
		_emote(t)
		hip_y += _emote_hip()
		use_ik = false
	# aim / flinch on the torso
	var aim := clampf(aim_pitch, -1.3, 1.3)
	if use_ik:
		t[B_SPINE] = t.get(B_SPINE, Vector3.ZERO) + Vector3(aim * 0.25, 0, 0)
		t[B_CHEST] = t.get(B_CHEST, Vector3.ZERO) + Vector3(aim * 0.3 - flinch * 0.25, 0, 0)
		t[B_NECK] = Vector3(aim * 0.2, 0, 0)
		t[B_HEAD] = t.get(B_HEAD, Vector3.ZERO) + Vector3(aim * 0.2, 0, 0)
	var twist := 0.0
	var lean := 0.0
	var swing := {}
	if use_ik and swing_t >= 0.0:
		swing = _sample_swing(SWING_A if swing_combo % 2 == 0 else SWING_B, clampf(swing_t, 0.0, 1.0))
		twist = swing.twist
		lean = swing.lean
		t[B_CHEST] = t.get(B_CHEST, Vector3.ZERO) + Vector3(lean, twist, 0)
		t[B_SPINE] = t.get(B_SPINE, Vector3.ZERO) + Vector3(lean * 0.5, twist * 0.5, 0)
	# smooth FK
	var k := clampf(delta * 18.0, 0.0, 1.0)
	for b in BONES.size():
		var target: Vector3 = t.get(b, Vector3.ZERO)
		_cur[b] = _cur[b].lerp(target, k)
	_cur[B_ROOT] = _cur[B_ROOT].lerp(root_rot, clampf(delta * 8.0, 0.0, 1.0))
	_hip_y = lerpf(_hip_y, hip_y, clampf(delta * 20.0, 0.0, 1.0))
	for b in BONES.size():
		if b == B_ROOT:
			continue
		skeleton.set_bone_pose_rotation(b, Quaternion.from_euler(_cur[b]))
	var rq := Quaternion.from_euler(_cur[B_ROOT])
	var pivot := Vector3(0, 1.0, 0)
	skeleton.set_bone_pose_rotation(B_ROOT, rq)
	skeleton.set_bone_pose_position(B_ROOT, pivot - rq * pivot)
	skeleton.set_bone_pose_position(B_HIPS, Vector3(0, 0.95 + _hip_y, 0))
	# arms: IK on top of FK
	var targets := _hand_targets(use_ik, ph, speed, swing) if use_ik else {}
	_ik_w_r = move_toward(_ik_w_r, 1.0 if targets.has("r") else 0.0, delta * 8.0)
	_ik_w_l = move_toward(_ik_w_l, 1.0 if targets.has("l") else 0.0, delta * 8.0)
	if _ik_w_r > 0.0 or _ik_w_l > 0.0:
		_apply_ik(targets, delta)
	_update_trail(swing_t >= 0.0 and swing_t < 0.8 and hold == "pickaxe")


## Returns hip height offset; writes leg/torso FK.
func _locomotion(t: Dictionary, ph: float, speed: float, now: float) -> float:
	var hip_y := 0.0
	if crouching:
		hip_y = -0.34
		t[B_LTHIGH] = Vector3(1.0, 0, -0.1)
		t[B_RTHIGH] = Vector3(1.0, 0, 0.1)
		t[B_LSHIN] = Vector3(-1.55, 0, 0)
		t[B_RSHIN] = Vector3(-1.55, 0, 0)
		t[B_LFOOT] = Vector3(0.5, 0, 0)
		t[B_RFOOT] = Vector3(0.5, 0, 0)
		t[B_SPINE] = Vector3(-0.32, 0, 0)
	if speed < 0.25:
		if not crouching:
			# idle: breathing + slight weight shift
			var b := sin(now * 1.6)
			hip_y = b * 0.006
			t[B_SPINE] = Vector3(b * 0.015, 0, 0)
			t[B_HIPS] = Vector3(0, 0.05, sin(now * 0.7) * 0.025)
			t[B_LTHIGH] = Vector3(0.05, 0, -0.06)
			t[B_RTHIGH] = Vector3(-0.05, 0, 0.06)
			t[B_LSHIN] = Vector3(-0.08, 0, 0)
		return hip_y
	var f := move_local.y / speed
	var sd := move_local.x / speed
	var amp := 0.95 if sprinting else (0.45 if crouching else 0.72)
	var s := sin(ph)
	var c := cos(ph)
	var dir := 1.0 if f >= -0.2 else -1.0
	# hips turn slightly toward strafe direction (Fortnite-style strafing)
	var strafe := clampf(sd * dir, -1.0, 1.0) * 0.45
	t[B_HIPS] = Vector3(0, strafe + s * 0.12, 0)
	var lt := Vector3(s * amp * dir, 0, 0)
	var rt := Vector3(-s * amp * dir, 0, 0)
	var crouch_add := Vector3(1.0, 0, 0) if crouching else Vector3.ZERO
	t[B_LTHIGH] = lt + crouch_add + Vector3(0, 0, -0.04)
	t[B_RTHIGH] = rt + crouch_add + Vector3(0, 0, 0.04)
	# knee bends most while the leg swings forward
	var kl := maxf(0.0, c * dir) * (1.5 if sprinting else 1.2) * amp + 0.15
	var kr := maxf(0.0, -c * dir) * (1.5 if sprinting else 1.2) * amp + 0.15
	t[B_LSHIN] = Vector3(-kl - (1.55 if crouching else 0.0), 0, 0)
	t[B_RSHIN] = Vector3(-kr - (1.55 if crouching else 0.0), 0, 0)
	t[B_LFOOT] = Vector3(maxf(0.0, -s * dir) * 0.4 + (0.5 if crouching else 0.0), 0, 0)
	t[B_RFOOT] = Vector3(maxf(0.0, s * dir) * 0.4 + (0.5 if crouching else 0.0), 0, 0)
	var lean_fwd := -0.32 if sprinting else -0.07 * f
	t[B_SPINE] = t.get(B_SPINE, Vector3.ZERO) + Vector3(lean_fwd, -strafe * 0.6 - s * 0.08, 0)
	t[B_CHEST] = Vector3(0, -s * 0.1, c * 0.03)
	# two bounces per stride, lowest at mid-stance
	var bounce := 0.075 if sprinting else (0.03 if crouching else 0.055)
	hip_y += -(1.0 - absf(s)) * bounce + bounce * 0.4
	if not sprinting and hold == "pickaxe" or sprinting:
		var arm_amp := 1.1 if sprinting else 0.55
		t[B_LARM] = Vector3(-s * arm_amp * dir, 0, -0.12)
		t[B_LFORE] = Vector3(0.9 if sprinting else 0.45, 0, 0)
		t[B_RARM] = Vector3(s * arm_amp * dir, 0, 0.12)
		t[B_RFORE] = Vector3(0.9 if sprinting else 0.45, 0, 0)
	return hip_y


## Hand targets in aim-frame space. Keys "r"/"l" -> {pos, fwd, up, frame}.
func _hand_targets(_use: bool, ph: float, speed: float, swing: Dictionary) -> Dictionary:
	var out := {}
	var fwd := Vector3(0, 0, -1)
	var up := Vector3.UP
	var kick := Vector3(0, 0.01, 0.06) * fire_kick
	match hold:
		"rifle", "smg", "shotgun", "sniper":
			if sprinting:
				# low-ready while sprinting, off hand pumps
				var bob := sin(ph * 2.0) * 0.03
				out.r = {"pos": Vector3(0.2, -0.3 + bob, -0.18), "fwd": Vector3(-0.35, -0.55, -1.0), "up": Vector3(-0.3, 1, 0.2), "frame": "chest"}
			else:
				var r := Vector3(0.12, -0.05, -0.3) if ads else Vector3(0.22, -0.12, -0.26)
				var grip := {"smg": 0.24, "shotgun": 0.38, "sniper": 0.42}.get(hold, 0.32) as float
				out.r = {"pos": r + kick, "fwd": fwd, "up": up, "frame": "aim"}
				out.l = {"pos": r + kick + Vector3(-0.03, -0.02, -grip), "fwd": Vector3(0.25, 0.3, -1), "up": Vector3(1, 0.3, 0), "frame": "aim"}
		"pistol":
			if sprinting:
				out.r = {"pos": Vector3(0.22, -0.35, -0.12), "fwd": Vector3(0, -1, -0.6), "up": Vector3(0, 0.3, 1), "frame": "chest"}
			else:
				var r := Vector3(0.06, -0.02, -0.46) + kick
				out.r = {"pos": r, "fwd": fwd, "up": up, "frame": "aim"}
				out.l = {"pos": r + Vector3(-0.05, -0.05, 0.03), "fwd": Vector3(0.6, 0, -1), "up": Vector3(0.6, 1, 0), "frame": "aim"}
		"rocket":
			out.r = {"pos": Vector3(0.14, -0.08, -0.2) + kick, "fwd": fwd, "up": up, "frame": "aim"}
			out.l = {"pos": Vector3(0.06, -0.12, -0.55), "fwd": Vector3(0.3, 0.3, -1), "up": Vector3(1, 0.3, 0), "frame": "aim"}
		"consumable":
			var bob := sin(heal_t * TAU * 1.5) * 0.03 if heal_t >= 0.0 else 0.0
			out.r = {"pos": Vector3(0.06, -0.16 + bob, -0.3), "fwd": Vector3(0, 1, -0.3), "up": Vector3(0, 0.3, 1), "frame": "chest"}
			if heal_t >= 0.0:
				out.l = {"pos": Vector3(-0.06, -0.18 - bob, -0.3), "fwd": Vector3(0.3, 0.6, -1), "up": Vector3(1, 0, 0), "frame": "chest"}
		"build":
			var push := sin(clampf(build_t, 0.0, 1.0) * PI) * 0.12 if build_t >= 0.0 else 0.0
			out.r = {"pos": Vector3(0.18, -0.04, -0.42 - push), "fwd": Vector3(0, 1, -0.3), "up": Vector3(0, 0.2, 1), "frame": "aim"}
		"pickaxe":
			if not swing.is_empty():
				out.r = {"pos": swing.pos, "fwd": swing.blade, "up": swing.handle, "frame": "chest"}
			elif not sprinting and speed < 0.25:
				out.r = {"pos": Vector3(0.28, -0.46, -0.14), "fwd": Vector3(0, 1, 0.8), "up": Vector3(0.08, 0.8, -1.0), "frame": "chest"}
	if reload_t >= 0.0 and out.has("l"):
		var a := sin(clampf(reload_t, 0.0, 1.0) * PI)
		out.l.pos = (out.l.pos as Vector3).lerp(Vector3(0.05, -0.28, -0.12), a)
	return out


func _sample_swing(keys: Array, x: float) -> Dictionary:
	var i := 0
	while i < keys.size() - 2 and x > keys[i + 1][0]:
		i += 1
	var a: Array = keys[i]
	var b: Array = keys[i + 1]
	var u := clampf((x - a[0]) / (b[0] - a[0]), 0.0, 1.0)
	# fast strike, eased wind-up / recovery
	u = u * u * (3.0 - 2.0 * u) if i != 1 else 1.0 - pow(1.0 - u, 3.0)
	var handle: Vector3 = (a[2] as Vector3).normalized().lerp((b[2] as Vector3).normalized(), u).normalized()
	var pos: Vector3 = (a[1] as Vector3).lerp(b[1], u)
	var blade := (pos - (a[1] as Vector3)).normalized() if i in [1, 2] else Vector3(0, 0, -1)
	blade = (blade - handle * blade.dot(handle))
	if blade.length() < 0.05:
		blade = Vector3(0, 0, -1) - handle * handle.z * -1.0
	return {"pos": pos, "handle": handle, "blade": blade.normalized(), "twist": lerpf(a[3], b[3], u), "lean": lerpf(a[4], b[4], u)}


## Skeleton-space transform of the chest (composed from current bone poses).
func _chest_global() -> Transform3D:
	var g := Transform3D.IDENTITY
	for b in [B_ROOT, B_HIPS, B_SPINE, B_CHEST]:
		g = g * Transform3D(Basis(skeleton.get_bone_pose_rotation(b)), skeleton.get_bone_pose_position(b))
	return g


func _apply_ik(targets: Dictionary, delta: float) -> void:
	var chest := _chest_global()
	var aim_basis := Basis(Vector3.RIGHT, clampf(aim_pitch, -1.3, 1.3))
	var aim := Transform3D(aim_basis, chest.origin)
	var k := clampf(delta * 22.0, 0.0, 1.0)
	for side in ["r", "l"]:
		var store: Dictionary = _hand_r if side == "r" else _hand_l
		var w := _ik_w_r if side == "r" else _ik_w_l
		if w <= 0.0:
			store.clear()
			continue
		var tgt: Dictionary = targets.get(side, {})
		if not tgt.is_empty():
			var frame := chest if tgt.frame == "chest" else aim
			var p: Vector3 = frame * (tgt.pos as Vector3)
			var f: Vector3 = (frame.basis * (tgt.fwd as Vector3)).normalized()
			var u: Vector3 = (frame.basis * (tgt.up as Vector3)).normalized()
			if store.is_empty():
				store.pos = p
				store.fwd = f
				store.up = u
			else:
				var kk := 1.0 if swing_t >= 0.0 and hold == "pickaxe" and side == "r" else k
				store.pos = (store.pos as Vector3).lerp(p, kk)
				store.fwd = (store.fwd as Vector3).lerp(f, kk).normalized()
				store.up = (store.up as Vector3).lerp(u, kk).normalized()
		if store.is_empty():
			continue
		_solve_arm(side == "r", chest, store.pos, store.fwd, store.up, w)


func _solve_arm(right: bool, chest: Transform3D, target: Vector3, fwd: Vector3, up: Vector3, weight: float) -> void:
	var b_arm := B_RARM if right else B_LARM
	var b_fore := B_RFORE if right else B_LFORE
	var b_hand := B_RHAND if right else B_LHAND
	var sgn := 1.0 if right else -1.0
	var s: Vector3 = chest * (SHOULDER_R if right else SHOULDER_L)
	var to := target - s
	var d := clampf(to.length(), 0.08, UPPER_LEN + FORE_LEN - 0.002)
	var dir := to.normalized()
	var cos_a := clampf((UPPER_LEN * UPPER_LEN + d * d - FORE_LEN * FORE_LEN) / (2.0 * UPPER_LEN * d), -1.0, 1.0)
	var sin_a := sqrt(1.0 - cos_a * cos_a)
	# elbows point down, out and slightly back
	var pole := chest.basis * Vector3(sgn * 0.7, -1.0, 0.35)
	var perp := (pole - dir * pole.dot(dir))
	if perp.length() < 0.001:
		perp = chest.basis * Vector3(0, -1, 0)
	perp = perp.normalized()
	var elbow := s + dir * UPPER_LEN * cos_a + perp * UPPER_LEN * sin_a
	var hand := elbow + (s + dir * d - elbow).normalized() * FORE_LEN
	var upper_g := _limb_basis(elbow - s, perp)
	var fore_g := _limb_basis(hand - elbow, perp)
	# hand: -Z = up (gun top / pickaxe handle) is primary, -Y = fwd (barrel / blade)
	var hz := -up.normalized()
	var hy := (-fwd - hz * (-fwd).dot(hz))
	if hy.length() < 0.01:
		hy = chest.basis * Vector3(0, 0, 1) - hz * hz.z
	hy = hy.normalized()
	var hand_g := Basis(hy.cross(hz), hy, hz).orthonormalized()
	var q_upper := Quaternion((chest.basis.inverse() * upper_g).orthonormalized())
	var q_fore := Quaternion((upper_g.inverse() * fore_g).orthonormalized())
	var q_hand := Quaternion((fore_g.inverse() * hand_g).orthonormalized())
	if weight < 1.0:
		q_upper = skeleton.get_bone_pose_rotation(b_arm).slerp(q_upper, weight)
		q_fore = skeleton.get_bone_pose_rotation(b_fore).slerp(q_fore, weight)
		q_hand = skeleton.get_bone_pose_rotation(b_hand).slerp(q_hand, weight)
	skeleton.set_bone_pose_rotation(b_arm, q_upper)
	skeleton.set_bone_pose_rotation(b_fore, q_fore)
	skeleton.set_bone_pose_rotation(b_hand, q_hand)


## Basis whose -Y runs along `along`, Z biased toward `ref`.
static func _limb_basis(along: Vector3, ref: Vector3) -> Basis:
	var y := -along.normalized()
	var z := ref - y * ref.dot(y)
	if z.length() < 0.001:
		z = Vector3.FORWARD - y * y.z
	z = z.normalized()
	return Basis(y.cross(z), y, z).orthonormalized()


func _update_trail(active: bool) -> void:
	if not active or held.mesh == null or not is_inside_tree():
		if _trail and _trail.visible:
			_trail.visible = false
			_trail_pts.clear()
		return
	if _trail == null:
		_trail = MeshInstance3D.new()
		_trail.mesh = ImmediateMesh.new()
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.vertex_color_use_as_albedo = true
		_trail.material_override = m
		_trail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_trail.top_level = true
		add_child(_trail)
	_trail.visible = true
	_trail.global_transform = Transform3D.IDENTITY
	var x := held.global_transform
	_trail_pts.push_front(x * Vector3(0, 0.62, 0))
	_trail_pts.push_front(x * Vector3(0, 0.78, 0.3))
	while _trail_pts.size() > 14:
		_trail_pts.pop_back()
	var im := _trail.mesh as ImmediateMesh
	im.clear_surfaces()
	if _trail_pts.size() < 4:
		return
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	var n := _trail_pts.size() / 2
	for i in n:
		var a := 1.0 - float(i) / n
		im.surface_set_color(Color(0.8, 0.9, 1.0, a * 0.35))
		im.surface_add_vertex(_trail_pts[i * 2])
		im.surface_set_color(Color(0.8, 0.9, 1.0, a * 0.05))
		im.surface_add_vertex(_trail_pts[i * 2 + 1])
	im.surface_end()


func _emote(t: Dictionary) -> void:
	var e := emote_t
	match emote:
		0:  # "Bounce": arm pumps on the beat
			var b := sin(e * TAU * 2.0)
			t[B_LARM] = Vector3(0.3, 0, -1.0 - b * 0.9)
			t[B_RARM] = Vector3(0.3, 0, 1.0 - b * 0.9)
			t[B_LFORE] = Vector3(0, 0, -1.2)
			t[B_RFORE] = Vector3(0, 0, 1.2)
			t[B_LTHIGH] = Vector3(0.3 * maxf(0.0, b), 0, -0.1)
			t[B_RTHIGH] = Vector3(0.3 * maxf(0.0, -b), 0, 0.1)
			t[B_HEAD] = Vector3(0.2 * b, 0, 0)
		1:  # "Hello": big wave
			t[B_RARM] = Vector3(0, 0, 2.6)
			t[B_RFORE] = Vector3(0, 0, sin(e * TAU * 2.5) * 0.6)
			t[B_LARM] = Vector3(0, 0, -0.2)
			t[B_HEAD] = Vector3(0, 0, 0.15)
		2:  # "Twirl": spin with arms out
			t[B_LARM] = Vector3(0, 0, -1.5)
			t[B_RARM] = Vector3(0, 0, 1.5)
			t[B_SPINE] = Vector3(0, e * TAU * 1.5, 0)
			t[B_LTHIGH] = Vector3(0.4 * sin(e * TAU * 3.0), 0, -0.2)
		3:  # "Robot": stiff arm moves
			var step := floorf(e * 4.0)
			var a := 1.0 if int(step) % 2 == 0 else -1.0
			t[B_LARM] = Vector3(1.4, 0, -0.2 * a)
			t[B_RARM] = Vector3(1.4, 0, 0.2 * a)
			t[B_LFORE] = Vector3(1.4 * (0.5 + 0.5 * a), 0, 0)
			t[B_RFORE] = Vector3(1.4 * (0.5 - 0.5 * a), 0, 0)
			t[B_HEAD] = Vector3(0, 0.4 * a, 0)


func _emote_hip() -> float:
	if emote == 0:
		return -absf(sin(emote_t * TAU * 2.0)) * 0.08
	return 0.0
