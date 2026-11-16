class_name BotBrain
extends RefCounted
## Battle-royale bot: picks a drop, loots, rotates with the storm, fights
## with skill-scaled aim, builds cover when shot, heals when safe.
## think() runs a few times per second; steer() every physics frame.

enum State { BUS, DROP, LOOT, ROAM, FIGHT, HEAL, HARVEST }

var pawn: Pawn
var game: Match
var state := State.BUS
var skill := 0.5
var rng := RandomNumberGenerator.new()
var jump_at := 0.0            # bus progress 0..1 at which to jump
var drop_target := Vector2.ZERO
var move_target := Vector3.INF
var enemy: Pawn
var loot_pickup: Loot.Pickup
var loot_chest: Loot.Chest
var harvest_target := Vector3.INF
var _stuck_t := 0.0
var _last_pos := Vector3.ZERO
var _strafe := 1.0
var _strafe_t := 0.0
var _think_t := 0.0
var _hit_react_t := 0.0
var _last_health := 200.0
var _aim_err := Vector3.ZERO
var _jump_cd := 0.0
var _chest_t := 0.0


func _init(p: Pawn, g: Match, seed_value: int) -> void:
	pawn = p
	game = g
	rng.seed = seed_value
	skill = clampf(rng.randfn(0.45, 0.18), 0.1, 0.9)


func plan_drop(bus_a: Vector2, bus_b: Vector2) -> void:
	# most bots go to named spots, some to random land
	if rng.randf() < 0.75:
		var poi: Dictionary = Terrain.POIS[rng.randi() % Terrain.POIS.size()]
		drop_target = poi.pos + Vector2.from_angle(rng.randf() * TAU) * rng.randf() * poi.r
	else:
		for i in 30:
			var p := Vector2(rng.randf_range(-1200, 1200), rng.randf_range(-1200, 1200))
			if game.terrain.height_at(p.x, p.y) > 3.0:
				drop_target = p
				break
	# jump where the bus passes closest to the target (minus a little lead)
	var ab := bus_b - bus_a
	var t := clampf((drop_target - bus_a).dot(ab) / ab.length_squared(), 0.05, 0.95)
	jump_at = clampf(t - rng.randf_range(0.02, 0.1), 0.03, 0.97)


## Low-frequency decisions.
func think(delta: float) -> void:
	_think_t += delta
	_jump_cd = maxf(0.0, _jump_cd - delta)
	if not pawn.is_alive():
		return
	match pawn.mode:
		Pawn.Mode.BUS:
			state = State.BUS
			return
		Pawn.Mode.SKYDIVE, Pawn.Mode.GLIDE:
			state = State.DROP
			return
	if state == State.DROP or state == State.BUS:
		state = State.LOOT
	_auto_equip()
	var took_damage := pawn.health + pawn.shield < _last_health - 0.5
	_last_health = pawn.health + pawn.shield
	if took_damage:
		_hit_react_t = 1.2
		if pawn.last_attacker and pawn.last_attacker.is_alive() and pawn.last_attacker != pawn:
			enemy = pawn.last_attacker
	_find_enemy()
	if enemy and _has_weapon():
		state = State.FIGHT
		if took_damage and pawn.mats[0] >= Cfg.BUILD_COST and rng.randf() < 0.25 + skill * 0.5:
			_build_cover()
		return
	if pawn.build_mode:
		pawn.set_build_mode(false)
	# storm
	var st: Storm = game.storm
	var pos2 := Vector2(pawn.global_position.x, pawn.global_position.z)
	var outside_next := pos2.distance_to(st.next_center) > st.next_radius * 0.85
	var outside_now := st.is_outside(pawn.global_position)
	if outside_now or (outside_next and (not st.waiting or st.timer < 45.0)):
		var to := st.next_center + (pos2 - st.next_center).normalized() * st.next_radius * 0.4
		move_target = Vector3(to.x, 0, to.y)
		state = State.ROAM
		pawn.in_sprint = true
		return
	# heal when hurt and safe
	if (pawn.health < 70.0 or pawn.shield < 50.0) and _select_heal():
		state = State.HEAL
		return
	# loot
	if _want_loot():
		state = State.LOOT
		return
	if pawn.mats[0] < 60 and rng.randf() < 0.5:
		state = State.HARVEST
		return
	state = State.ROAM
	if move_target == Vector3.INF or Vector2(move_target.x - pawn.global_position.x, move_target.z - pawn.global_position.z).length() < 6.0:
		var r := st.next_radius * 0.7
		var p := st.next_center + Vector2.from_angle(rng.randf() * TAU) * rng.randf() * minf(r, 300.0)
		move_target = Vector3(p.x, 0, p.y)


func _has_weapon() -> bool:
	for it: Dictionary in pawn.inventory:
		if Items.is_weapon(it) and (it.ammo > 0 or pawn.ammo[Items.WEAPONS[it.id].ammo] > 0):
			return true
	return false


func _auto_equip() -> void:
	if state == State.HEAL or state == State.HARVEST:
		return
	# pick the best weapon for the current range
	var best := 0
	var best_score := -1.0
	var dist := 30.0
	if enemy:
		dist = enemy.global_position.distance_to(pawn.global_position)
	for i in pawn.inventory.size():
		var it: Dictionary = pawn.inventory[i]
		if not Items.is_weapon(it):
			continue
		var w: Dictionary = Items.WEAPONS[it.id]
		if it.ammo <= 0 and pawn.ammo[w.ammo] <= 0:
			continue
		var score := float(w.dmg[it.rarity]) * float(w.rate)
		if w.pellets > 1:
			score *= 2.0 if dist < 12.0 else 0.2
		elif w.has("scope"):
			score *= 2.5 if dist > 60.0 else 0.3
		elif w.slot_class == "smg":
			score *= 1.3 if dist < 25.0 else 0.6
		if score > best_score:
			best_score = score
			best = i + 1
	if best > 0 and pawn.slot != best:
		pawn.select_slot(best)


func _find_enemy() -> void:
	if enemy and (not enemy.is_alive() or enemy.global_position.distance_to(pawn.global_position) > 160.0):
		enemy = null
	if enemy and _think_t < 0.6:
		return
	_think_t = 0.0
	var best: Pawn = null
	var bd := 25.0 + skill * 95.0
	for pw: Pawn in game.pawns_near(pawn.global_position, bd):
		if pw == pawn or pw.mode != Pawn.Mode.GROUND and pw.mode != Pawn.Mode.SWIM:
			continue
		var d := pw.global_position.distance_to(pawn.global_position)
		if d < bd and _can_see(pw):
			bd = d
			best = pw
	if best:
		enemy = best


func _can_see(pw: Pawn) -> bool:
	if pawn.lite:
		return true
	var hit := game.combat.ray(pawn.eye_pos(), pw.global_position + Vector3(0, 1.2, 0), [pawn.get_rid(), pw.get_rid()], Cfg.L_WORLD | Cfg.L_BUILD)
	return hit.is_empty()


func _want_loot() -> bool:
	var need_weapon := not _has_weapon()
	var empty := 0
	for it: Dictionary in pawn.inventory:
		if it.is_empty():
			empty += 1
	if loot_chest and not loot_chest.opened:
		return true
	if loot_pickup and loot_pickup.alive:
		return true
	loot_chest = null
	loot_pickup = null
	var radius := 70.0 if need_weapon else 35.0
	if empty > 0 or need_weapon:
		loot_chest = game.loot.nearest_chest(pawn.global_position, radius)
		if loot_chest:
			return true
		var pk := game.loot.nearest_pickup(pawn.global_position, radius)
		if pk and (Items.is_weapon(pk.data.item) or empty > 1):
			loot_pickup = pk
			return true
	return false


func _select_heal() -> bool:
	for i in pawn.inventory.size():
		var it: Dictionary = pawn.inventory[i]
		if it.is_empty() or Items.is_weapon(it):
			continue
		var c: Dictionary = Items.CONSUMABLES[it.id]
		var cur := pawn.health if c.stat == "health" else pawn.shield
		if cur < float(c.max):
			pawn.select_slot(i + 1)
			return true
	return false


func _build_cover() -> void:
	if enemy == null or pawn.mode != Pawn.Mode.GROUND:
		return
	var to := enemy.global_position - pawn.global_position
	pawn.yaw = atan2(-to.x, -to.z)
	pawn.pitch = 0.0
	pawn.build_mat = 0
	pawn.build_kind = PieceMeshes.Kind.WALL if rng.randf() < 0.7 else PieceMeshes.Kind.RAMP
	game.try_build(pawn)
	if rng.randf() < skill:
		pawn.build_kind = PieceMeshes.Kind.RAMP
		game.try_build(pawn)


## Per-frame control output.
func steer(delta: float) -> void:
	if not pawn.is_alive():
		return
	pawn.in_fire = false
	pawn.in_aim = false
	pawn.in_crouch = false
	pawn.in_move = Vector2.ZERO
	_hit_react_t = maxf(0.0, _hit_react_t - delta)
	match state:
		State.BUS:
			if game.bus_progress() >= jump_at:
				game.eject(pawn)
		State.DROP:
			_steer_drop()
		State.FIGHT:
			_steer_fight(delta)
		State.LOOT:
			_steer_loot(delta)
		State.HEAL:
			pawn.in_fire = true
			pawn.in_sprint = false
			if pawn.current_item().is_empty() or Items.is_weapon(pawn.current_item()):
				state = State.ROAM
		State.HARVEST:
			_steer_harvest(delta)
		_:
			if move_target != Vector3.INF:
				_go_to(move_target, delta, 4.0)
	_unstick(delta)


func _steer_drop() -> void:
	var p := pawn.global_position
	var to := Vector3(drop_target.x - p.x, 0, drop_target.y - p.z)
	pawn.yaw = atan2(-to.x, -to.z)
	var dist := to.length()
	var h := pawn.height_above_ground()
	# dive if the target is close relative to height, otherwise glide flat
	pawn.pitch = -1.2 if dist < h * 0.9 else -0.3
	pawn.in_move = Vector2(0, 1 if dist > 8.0 else 0)


func _steer_fight(delta: float) -> void:
	if enemy == null or not enemy.is_alive():
		enemy = null
		state = State.ROAM
		return
	var target := enemy.global_position + Vector3(0, 1.25, 0)
	if enemy.crouched:
		target.y -= 0.4
	var from := pawn.eye_pos()
	var dist := from.distance_to(target)
	_aim_err = _aim_err.lerp(Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.6, 1), rng.randf_range(-1, 1)) * (1.4 - skill) * (0.25 + dist * 0.025), clampf(delta * 3.0, 0.0, 1.0))
	var aim_pt := target + _aim_err
	var dir := (aim_pt - from).normalized()
	pawn.yaw = atan2(-dir.x, -dir.z)
	pawn.pitch = asin(clampf(dir.y, -1.0, 1.0))
	pawn.aim_from = from
	pawn.aim_dir = dir
	pawn.in_sprint = false
	var w := pawn.current_weapon()
	if w.is_empty():
		_auto_equip()
		return
	var wd: Dictionary = Items.WEAPONS[w.id]
	var want := 7.0 if wd.pellets > 1 else (60.0 if wd.has("scope") else 22.0)
	# strafe and keep preferred range
	_strafe_t -= delta
	if _strafe_t <= 0.0:
		_strafe_t = rng.randf_range(0.4, 1.4)
		_strafe = -_strafe if rng.randf() < 0.6 else _strafe
	var fwd := 0.0
	if dist > want * 1.4:
		fwd = 1.0
	elif dist < want * 0.6:
		fwd = -0.7
	pawn.in_move = Vector2(_strafe * (0.5 + skill * 0.5), fwd)
	pawn.in_aim = dist > 18.0 and not wd.pellets > 1
	pawn.in_crouch = rng.randf() < 0.02 and dist > 30.0
	if _jump_cd <= 0.0 and rng.randf() < 0.01 + skill * 0.02:
		pawn.jump()
		_jump_cd = 1.5
	# fire: semi-auto weapons are pulsed
	var reaction_ok := _hit_react_t < 1.0 or skill > 0.6
	if reaction_ok and dist < float(wd.range):
		if wd.auto:
			pawn.in_fire = true
		else:
			pawn.in_fire = (Engine.get_physics_frames() + pawn.id) % 6 < 3
	if w.ammo <= 0:
		pawn.start_reload()


func _steer_loot(delta: float) -> void:
	if loot_chest and not loot_chest.opened:
		var d := loot_chest.pos.distance_to(pawn.global_position)
		if d < 2.3:
			_chest_t += delta
			if _chest_t > 0.4:
				game.loot.open_chest(loot_chest)
				loot_chest = null
				_chest_t = 0.0
		else:
			_chest_t = 0.0
			_go_to(loot_chest.pos, delta, 1.8)
		return
	if loot_pickup and loot_pickup.alive:
		if loot_pickup.pos.distance_to(pawn.global_position) < 2.2:
			pawn.take_pickup(loot_pickup)
			loot_pickup = null
		else:
			_go_to(loot_pickup.pos, delta, 1.5)
		return
	# grab ammo / mats underfoot
	for pk: Loot.Pickup in game.loot.pickups_near(pawn.global_position, 1.8):
		if not pk.data.has("item"):
			pawn.take_pickup(pk)
	state = State.ROAM


func _steer_harvest(delta: float) -> void:
	if harvest_target == Vector3.INF:
		harvest_target = pawn.global_position + Vector3(rng.randf_range(-20, 20), 0, rng.randf_range(-20, 20))
	pawn.select_slot(0)
	var fwd := Vector3(-sin(pawn.yaw), 0, -cos(pawn.yaw))
	var hit := game.combat.ray(pawn.global_position + Vector3(0, 1, 0), pawn.global_position + Vector3(0, 1, 0) + fwd * 2.2, [pawn.get_rid()], Cfg.L_WORLD | Cfg.L_BUILD) if not pawn.lite else {}
	if not hit.is_empty() and (hit.collider as Node).has_meta("dest"):
		var d: Structures.Destructible = (hit.collider as Node).get_meta("dest")
		if d.harvest and d.owner_id < 0:
			pawn.aim_from = pawn.eye_pos()
			pawn.aim_dir = (hit.position - pawn.eye_pos()).normalized()
			pawn.in_fire = true
			if pawn.mats[0] >= 150:
				harvest_target = Vector3.INF
				state = State.ROAM
			return
	if pawn.lite:
		pawn.add_mats(0, 1)
		if pawn.mats[0] >= 150:
			state = State.ROAM
		return
	_go_to(harvest_target, delta, 2.0)
	if Vector2(harvest_target.x - pawn.global_position.x, harvest_target.z - pawn.global_position.z).length() < 2.5:
		harvest_target = Vector3.INF


func _go_to(target: Vector3, _delta: float, arrive: float) -> void:
	var to := Vector3(target.x - pawn.global_position.x, 0, target.z - pawn.global_position.z)
	if to.length() < arrive:
		return
	pawn.yaw = atan2(-to.x, -to.z)
	pawn.pitch = lerpf(pawn.pitch, 0.0, 0.2)
	pawn.in_move = Vector2(0, 1)
	pawn.in_sprint = to.length() > 15.0 and pawn.stamina > 20.0
	pawn.aim_from = pawn.eye_pos()
	pawn.aim_dir = Vector3(-sin(pawn.yaw), 0, -cos(pawn.yaw))


func _unstick(delta: float) -> void:
	if pawn.mode != Pawn.Mode.GROUND or pawn.in_move.length() < 0.1 or pawn.lite:
		_stuck_t = 0.0
		_last_pos = pawn.global_position
		return
	var moved := pawn.global_position.distance_to(_last_pos)
	_last_pos = pawn.global_position
	if moved < delta * 1.2:
		_stuck_t += delta
	else:
		_stuck_t = maxf(0.0, _stuck_t - delta)
	if _stuck_t > 0.5 and _jump_cd <= 0.0:
		pawn.jump()
		_jump_cd = 0.8
	if _stuck_t > 1.4:
		# smash through whatever is in the way, or turn
		if rng.randf() < 0.5:
			pawn.select_slot(0)
			pawn.in_fire = true
			pawn.aim_from = pawn.eye_pos()
			pawn.aim_dir = Vector3(-sin(pawn.yaw), 0, -cos(pawn.yaw))
		else:
			pawn.yaw += rng.randf_range(-1.5, 1.5)
		if _stuck_t > 3.0:
			_stuck_t = 0.0
			move_target = Vector3.INF
			loot_chest = null
			loot_pickup = null
