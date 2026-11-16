class_name Items
extends RefCounted
## Weapon, consumable and ammo definitions. Damage arrays are per rarity
## (common..legendary); -1 means that rarity does not drop.

const WEAPONS := {
	"ar": {
		"name": "Assault Rifle", "ammo": "medium", "dmg": [30, 31, 33, 35, 36], "rate": 5.5,
		"mag": 30, "reload": [2.7, 2.6, 2.5, 2.4, 2.3], "head": 1.5, "spread": 2.4, "first_shot": true,
		"bloom": 0.55, "range": 280.0, "falloff": 0.7, "struct": 1.0, "pellets": 1, "ads_fov": 52.0,
		"auto": true, "weights": [24, 20, 12, 5, 2], "slot_class": "rifle", "recoil": 0.9,
	},
	"pump": {
		"name": "Pump Shotgun", "ammo": "shells", "dmg": [-1, 80, 85, 90, 95], "rate": 0.7,
		"mag": 5, "reload": [-1, 4.8, 4.6, 4.4, 4.2], "head": 2.0, "spread": 6.0, "first_shot": false,
		"bloom": 0.0, "range": 40.0, "falloff": 0.15, "struct": 0.55, "pellets": 10, "ads_fov": 65.0,
		"auto": false, "weights": [0, 14, 10, 4, 2], "slot_class": "shotgun", "recoil": 4.0,
	},
	"tac": {
		"name": "Tactical Shotgun", "ammo": "shells", "dmg": [67, 70, 74, 77, 81], "rate": 1.5,
		"mag": 8, "reload": [6.3, 6.0, 5.7, 5.4, 5.1], "head": 2.0, "spread": 7.0, "first_shot": false,
		"bloom": 0.0, "range": 35.0, "falloff": 0.2, "struct": 0.5, "pellets": 10, "ads_fov": 65.0,
		"auto": false, "weights": [16, 14, 8, 2, 0], "slot_class": "shotgun", "recoil": 3.0,
	},
	"smg": {
		"name": "Rapid SMG", "ammo": "light", "dmg": [17, 18, 19, 20, 21], "rate": 12.0,
		"mag": 30, "reload": [2.2, 2.1, 2.0, 1.9, 1.8], "head": 1.75, "spread": 3.6, "first_shot": false,
		"bloom": 0.3, "range": 120.0, "falloff": 0.55, "struct": 0.9, "pellets": 1, "ads_fov": 58.0,
		"auto": true, "weights": [18, 16, 10, 3, 1], "slot_class": "smg", "recoil": 0.6,
	},
	"pistol": {
		"name": "Sidearm Pistol", "ammo": "light", "dmg": [23, 24, 25, 26, 27], "rate": 6.75,
		"mag": 16, "reload": [1.5, 1.45, 1.4, 1.35, 1.3], "head": 2.0, "spread": 2.0, "first_shot": true,
		"bloom": 0.6, "range": 150.0, "falloff": 0.6, "struct": 0.8, "pellets": 1, "ads_fov": 60.0,
		"auto": false, "weights": [20, 14, 6, 0, 0], "slot_class": "pistol", "recoil": 1.2,
	},
	"sniper": {
		"name": "Bolt Sniper", "ammo": "heavy", "dmg": [-1, -1, 105, 110, 116], "rate": 0.33,
		"mag": 1, "reload": [-1, -1, 3.0, 2.85, 2.7], "head": 2.5, "spread": 4.0, "first_shot": true,
		"bloom": 0.0, "range": 1200.0, "falloff": 1.0, "struct": 1.0, "pellets": 1, "ads_fov": 18.0,
		"auto": false, "weights": [0, 0, 5, 3, 1], "slot_class": "sniper", "recoil": 5.0,
		"projectile": 450.0, "scope": true,
	},
	"rocket": {
		"name": "Rocket Launcher", "ammo": "rockets", "dmg": [-1, -1, -1, 110, 121], "rate": 0.75,
		"mag": 1, "reload": [-1, -1, -1, 3.0, 2.8], "head": 1.0, "spread": 0.5, "first_shot": true,
		"bloom": 0.0, "range": 600.0, "falloff": 1.0, "struct": 4.0, "pellets": 1, "ads_fov": 60.0,
		"auto": false, "weights": [0, 0, 0, 2, 1], "slot_class": "explosive", "recoil": 4.0,
		"projectile": 70.0, "explosive": 5.0,
	},
}

## time: seconds to use. max: cap of the stat it restores.
const CONSUMABLES := {
	"bandage": {"name": "Bandages", "stack": 15, "time": 3.5, "heal": 15.0, "max": 75.0, "stat": "health", "drop": 5, "rarity": 0, "weight": 14},
	"medkit": {"name": "Medkit", "stack": 3, "time": 10.0, "heal": 100.0, "max": 100.0, "stat": "health", "drop": 1, "rarity": 1, "weight": 7},
	"mini": {"name": "Small Shield Potion", "stack": 6, "time": 2.0, "heal": 25.0, "max": 50.0, "stat": "shield", "drop": 3, "rarity": 1, "weight": 12},
	"shieldpot": {"name": "Shield Potion", "stack": 3, "time": 5.0, "heal": 50.0, "max": 100.0, "stat": "shield", "drop": 1, "rarity": 2, "weight": 7},
}

const AMMO := {
	"light": {"name": "Light Bullets", "drop": 18, "color": Color(0.55, 0.85, 1.0)},
	"medium": {"name": "Medium Bullets", "drop": 20, "color": Color(0.5, 0.9, 0.4)},
	"heavy": {"name": "Heavy Bullets", "drop": 6, "color": Color(0.95, 0.4, 0.35)},
	"shells": {"name": "Shells", "drop": 5, "color": Color(1.0, 0.8, 0.3)},
	"rockets": {"name": "Rockets", "drop": 2, "color": Color(0.85, 0.85, 0.85)},
}
const AMMO_MAX := 999


static func make_weapon(id: String, rarity: int) -> Dictionary:
	var w: Dictionary = WEAPONS[id]
	return {"id": id, "rarity": rarity, "ammo": w.mag}


static func make_consumable(id: String, count := -1) -> Dictionary:
	var c: Dictionary = CONSUMABLES[id]
	return {"id": id, "rarity": c.rarity, "count": c.drop if count < 0 else count}


static func is_weapon(item: Dictionary) -> bool:
	return WEAPONS.has(item.get("id", ""))


static func display_name(item: Dictionary) -> String:
	if is_weapon(item):
		return WEAPONS[item.id].name
	return CONSUMABLES[item.id].name


static func damage(item: Dictionary) -> float:
	return float(WEAPONS[item.id].dmg[item.rarity])


static func reload_time(item: Dictionary) -> float:
	return float(WEAPONS[item.id].reload[item.rarity])


## Weighted random weapon (id, rarity). chest=true biases rarity upward.
static func roll_weapon(rng: RandomNumberGenerator, chest := false) -> Dictionary:
	var pool := []
	var total := 0.0
	for id: String in WEAPONS:
		var w: Dictionary = WEAPONS[id]
		for r in 5:
			var wt: float = w.weights[r]
			if wt <= 0.0 or w.dmg[r] < 0:
				continue
			if chest:
				wt *= [0.6, 1.0, 1.4, 1.8, 2.2][r]
			pool.append([id, r, wt])
			total += wt
	var pick := rng.randf() * total
	for e: Array in pool:
		pick -= e[2]
		if pick <= 0.0:
			return make_weapon(e[0], e[1])
	return make_weapon("ar", 0)


static func roll_consumable(rng: RandomNumberGenerator) -> Dictionary:
	var total := 0.0
	for id: String in CONSUMABLES:
		total += CONSUMABLES[id].weight
	var pick := rng.randf() * total
	for id: String in CONSUMABLES:
		pick -= CONSUMABLES[id].weight
		if pick <= 0.0:
			return make_consumable(id)
	return make_consumable("bandage")
