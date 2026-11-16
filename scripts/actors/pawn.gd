class_name Pawn
extends CharacterBody3D
## A combatant (player or bot): movement modes, health/shield, inventory,
## weapons, pickaxe, consumables, building. Controllers drive it through the
## in_* fields and the action methods; the pawn never reads input itself.

signal eliminated(victim: Pawn, killer: Pawn, weapon: String)

enum Mode { BUS, SKYDIVE, GLIDE, GROUND, SWIM, DEAD }

var id := 0
var display_name := "Player"
var is_player := false
var skin := 0
var game: Match
var rig: CharacterRig
var mode := Mode.BUS
var lite := false            # far-away bot: cheap simulation, no collision

# --- controls ---
var in_move := Vector2.ZERO  # x right, y forward (-1..1)
var in_sprint := false
var in_crouch := false
var in_aim := false
var in_fire := false
var yaw := 0.0
var pitch := 0.0
var aim_from := Vector3.ZERO  # ray origin (camera for player, eye for bots)
var aim_dir := Vector3.FORWARD

# --- stats ---
var health := Cfg.MAX_HEALTH
var shield := 0.0
var stamina := Cfg.STAMINA_MAX
var mats := [0, 0, 0]
var ammo := {"light": 0, "medium": 0, "heavy": 0, "shells": 0, "rockets": 0}
var inventory: Array = [{}, {}, {}, {}, {}]
var slot := 0                 # 0 = pickaxe, 1..5 = inventory
var kills := 0
var damage_dealt := 0.0
var placement := 0

# --- building ---
var build_mode := false
var build_kind := PieceMeshes.Kind.WALL
var build_mat := 0
var _build_cd := 0.0

# --- timers / state ---
var _fire_cd := 0.0
var _equip_cd := 0.0
var bloom := 0.0
var reload_left := -1.0
var use_left := -1.0
var use_total := 1.0
var _swing_cd := 0.0
var _swing_t := -1.0
var _swing_hit_done := false
var _fire_was_held := false
var _sliding := false
var _fall_peak := 0.0
var _airborne := false
var _mantle_t := -1.0
var _mantle_from := Vector3.ZERO
var _mantle_to := Vector3.ZERO
var _step_t := 0.0
var storm_dmg_t := 0.0
var last_attacker: Pawn
var last_hit_time := -100.0
var _emote_t := -1.0
var emote_id := -1
var crouched := false
var dive := 0.0
var glide_cooldown := 0.0
var hit_flash := 0.0
var _shape: CollisionShape3D
var _capsule: CapsuleShape3D


func setup(p_game: Match, p_id: int, p_name: String, p_skin: int, player: bool) -> void:
	game = p_game
	id = p_id
	display_name = p_name
	skin = p_skin
	is_player = player
	collision_layer = Cfg.L_PAWN
	collision_mask = Cfg.L_WORLD | Cfg.L_BUILD
	floor_max_angle = deg_to_rad(50.0)
	floor_snap_length = 0.45
	safe_margin = 0.02
	_capsule = CapsuleShape3D.new()
	_capsule.radius = Cfg.CAPSULE_RADIUS
	_capsule.height = Cfg.CAPSULE_HEIGHT
	_shape = CollisionShape3D.new()
	_shape.shape = _capsule
	_shape.position.y = Cfg.CAPSULE_HEIGHT * 0.5
	add_child(_shape)
	rig = CharacterRig.new()
	add_child(rig)
	rig.setup(skin)
	_refresh_held()


func is_alive() -> bool:
	return mode != Mode.DEAD


func eye_pos() -> Vector3:
	return global_position + Vector3(0, (Cfg.EYE_HEIGHT - 0.5) if crouched else Cfg.EYE_HEIGHT, 0)


func is_head_hit(p: Vector3) -> bool:
	var h := 1.45 if not crouched else 0.95
	if mode in [Mode.SKYDIVE, Mode.GLIDE, Mode.SWIM]:
		return false
	return p.y - global_position.y > h


func current_item() -> Dictionary:
	if slot == 0:
		return {}
	return inventory[slot - 1]


func current_weapon() -> Dictionary:
	var it := current_item()
	if Items.is_weapon(it):
		return it
	return {}


# ------------------------------------------------------------------ physics

func _physics_process(delta: float) -> void:
	if mode == Mode.DEAD or mode == Mode.BUS:
		return
	_timers(delta)
	match mode:
		Mode.SKYDIVE:
			_skydive(delta)
		Mode.GLIDE:
			_glide(delta)
		Mode.SWIM:
			_swim(delta)
		_:
			_ground(delta)
	if mode == Mode.GROUND or mode == Mode.SWIM:
		_combat(delta)
	_drive_rig(delta)


func _timers(delta: float) -> void:
	_fire_cd = maxf(0.0, _fire_cd - delta)
	_equip_cd = maxf(0.0, _equip_cd - delta)
	_build_cd = maxf(0.0, _build_cd - delta)
	_swing_cd = maxf(0.0, _swing_cd - delta)
	glide_cooldown = maxf(0.0, glide_cooldown - delta)
	hit_flash = maxf(0.0, hit_flash - delta * 3.0)
	var wpn := current_weapon()
	var decay := 6.0 if not wpn.is_empty() and Items.WEAPONS[wpn.id].auto else 3.0
	bloom = maxf(0.0, bloom - delta * decay)
	rig.fire_kick = maxf(0.0, rig.fire_kick - delta * 8.0)
	rig.flinch = maxf(0.0, rig.flinch - delta * 5.0)


func _wish_dir() -> Vector3:
	var fwd := Vector3(-sin(yaw), 0, -cos(yaw))
	var right := Vector3(cos(yaw), 0, -sin(yaw))
	var v := right * in_move.x + fwd * in_move.y
	return v.limit_length(1.0)


func _ground(delta: float) -> void:
	rotation.y = yaw
	if _mantle_t >= 0.0:
		_mantle_t += delta / 0.32
		global_position = _mantle_from.lerp(_mantle_to, smoothstep(0.0, 1.0, _mantle_t)) + Vector3(0, sin(minf(_mantle_t, 1.0) * PI) * 0.3, 0)
		velocity = Vector3.ZERO
		if _mantle_t >= 1.0:
			_mantle_t = -1.0
		return
	if lite:
		_lite_move(delta)
		return
	var on_floor := is_on_floor()
	var wish := _wish_dir()
	var moving := wish.length() > 0.1
	var forward_amt := in_move.y
	# crouch / slide
	var want_crouch := in_crouch
	var hspeed := Vector2(velocity.x, velocity.z).length()
	if want_crouch and not crouched and on_floor and hspeed > Cfg.SLIDE_MIN_SPEED:
		_sliding = true
	if not want_crouch:
		_sliding = false
	_set_crouch(want_crouch)
	var sprinting := in_sprint and moving and forward_amt > 0.3 and stamina > 1.0 and not in_aim and not crouched and use_left < 0.0 and not build_mode
	if sprinting and on_floor:
		stamina = maxf(0.0, stamina - Cfg.STAMINA_DRAIN * delta)
	elif not in_sprint or not moving:
		stamina = minf(Cfg.STAMINA_MAX, stamina + Cfg.STAMINA_REGEN * delta)
	var speed := Cfg.RUN_SPEED
	if sprinting:
		speed = Cfg.SPRINT_SPEED
	elif crouched:
		speed = Cfg.CROUCH_SPEED
	if in_aim and not current_weapon().is_empty():
		speed *= Cfg.ADS_MULT
	if forward_amt < -0.2:
		speed *= Cfg.BACKPEDAL_MULT
	if use_left >= 0.0:
		speed *= 0.45
	var target := wish * speed
	if _sliding and on_floor:
		var n := get_floor_normal()
		var downhill := Vector3(n.x, 0, n.z) * 20.0
		var hv := Vector3(velocity.x, 0, velocity.z)
		hv += downhill * delta
		hv = hv.move_toward(Vector3.ZERO, Cfg.SLIDE_FRICTION * delta)
		hv += wish * 2.0 * delta
		velocity.x = hv.x
		velocity.z = hv.z
		if hv.length() < 3.5:
			_sliding = false
	else:
		var accel := Cfg.GROUND_ACCEL if on_floor else Cfg.AIR_ACCEL
		var hv := Vector3(velocity.x, 0, velocity.z).move_toward(target, accel * delta)
		velocity.x = hv.x
		velocity.z = hv.z
	# gravity + jump
	if not on_floor:
		velocity.y = maxf(velocity.y - Cfg.GRAVITY * delta, -Cfg.MAX_FALL)
		if not _airborne:
			_airborne = true
			_fall_peak = global_position.y
		_fall_peak = maxf(_fall_peak, global_position.y)
		if moving and forward_amt > 0.3 and velocity.y < 2.0:
			_try_mantle()
	else:
		if _airborne:
			_land()
		_airborne = false
		velocity.y = minf(velocity.y, 0.0)
	var was_floor := on_floor
	move_and_slide()
	if was_floor and moving and on_floor:
		_step_t += delta * hspeed
		if _step_t > 2.1 and (is_player or game.near_player(global_position, 30.0)):
			_step_t = 0.0
			if not crouched:
				Sfx.play_at("step", global_position)
	# water
	if global_position.y < Cfg.SEA_LEVEL - 1.1:
		_enter_swim()
	if global_position.y < -40.0:
		take_damage(999.0, null, "fall", false, global_position)


func jump() -> void:
	if mode == Mode.GROUND and is_on_floor() and _mantle_t < 0.0:
		velocity.y = Cfg.JUMP_VELOCITY
		_sliding = false
		_set_crouch(false)
		if is_player:
			Sfx.play("jump")
	elif mode == Mode.GROUND and not is_on_floor() and _airborne:
		_try_mantle(true)
	elif mode == Mode.SWIM:
		velocity.y = 6.5
		mode = Mode.GROUND
		_airborne = true
		_fall_peak = global_position.y
	elif mode == Mode.SKYDIVE:
		if height_above_ground() > 15.0:
			deploy_glider()


func _set_crouch(c: bool) -> void:
	if c == crouched:
		return
	if not c:
		# can we stand up?
		var hit := game.combat.ray(global_position + Vector3(0, Cfg.CROUCH_HEIGHT, 0), global_position + Vector3(0, Cfg.CAPSULE_HEIGHT + 0.05, 0), [get_rid()], Cfg.L_WORLD | Cfg.L_BUILD)
		if not hit.is_empty():
			return
	crouched = c
	_capsule.height = Cfg.CROUCH_HEIGHT if c else Cfg.CAPSULE_HEIGHT
	_shape.position.y = _capsule.height * 0.5


func _try_mantle(forced := false) -> void:
	if _mantle_t >= 0.0:
		return
	var fwd := Vector3(-sin(yaw), 0, -cos(yaw))
	var chest := global_position + Vector3(0, 1.0, 0)
	var wall := game.combat.ray(chest, chest + fwd * 0.75, [get_rid()], Cfg.L_WORLD | Cfg.L_BUILD)
	if wall.is_empty() and not forced:
		return
	if wall.is_empty():
		return
	var top_from := global_position + fwd * 0.75 + Vector3(0, Cfg.MANTLE_MAX + 0.4, 0)
	var top := game.combat.ray(top_from, top_from + Vector3(0, -Cfg.MANTLE_MAX - 0.3, 0), [get_rid()], Cfg.L_WORLD | Cfg.L_BUILD)
	if top.is_empty() or (top.normal as Vector3).y < 0.7:
		return
	var rise: float = top.position.y - global_position.y
	if rise < 0.6 or rise > Cfg.MANTLE_MAX:
		return
	var dest: Vector3 = top.position + fwd * 0.3
	var head := game.combat.ray(dest + Vector3(0, 0.1, 0), dest + Vector3(0, 1.7, 0), [get_rid()], Cfg.L_WORLD | Cfg.L_BUILD)
	if not head.is_empty():
		return
	_mantle_from = global_position
	_mantle_to = dest
	_mantle_t = 0.0
	_airborne = false


func _land() -> void:
	var fall := _fall_peak - global_position.y
	if fall > 1.5 and (is_player or game.near_player(global_position, 40.0)):
		Sfx.play_at("land", global_position)
	if fall > Cfg.FALL_SAFE:
		var dmg := remap(fall, Cfg.FALL_SAFE, Cfg.FALL_LETHAL, 10.0, 100.0)
		take_damage(dmg, null, "fall", false, global_position, true)


## Far-away bot: move along terrain without physics.
func _lite_move(delta: float) -> void:
	var wish := _wish_dir()
	var speed := Cfg.SPRINT_SPEED if in_sprint else Cfg.RUN_SPEED
	velocity = wish * speed
	var p := global_position + velocity * delta
	var h := game.terrain.height_at(p.x, p.z)
	if h < Cfg.SEA_LEVEL - 1.2:
		h = Cfg.SEA_LEVEL - 1.2
	p.y = maxf(h, p.y - 30.0 * delta) if p.y > h + 0.5 else h
	global_position = p


func _enter_swim() -> void:
	mode = Mode.SWIM
	_airborne = false
	_set_crouch(false)
	build_mode = false


func _swim(delta: float) -> void:
	rotation.y = yaw
	var wish := _wish_dir()
	var target := wish * Cfg.SWIM_SPEED
	var hv := Vector3(velocity.x, 0, velocity.z).move_toward(target, 20.0 * delta)
	velocity.x = hv.x
	velocity.z = hv.z
	var float_y := Cfg.SEA_LEVEL - 1.25
	velocity.y = (float_y - global_position.y) * 4.0
	if lite:
		global_position += velocity * delta
	else:
		move_and_slide()
	stamina = minf(Cfg.STAMINA_MAX, stamina + Cfg.STAMINA_REGEN * delta)
	var ground := game.terrain.height_at(global_position.x, global_position.z)
	if ground > Cfg.SEA_LEVEL - 1.0:
		mode = Mode.GROUND
	if is_player and hv.length() > 1.0 and randf() < delta * 2.0:
		Sfx.play_at("step", global_position, 0.6)


# ------------------------------------------------------------------ drop

func start_skydive(vel: Vector3) -> void:
	mode = Mode.SKYDIVE
	velocity = vel
	visible = true
	_shape.disabled = false
	if is_player:
		Sfx.loop("wind", 0.0)


func height_above_ground() -> float:
	var h := game.terrain.height_at(global_position.x, global_position.z)
	if not lite:
		var hit := game.combat.ray(global_position, global_position + Vector3(0, -Cfg.AUTO_DEPLOY - 5.0, 0), [get_rid()], Cfg.L_WORLD | Cfg.L_BUILD)
		if not hit.is_empty():
			h = maxf(h, hit.position.y)
	return global_position.y - maxf(h, Cfg.SEA_LEVEL)


func _skydive(delta: float) -> void:
	rotation.y = yaw
	var look_down := clampf(-pitch / 1.3, 0.0, 1.0)
	var fwd_in := maxf(in_move.y, 0.0)
	dive = clampf(fwd_in * (0.35 + 0.65 * look_down), 0.0, 1.0)
	var vy := -lerpf(Cfg.DIVE_MIN_VERTICAL, Cfg.DIVE_MAX_VERTICAL, dive)
	var hmax := lerpf(12.75, Cfg.DIVE_HORIZONTAL, dive)
	var target := _wish_dir() * hmax
	var hv := Vector3(velocity.x, 0, velocity.z).move_toward(target, 18.0 * delta)
	velocity = Vector3(hv.x, move_toward(velocity.y, vy, 40.0 * delta), hv.z)
	global_position += velocity * delta
	if height_above_ground() < Cfg.AUTO_DEPLOY:
		deploy_glider()
	_clamp_to_map()


func deploy_glider() -> void:
	if mode != Mode.SKYDIVE:
		return
	mode = Mode.GLIDE
	if is_player or game.near_player(global_position, 60.0):
		Sfx.play_at("glider", global_position)


func _glide(delta: float) -> void:
	rotation.y = yaw
	var look_down := clampf(-pitch / 1.3, 0.0, 1.0)
	var fwd_in := maxf(in_move.y, 0.0)
	var vy := -lerpf(8.5, 16.0, fwd_in * look_down)
	var target := _wish_dir() * Cfg.GLIDE_HORIZONTAL
	var hv := Vector3(velocity.x, 0, velocity.z).move_toward(target, 14.0 * delta)
	velocity = Vector3(hv.x, move_toward(velocity.y, vy, 30.0 * delta), hv.z)
	if lite:
		global_position += velocity * delta
		var h := maxf(game.terrain.height_at(global_position.x, global_position.z), Cfg.SEA_LEVEL - 1.2)
		if global_position.y <= h + 0.05:
			global_position.y = h
			_touchdown()
	else:
		move_and_slide()
		if is_on_floor() or global_position.y < Cfg.SEA_LEVEL - 0.8:
			_touchdown()
	_clamp_to_map()


func _touchdown() -> void:
	mode = Mode.GROUND
	velocity = Vector3(velocity.x, 0, velocity.z) * 0.3
	_airborne = false
	if is_player:
		Sfx.loop("wind", -80.0)
		Sfx.play("land")


func _clamp_to_map() -> void:
	var lim := Terrain.EXTENT * 0.5 - 30.0
	global_position.x = clampf(global_position.x, -lim, lim)
	global_position.z = clampf(global_position.z, -lim, lim)


# ------------------------------------------------------------------ inventory

func select_slot(s: int) -> void:
	s = clampi(s, 0, Cfg.INVENTORY_SLOTS)
	if s == slot and not build_mode:
		return
	build_mode = false
	if s != slot:
		slot = s
		reload_left = -1.0
		use_left = -1.0
		_equip_cd = 0.25
		_swing_t = -1.0
	_refresh_held()
	_stop_emote()


func cycle_slot(dirn: int) -> void:
	select_slot(posmod(slot + dirn, Cfg.INVENTORY_SLOTS + 1))


func _refresh_held() -> void:
	if rig == null:
		return
	if build_mode:
		rig.set_held_mesh("")
		rig.hold = "build"
		return
	var it := current_item()
	if slot == 0 or it.is_empty():
		rig.set_held_mesh("pickaxe", skin % 3)
		rig.hold = "pickaxe"
		return
	rig.set_held_mesh(it.id, it.rarity)
	if Items.is_weapon(it):
		rig.hold = {"rifle": "rifle", "smg": "smg", "shotgun": "shotgun", "pistol": "pistol", "sniper": "sniper", "explosive": "rocket"}[Items.WEAPONS[it.id].slot_class]
	else:
		rig.hold = "consumable"


func add_ammo(t: String, n: int) -> int:
	var before: int = ammo[t]
	ammo[t] = mini(Items.AMMO_MAX, before + n)
	return ammo[t] - before


func add_mats(m: int, n: int) -> int:
	var before: int = mats[m]
	mats[m] = mini(Cfg.MAX_MATS, before + n)
	return mats[m] - before


## Returns true if the pickup was fully taken.
func take_pickup(pk: Loot.Pickup) -> bool:
	var d := pk.data
	if d.has("ammo"):
		add_ammo(d.ammo, d.count)
		game.loot.remove(pk)
		if is_player: Sfx.play("pickup")
		return true
	if d.has("mats"):
		add_mats(d.mats, d.count)
		game.loot.remove(pk)
		if is_player: Sfx.play("pickup")
		return true
	var item: Dictionary = d.item.duplicate()
	# stack consumables
	if not Items.is_weapon(item):
		var stack: int = Items.CONSUMABLES[item.id].stack
		for i in inventory.size():
			var s: Dictionary = inventory[i]
			if s.get("id", "") == item.id and s.count < stack:
				var add := mini(stack - s.count, item.count)
				s.count += add
				item.count -= add
				if item.count <= 0:
					game.loot.remove(pk)
					if is_player: Sfx.play("pickup")
					return true
	for i in inventory.size():
		if inventory[i].is_empty():
			inventory[i] = item
			game.loot.remove(pk)
			if slot == 0 and is_player and Items.is_weapon(item):
				pass
			if slot == i + 1:
				_refresh_held()
			if is_player: Sfx.play("pickup")
			return true
	# full: swap with held slot (pickaxe slot swaps into slot 1 like BR)
	var target := slot - 1 if slot > 0 else 0
	var old: Dictionary = inventory[target]
	inventory[target] = item
	game.loot.remove(pk)
	game.loot.spawn({"item": old}, global_position + Vector3(randf_range(-0.5, 0.5), 0.1, randf_range(-0.5, 0.5)))
	slot = target + 1
	_refresh_held()
	if is_player: Sfx.play("pickup")
	return true


func drop_current() -> void:
	if slot == 0:
		return
	var it: Dictionary = inventory[slot - 1]
	if it.is_empty():
		return
	inventory[slot - 1] = {}
	var fwd := Vector3(-sin(yaw), 0, -cos(yaw))
	var p := global_position + fwd * 1.5
	p.y = game.loot.ground_height(p)
	game.loot.spawn({"item": it}, p, global_position + Vector3(0, 1, 0))
	_refresh_held()


# ------------------------------------------------------------------ combat

func _combat(delta: float) -> void:
	var held := in_fire
	var pressed := held and not _fire_was_held
	_fire_was_held = held
	# reload
	if reload_left >= 0.0:
		reload_left -= delta
		var wr := current_weapon()
		if wr.is_empty():
			reload_left = -1.0
		else:
			rig.reload_t = 1.0 - reload_left / Items.reload_time(wr)
			if reload_left <= 0.0:
				_finish_reload()
	else:
		rig.reload_t = -1.0
	# consumable use
	if use_left >= 0.0:
		use_left -= delta
		rig.heal_t = 1.0 - use_left / use_total
		if use_left <= 0.0:
			_finish_use()
	else:
		rig.heal_t = -1.0
	# pickaxe swing anim
	if _swing_t >= 0.0:
		_swing_t += delta / 0.55
		rig.swing_t = _swing_t
		if _swing_t >= 0.45 and not _swing_hit_done:
			_swing_hit_done = true
			_pickaxe_hit()
		if _swing_t >= 1.0:
			_swing_t = -1.0
			rig.swing_t = -1.0
	if rig.build_t >= 0.0:
		rig.build_t += delta * 5.0
		if rig.build_t > 1.0:
			rig.build_t = -1.0
	if build_mode:
		if held and _build_cd <= 0.0:
			game.try_build(self)
		return
	if not held or _equip_cd > 0.0:
		return
	if slot == 0 or current_item().is_empty():
		if _swing_cd <= 0.0 and _swing_t < 0.0:
			_swing_t = 0.0
			_swing_hit_done = false
			_swing_cd = 0.5
			_stop_emote()
			if is_player or game.near_player(global_position, 25.0):
				Sfx.play_at("swing", global_position)
		return
	var it := current_item()
	if not Items.is_weapon(it):
		if pressed and use_left < 0.0:
			start_use()
		return
	var w: Dictionary = Items.WEAPONS[it.id]
	if not w.auto and not pressed:
		return
	if _fire_cd > 0.0 or reload_left >= 0.0:
		return
	if it.ammo <= 0:
		if pressed:
			if ammo[w.ammo] > 0:
				start_reload()
			elif is_player:
				Sfx.play("empty")
		return
	_fire(it, w)


func _fire(it: Dictionary, w: Dictionary) -> void:
	_stop_emote()
	use_left = -1.0
	_fire_cd = 1.0 / float(w.rate)
	it.ammo -= 1
	rig.fire_kick = 1.0
	var muzzle := eye_pos() + Vector3(-sin(yaw), 0, -cos(yaw)) * 0.7 + Vector3(cos(yaw), 0, -sin(yaw)) * 0.25 - Vector3(0, 0.25, 0)
	var shot_from := aim_from
	var dir := aim_dir.normalized()
	var spread := _current_spread(w)
	var dmg := Items.damage(it)
	var pellets: int = w.pellets
	var sfx_name: String = it.id if Sfx._sounds.has(it.id) else "ar"
	Sfx.play_at(sfx_name, muzzle)
	if is_player:
		game.player_fired(float(w.recoil))
	Fx.muzzle(muzzle, 1.6 if pellets > 1 else 1.0)
	if w.has("projectile"):
		var target := shot_from + dir * 600.0
		var hit := game.combat.ray(shot_from, target, [get_rid()])
		if not hit.is_empty():
			target = hit.position
		var pd := (target - muzzle).normalized()
		pd = _apply_spread(pd, spread)
		game.combat.spawn_projectile(self, muzzle, pd, float(w.projectile), dmg, float(w.head), float(w.struct), it.id, float(w.get("explosive", 0.0)))
	else:
		var any_head := false
		var any_hit := false
		var total := 0.0
		for p in pellets:
			var d := dir
			if pellets > 1 or spread > 0.0:
				d = _apply_spread(dir, spread)
			var rng_len: float = w.range
			var end := shot_from + d * rng_len
			var hit := game.combat.ray(shot_from, end, [get_rid()])
			# block shots that the gun itself can't see (third-person camera peeking)
			if not hit.is_empty():
				var from_gun := game.combat.ray(muzzle, hit.position + d * 0.05, [get_rid()])
				if not from_gun.is_empty() and from_gun.collider != hit.collider and from_gun.position.distance_to(hit.position) > 0.3:
					hit = from_gun
			var endp: Vector3 = end if hit.is_empty() else hit.position
			if p < 3 or pellets == 1:
				Fx.tracer(muzzle, endp)
			if hit.is_empty():
				continue
			var dist := shot_from.distance_to(hit.position)
			var full: float = rng_len * (0.25 if pellets > 1 else 0.18)
			var mult := 1.0
			if dist > full:
				mult = lerpf(1.0, float(w.falloff), clampf((dist - full) / (rng_len - full), 0.0, 1.0))
			var res := game.combat.apply_hit(self, hit, dmg / pellets * mult, float(w.head), float(w.struct), it.id)
			if res == "head" or res == "body":
				any_hit = true
				any_head = any_head or res == "head"
				total += dmg / pellets * mult
		if is_player and any_hit:
			on_hit_confirm(any_head, false)
	bloom = minf(bloom + float(w.bloom), 4.0)
	if it.ammo <= 0 and ammo[w.ammo] > 0:
		start_reload()


func _current_spread(w: Dictionary) -> float:
	var s: float = w.spread
	var moving := Vector2(velocity.x, velocity.z).length() > 0.5
	if in_aim:
		s *= 0.5
	if crouched:
		s *= 0.75
	if moving:
		s *= 1.35
	if mode == Mode.GROUND and not is_on_floor():
		s *= 2.0
	if w.first_shot and bloom < 0.05 and not moving and (in_aim or crouched):
		return 0.0
	return s + bloom * (0.55 if in_aim else 1.0)


func _apply_spread(d: Vector3, deg: float) -> Vector3:
	if deg <= 0.0:
		return d
	var r := deg_to_rad(deg) * sqrt(randf())
	var a := randf() * TAU
	var up := Vector3.UP if absf(d.y) < 0.95 else Vector3.RIGHT
	var right := d.cross(up).normalized()
	var u := right.cross(d).normalized()
	return (d + (right * cos(a) + u * sin(a)) * tan(r)).normalized()


func current_spread_deg() -> float:
	var w := current_weapon()
	if w.is_empty():
		return 0.0
	return _current_spread(Items.WEAPONS[w.id])


func start_reload() -> void:
	var it := current_weapon()
	if it.is_empty() or reload_left >= 0.0:
		return
	var w: Dictionary = Items.WEAPONS[it.id]
	if it.ammo >= w.mag or ammo[w.ammo] <= 0:
		return
	reload_left = Items.reload_time(it)
	if is_player or game.near_player(global_position, 30.0):
		Sfx.play_at("reload", global_position)


func _finish_reload() -> void:
	reload_left = -1.0
	var it := current_weapon()
	if it.is_empty():
		return
	var w: Dictionary = Items.WEAPONS[it.id]
	var need: int = w.mag - it.ammo
	var take: int = mini(need, ammo[w.ammo])
	it.ammo += take
	ammo[w.ammo] -= take


func start_use() -> void:
	var it := current_item()
	if it.is_empty() or Items.is_weapon(it):
		return
	var c: Dictionary = Items.CONSUMABLES[it.id]
	var cur := health if c.stat == "health" else shield
	if cur >= float(c.max):
		return
	use_total = float(c.time)
	use_left = use_total


func _finish_use() -> void:
	use_left = -1.0
	var it := current_item()
	if it.is_empty() or Items.is_weapon(it):
		return
	var c: Dictionary = Items.CONSUMABLES[it.id]
	if c.stat == "health":
		health = minf(maxf(health, minf(float(c.max), health + float(c.heal))), Cfg.MAX_HEALTH)
	else:
		shield = minf(maxf(shield, minf(float(c.max), shield + float(c.heal))), Cfg.MAX_SHIELD)
	it.count -= 1
	if is_player or game.near_player(global_position, 20.0):
		Sfx.play_at("heal", global_position)
	if it.count <= 0:
		inventory[slot - 1] = {}
		_refresh_held()


func _pickaxe_hit() -> void:
	var dir := aim_dir.normalized()
	var from := eye_pos()
	var hit := game.combat.ray(from, from + dir * 2.6, [get_rid()])
	if hit.is_empty():
		# second try straight ahead at chest height (bots / low targets)
		var fwd := Vector3(-sin(yaw), 0, -cos(yaw))
		hit = game.combat.ray(global_position + Vector3(0, 1.0, 0), global_position + Vector3(0, 1.0, 0) + fwd * 2.4, [get_rid()])
	if hit.is_empty():
		return
	var col: Object = hit.collider
	if col is Pawn:
		game.combat.apply_hit(self, hit, Cfg.PICKAXE_PLAYER_DMG, 1.0, 1.0, "pickaxe")
		if is_player:
			on_hit_confirm(false, false)
		return
	if col is Node and (col as Node).has_meta("dest"):
		var d: Structures.Destructible = (col as Node).get_meta("dest")
		var crit := game.check_weakspot(self, d, hit.position)
		var amount := Cfg.PICKAXE_STRUCT_DMG * (2.0 if crit else 1.0)
		if d.max_hp >= 9000.0:
			amount = 0.0
		if d.harvest:
			var got := add_mats(d.mat, d.harvest_yield * (2 if crit else 1))
			if is_player and got > 0:
				Fx.number(hit.position + Vector3.UP * 0.3, "+%d" % got, 4)
		if amount > 0.0:
			game.structures.damage(d, amount)
			if is_player:
				Fx.number(hit.position, str(int(amount)), 2 if crit else 3)
		if is_player or game.near_player(hit.position, 40.0):
			Sfx.play_at("pickaxe_crit" if crit else "pickaxe_hit", hit.position)
		Fx.impact(hit.position, hit.normal, d.tint)
	else:
		Fx.impact(hit.position, hit.normal)
		if is_player:
			Sfx.play_at("pickaxe_hit", hit.position, 0.8)


func on_hit_confirm(head: bool, shield_hit: bool) -> void:
	game.player_hit_marker(head, shield_hit)


func shake(amount: float) -> void:
	if is_player:
		game.camera_shake(amount)


func take_damage(amount: float, attacker: Pawn, weapon: String, head: bool, at: Vector3, bypass_shield := false) -> void:
	if mode == Mode.DEAD or mode == Mode.BUS or amount <= 0.0:
		return
	if game.ended:
		return
	var to_shield := 0.0
	if not bypass_shield:
		to_shield = minf(shield, amount)
	shield -= to_shield
	var to_health := amount - to_shield
	var shield_broke := to_shield > 0.0 and shield <= 0.0
	health -= to_health
	rig.flinch = 1.0
	hit_flash = 1.0
	if attacker:
		last_attacker = attacker
		last_hit_time = game.time
		attacker.damage_dealt += amount
		if attacker.is_player:
			if to_shield > 0.0:
				Fx.number(at, str(roundi(to_shield)), 1)
			if to_health > 0.0:
				Fx.number(at + Vector3(0.15, 0.1, 0), str(roundi(to_health)), 2 if head else 0)
			if head:
				Sfx.play("headshot")
			elif to_shield > 0.0:
				Sfx.play("shield_hit")
			else:
				Sfx.play("hit")
			if shield_broke:
				Sfx.play_at("shield_break", at)
	if is_player:
		Sfx.play("damage_taken", 1.0, -4.0)
		game.player_damaged(attacker, amount)
	reload_left = -1.0 if reload_left > 0.0 and false else reload_left
	use_left = -1.0
	if health <= 0.0:
		die(attacker if attacker else (last_attacker if game.time - last_hit_time < 10.0 else null), weapon)


func die(killer: Pawn, weapon: String) -> void:
	if mode == Mode.DEAD:
		return
	mode = Mode.DEAD
	health = 0.0
	shield = 0.0
	velocity = Vector3.ZERO
	_shape.set_deferred("disabled", true)
	rig.pose = CharacterRig.Pose.DEAD
	rig.glider.visible = false
	build_mode = false
	_drop_everything()
	if killer and killer != self:
		killer.kills += 1
	eliminated.emit(self, killer, weapon)
	# beam-out: shrink and float away
	var tw := create_tween()
	tw.tween_interval(1.4)
	tw.tween_property(rig, "scale", Vector3(0.05, 1.6, 0.05), 0.35)
	tw.tween_callback(func() -> void: visible = false)


func _drop_everything() -> void:
	var base := global_position
	base.y = game.loot.ground_height(base)
	var drops := []
	for it: Dictionary in inventory:
		if not it.is_empty():
			drops.append({"item": it})
	for t: String in ammo:
		if ammo[t] > 0:
			drops.append({"ammo": t, "count": ammo[t]})
	for m in 3:
		if mats[m] > 0:
			drops.append({"mats": m, "count": mats[m]})
	inventory = [{}, {}, {}, {}, {}]
	var n := drops.size()
	for i in n:
		var a := TAU * i / maxf(n, 1)
		var p := base + Vector3(cos(a), 0, sin(a)) * (1.2 + (i % 2) * 0.8)
		p.y = game.loot.ground_height(p)
		game.loot.spawn(drops[i], p, base + Vector3(0, 1, 0))


# ------------------------------------------------------------------ emotes

func start_emote(e: int) -> void:
	if mode != Mode.GROUND or not is_on_floor():
		return
	emote_id = e
	_emote_t = 0.0
	build_mode = false


func _stop_emote() -> void:
	emote_id = -1
	_emote_t = -1.0


# ------------------------------------------------------------------ rig

func _drive_rig(delta: float) -> void:
	if not visible:
		return
	var local_v := Vector3(velocity.x, 0, velocity.z).rotated(Vector3.UP, -yaw)
	rig.move_local = Vector2(local_v.x, -local_v.z)
	rig.sprinting = Vector2(velocity.x, velocity.z).length() > Cfg.RUN_SPEED + 0.5
	rig.crouching = crouched and not _sliding
	rig.aim_pitch = pitch
	rig.dive = dive
	match mode:
		Mode.SKYDIVE: rig.pose = CharacterRig.Pose.SKYDIVE
		Mode.GLIDE: rig.pose = CharacterRig.Pose.GLIDE
		Mode.SWIM: rig.pose = CharacterRig.Pose.SWIM
		_:
			if _sliding:
				rig.pose = CharacterRig.Pose.SLIDE
			elif not lite and not is_on_floor() and _mantle_t < 0.0 and velocity.y < -3.0 or (not lite and velocity.y > 2.0):
				rig.pose = CharacterRig.Pose.AIR
			else:
				rig.pose = CharacterRig.Pose.GROUND
	if emote_id >= 0:
		_emote_t += delta
		if Vector2(velocity.x, velocity.z).length() > 0.5 or in_fire:
			_stop_emote()
	rig.emote = emote_id
	rig.emote_t = maxf(_emote_t, 0.0)
	if build_mode:
		if rig.hold != "build":
			_refresh_held()
	elif rig.hold == "build":
		_refresh_held()


func set_build_mode(on: bool, kind := -1) -> void:
	if mode != Mode.GROUND:
		return
	build_mode = on
	if kind >= 0:
		build_kind = kind
	use_left = -1.0
	reload_left = -1.0
	_stop_emote()
	_refresh_held()


func on_built() -> void:
	_build_cd = 0.12
	rig.build_t = 0.0
