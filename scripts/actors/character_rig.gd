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
	["l_arm", 3, Vector3(-0.21, 0.15, 0)],
	["l_fore", 6, Vector3(0, -0.28, 0)],
	["l_hand", 7, Vector3(0, -0.25, 0)],
	["r_arm", 3, Vector3(0.21, 0.15, 0)],
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

var _phase := 0.0
var _cur := {}                   # bone -> Vector3 euler (smoothed)
var _hip_y := 0.0
var _frame := 0


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
		held.rotation = Vector3(0, 0, 0)
		held.position = Vector3(0, -0.05, 0)
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
	mb.sphere(Vector3(0, 0.93, 0), Vector3(0.17 * w, 0.13, 0.12 * w), 4, 10, pants)
	mb.cylinder(Vector3(0, 0.98, 0), 0.06, 0.165 * w, 0.165 * w, 10, acc, false)   # belt
	# torso
	mb.bone = B_SPINE
	mb.cylinder(Vector3(0, 1.0, 0), 0.22, 0.155 * w, 0.17 * w, 10, top, false)
	mb.bone = B_CHEST
	mb.sphere(Vector3(0, 1.28, 0), Vector3(0.205 * w, 0.17, 0.135 * w), 5, 10, top)
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
		var sh := Vector3(0.21 * side * w, 1.46, 0)
		var el := sh + Vector3(0.0, -0.28, 0)
		var wr := el + Vector3(0, -0.25, 0)
		var sleeve: Color = top if s.sleeves == "long" else skin
		mb.bone = B_LARM if side < 0 else B_RARM
		mb.sphere(sh, Vector3.ONE * 0.075 * w, 3, 8, top)
		mb.limb(sh, el, 0.065 * w, 0.055 * w, sleeve if s.sleeves == "long" else skin, 8)
		if s.sleeves == "short":
			mb.cylinder(sh + Vector3(0, -0.1, 0), 0.1, 0.075 * w, 0.075 * w, 8, top, false)
		if s.extra == "pauldrons":
			mb.sphere(sh + Vector3(0.03 * side, 0.02, 0), Vector3(0.11, 0.08, 0.11) * w, 3, 8, acc)
		mb.bone = B_LFORE if side < 0 else B_RFORE
		mb.limb(el, wr, 0.055 * w, 0.045 * w, top if s.sleeves == "long" else skin, 8)
		mb.cylinder(wr + Vector3(0, 0.02, 0), 0.06, 0.05 * w, 0.05 * w, 8, gloves, false)
		mb.bone = B_LHAND if side < 0 else B_RHAND
		mb.sphere(wr + Vector3(0, -0.06, 0), Vector3(0.045, 0.06, 0.035) * w, 3, 8, gloves)
	# legs
	for side: float in [-1.0, 1.0]:
		var hp := Vector3(0.1 * side * w, 0.91, 0)
		var kn := Vector3(0.1 * side * w, 0.48, 0)
		var an := Vector3(0.1 * side * w, 0.08, 0)
		mb.bone = B_LTHIGH if side < 0 else B_RTHIGH
		mb.limb(hp, kn, 0.085 * w, 0.065 * w, pants, 8)
		mb.bone = B_LSHIN if side < 0 else B_RSHIN
		mb.limb(kn, an, 0.065 * w, 0.05 * w, pants, 8)
		mb.cylinder(an + Vector3(0, 0.05, 0), 0.12, 0.065 * w, 0.07 * w, 8, shoes)
		mb.bone = B_LFOOT if side < 0 else B_RFOOT
		mb.sphere(an + Vector3(0, -0.02, -0.06), Vector3(0.065 * w, 0.06, 0.13), 3, 8, shoes)
	# back bling (on chest bone)
	mb.bone = B_CHEST
	_back(mb, s)
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

func _process(delta: float) -> void:
	if skeleton == null or not visible:
		return
	_frame += 1
	if lod_skip > 0 and _frame % (lod_skip + 1) != 0:
		return
	delta *= (lod_skip + 1)
	_animate(minf(delta, 0.1))


func _animate(delta: float) -> void:
	var t := {}   # bone -> euler
	var hip_y := 0.0
	var root_rot := Vector3.ZERO
	var speed := move_local.length()
	var stride := 2.2 if sprinting else 1.7
	_phase += delta * speed / stride * TAU * 0.5
	var ph := _phase
	glider.visible = pose == Pose.GLIDE
	match pose:
		Pose.SKYDIVE:
			root_rot.x = -lerpf(1.25, 1.55, dive)
			hip_y = 0.0
			var flap := sin(Time.get_ticks_msec() * 0.012) * 0.06
			t[B_LARM] = Vector3(lerpf(0.3, -0.3, dive), 0, -lerpf(1.5, 0.5, dive) + flap)
			t[B_RARM] = Vector3(lerpf(0.3, -0.3, dive), 0, lerpf(1.5, 0.5, dive) - flap)
			t[B_LFORE] = Vector3(0.3, 0, 0)
			t[B_RFORE] = Vector3(0.3, 0, 0)
			t[B_LTHIGH] = Vector3(-0.15, 0, -lerpf(0.35, 0.08, dive))
			t[B_RTHIGH] = Vector3(-0.15, 0, lerpf(0.35, 0.08, dive))
			t[B_LSHIN] = Vector3(-lerpf(0.6, 0.1, dive), 0, 0)
			t[B_RSHIN] = Vector3(-lerpf(0.6, 0.1, dive), 0, 0)
			t[B_HEAD] = Vector3(lerpf(0.9, 0.5, dive), 0, 0)
		Pose.GLIDE:
			t[B_LARM] = Vector3(0, 0, -2.75)
			t[B_RARM] = Vector3(0, 0, 2.75)
			t[B_LFORE] = Vector3(0, 0, -0.35)
			t[B_RFORE] = Vector3(0, 0, 0.35)
			var sway := sin(Time.get_ticks_msec() * 0.004) * 0.12
			t[B_LTHIGH] = Vector3(0.35 + sway, 0, -0.05)
			t[B_RTHIGH] = Vector3(0.25 - sway, 0, 0.05)
			t[B_LSHIN] = Vector3(-0.5, 0, 0)
			t[B_RSHIN] = Vector3(-0.4, 0, 0)
			root_rot.z = -move_local.x * 0.02
			root_rot.x = move_local.y * 0.008
		Pose.SWIM:
			root_rot.x = -0.9
			var sw := Time.get_ticks_msec() * 0.006
			t[B_LARM] = Vector3(sin(sw) * 1.6 + 1.2, 0, -0.3)
			t[B_RARM] = Vector3(sin(sw + PI) * 1.6 + 1.2, 0, 0.3)
			t[B_LTHIGH] = Vector3(sin(sw * 2.0) * 0.4, 0, -0.08)
			t[B_RTHIGH] = Vector3(-sin(sw * 2.0) * 0.4, 0, 0.08)
			hip_y = -0.6
		Pose.SLIDE:
			hip_y = -0.55
			root_rot.x = 0.35
			t[B_LTHIGH] = Vector3(1.3, 0, -0.1)
			t[B_RTHIGH] = Vector3(0.4, 0, 0.15)
			t[B_LSHIN] = Vector3(-0.15, 0, 0)
			t[B_RSHIN] = Vector3(-1.6, 0, 0)
			t[B_SPINE] = Vector3(-0.35, 0, 0)
		Pose.AIR:
			t[B_LTHIGH] = Vector3(0.5, 0, -0.06)
			t[B_RTHIGH] = Vector3(0.15, 0, 0.06)
			t[B_LSHIN] = Vector3(-0.9, 0, 0)
			t[B_RSHIN] = Vector3(-0.45, 0, 0)
			t[B_LARM] = Vector3(0.2, 0, -0.5)
			t[B_RARM] = Vector3(0.2, 0, 0.5)
		Pose.DEAD:
			root_rot.x = 1.4
			hip_y = -0.75
		_:
			_locomotion(t, ph, speed)
			if crouching:
				hip_y = -0.32
				t[B_LTHIGH] = t.get(B_LTHIGH, Vector3.ZERO) + Vector3(0.95, 0, 0)
				t[B_RTHIGH] = t.get(B_RTHIGH, Vector3.ZERO) + Vector3(0.95, 0, 0)
				t[B_LSHIN] = t.get(B_LSHIN, Vector3.ZERO) + Vector3(-1.45, 0, 0)
				t[B_RSHIN] = t.get(B_RSHIN, Vector3.ZERO) + Vector3(-1.45, 0, 0)
				t[B_LFOOT] = Vector3(0.45, 0, 0)
				t[B_RFOOT] = Vector3(0.45, 0, 0)
				t[B_SPINE] = Vector3(-0.3, 0, 0)
			elif speed > 0.3:
				hip_y = -absf(sin(ph)) * (0.07 if sprinting else 0.045) + 0.02
			else:
				hip_y = sin(Time.get_ticks_msec() * 0.002) * 0.008
	if pose in [Pose.GROUND, Pose.AIR, Pose.SLIDE, Pose.SWIM]:
		_upper_body(t, ph, speed)
	if emote >= 0 and pose == Pose.GROUND:
		_emote(t)
		hip_y += _emote_hip()
	# smooth toward target
	var k := clampf(delta * 16.0, 0.0, 1.0)
	for b in BONES.size():
		var target: Vector3 = t.get(b, Vector3.ZERO)
		_cur[b] = _cur[b].lerp(target, k)
		if b == B_ROOT:
			continue
		skeleton.set_bone_pose_rotation(b, Quaternion.from_euler(_cur[b]))
	_cur[B_ROOT] = _cur[B_ROOT].lerp(root_rot, clampf(delta * 8.0, 0.0, 1.0))
	_hip_y = lerpf(_hip_y, hip_y, k)
	# pivot whole-body rotations (skydive, swim, death) around the waist
	var rq := Quaternion.from_euler(_cur[B_ROOT])
	var pivot := Vector3(0, 1.0, 0)
	skeleton.set_bone_pose_rotation(B_ROOT, rq)
	skeleton.set_bone_pose_position(B_ROOT, pivot - rq * pivot)
	skeleton.set_bone_pose_position(B_HIPS, Vector3(0, 0.95 + _hip_y, 0))


func _locomotion(t: Dictionary, ph: float, speed: float) -> void:
	if speed < 0.3:
		return
	var f := move_local.y / maxf(speed, 0.01)
	var sd := move_local.x / maxf(speed, 0.01)
	var amp := 0.85 if sprinting else 0.65
	var s := sin(ph)
	var c := cos(ph)
	t[B_LTHIGH] = Vector3(s * amp * f, 0, -0.03 + s * 0.35 * sd)
	t[B_RTHIGH] = Vector3(-s * amp * f, 0, 0.03 - s * 0.35 * sd)
	t[B_LSHIN] = Vector3(-maxf(0.0, -c) * 1.3 * amp - 0.1, 0, 0)
	t[B_RSHIN] = Vector3(-maxf(0.0, c) * 1.3 * amp - 0.1, 0, 0)
	t[B_LFOOT] = Vector3(maxf(0.0, -s) * 0.3, 0, 0)
	t[B_RFOOT] = Vector3(maxf(0.0, s) * 0.3, 0, 0)
	t[B_SPINE] = Vector3(-0.12 * f if not sprinting else -0.28, sin(ph) * 0.06, 0)


func _upper_body(t: Dictionary, ph: float, speed: float) -> void:
	var aim := clampf(aim_pitch, -1.2, 1.2)
	var chest_pitch := aim * 0.55
	t[B_CHEST] = t.get(B_CHEST, Vector3.ZERO) + Vector3(chest_pitch - fire_kick * 0.25 - flinch * 0.3, 0, 0)
	t[B_HEAD] = Vector3(aim * 0.4, 0, 0)
	var running_arms := sprinting and pose == Pose.GROUND and swing_t < 0.0
	if running_arms:
		var s := sin(ph)
		t[B_LARM] = Vector3(-s * 1.0, 0, -0.15)
		t[B_RARM] = Vector3(s * 1.0, 0, 0.15)
		t[B_LFORE] = Vector3(1.1, 0, 0)
		t[B_RFORE] = Vector3(1.1, 0, 0)
		return
	match hold:
		"rifle", "smg", "sniper", "shotgun":
			t[B_RARM] = Vector3(0.95 + aim * 0.3, 0.3, 0.2)
			t[B_RFORE] = Vector3(0.95, 0, 0)
			t[B_RHAND] = Vector3(-0.35, 0, 0)
			t[B_LARM] = Vector3(1.25 + aim * 0.3, -0.35, -0.55)
			t[B_LFORE] = Vector3(0.65, 0.0, 0.0)
		"pistol":
			t[B_RARM] = Vector3(1.4 + aim * 0.4, 0.15, 0.15)
			t[B_RFORE] = Vector3(0.15, 0, 0)
			t[B_LARM] = Vector3(1.3 + aim * 0.4, -0.35, -0.35)
			t[B_LFORE] = Vector3(0.35, 0, 0)
		"rocket":
			t[B_RARM] = Vector3(0.6, 0, 0.6)
			t[B_RFORE] = Vector3(1.6, 0, 0)
			t[B_LARM] = Vector3(1.0, 0, -0.4)
			t[B_LFORE] = Vector3(0.8, 0, 0)
		"build":
			t[B_RARM] = Vector3(0.9, 0, 0.25)
			t[B_RFORE] = Vector3(0.6, 0, 0)
			t[B_LARM] = Vector3(0.3, 0, -0.2)
			t[B_LFORE] = Vector3(0.6, 0, 0)
		"consumable":
			t[B_RARM] = Vector3(0.6, 0, 0.2)
			t[B_RFORE] = Vector3(1.4, 0, 0)
		_:   # pickaxe / none
			var s := sin(ph) * minf(speed / 5.0, 1.0)
			t[B_RARM] = Vector3(0.35 - s * 0.4, 0, 0.12)
			t[B_RFORE] = Vector3(0.5, 0, 0)
			t[B_LARM] = Vector3(s * 0.5, 0, -0.12)
			t[B_LFORE] = Vector3(0.3, 0, 0)
	if fire_kick > 0.0:
		t[B_RARM] = t.get(B_RARM, Vector3.ZERO) + Vector3(fire_kick * 0.25, 0, 0)
	if swing_t >= 0.0:
		# wind up over the shoulder then chop down across the body
		var a: float
		if swing_t < 0.35:
			a = lerpf(0.0, 1.0, swing_t / 0.35)
			t[B_RARM] = Vector3(lerpf(0.4, 2.9, a), 0, lerpf(0.1, 0.5, a))
			t[B_RFORE] = Vector3(lerpf(0.5, 1.2, a), 0, 0)
			t[B_CHEST] = t.get(B_CHEST, Vector3.ZERO) + Vector3(0.1 * a, 0.35 * a, 0)
		else:
			a = clampf((swing_t - 0.35) / 0.4, 0.0, 1.0)
			t[B_RARM] = Vector3(lerpf(2.9, 0.6, a), -0.3 * a, lerpf(0.5, -0.1, a))
			t[B_RFORE] = Vector3(lerpf(1.2, 0.2, a), 0, 0)
			t[B_CHEST] = t.get(B_CHEST, Vector3.ZERO) + Vector3(-0.25 * a, lerpf(0.35, -0.3, a), 0)
	if build_t >= 0.0:
		var a := sin(clampf(build_t, 0.0, 1.0) * PI)
		t[B_RARM] = Vector3(1.2 + a * 0.4, 0, 0.3)
		t[B_RFORE] = Vector3(0.3, 0, 0)
	if reload_t >= 0.0:
		var a := sin(clampf(reload_t, 0.0, 1.0) * PI)
		t[B_LARM] = Vector3(0.6 + a * 0.2, 0, -0.1)
		t[B_LFORE] = Vector3(1.4 - a * 0.6, 0, 0)
		t[B_RARM] = t.get(B_RARM, Vector3.ZERO) + Vector3(-0.3 * a, 0, 0)
	if heal_t >= 0.0:
		var bob := sin(heal_t * TAU * 1.5) * 0.15
		t[B_LARM] = Vector3(0.7 + bob, 0, -0.2)
		t[B_LFORE] = Vector3(1.5, 0, 0)
		t[B_RARM] = Vector3(0.7 - bob, 0, 0.2)
		t[B_RFORE] = Vector3(1.5, 0, 0)


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
