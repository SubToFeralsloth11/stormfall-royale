class_name Skins
extends RefCounted
## 20 original outfits. Fields:
## skin, top, accent, pants, shoes, gloves (colours); hair: style id; hair_col;
## hat; back (back bling); extra; build (body width scale); sleeves: "long"/"short".

const HAIR_NONE := 0
const HAIR_SHORT := 1
const HAIR_LONG := 2
const HAIR_BUN := 3
const HAIR_MOHAWK := 4
const HAIR_PONY := 5
const HAIR_CURLY := 6
const HAIR_SPIKY := 7

const LIST := [
	{"name": "Scout Rookie", "skin": Color(0.93, 0.76, 0.62), "top": Color(0.3, 0.55, 0.3), "accent": Color(0.85, 0.8, 0.6), "pants": Color(0.32, 0.35, 0.45), "shoes": Color(0.25, 0.2, 0.18), "gloves": Color(0.93, 0.76, 0.62), "hair": HAIR_SHORT, "hair_col": Color(0.35, 0.22, 0.12), "hat": "", "back": "backpack", "extra": "", "build": 1.0, "sleeves": "long"},
	{"name": "Ember Ace", "skin": Color(0.98, 0.82, 0.7), "top": Color(0.85, 0.2, 0.15), "accent": Color(1.0, 0.65, 0.15), "pants": Color(0.18, 0.18, 0.2), "shoes": Color(0.9, 0.9, 0.9), "gloves": Color(0.18, 0.18, 0.2), "hair": HAIR_SPIKY, "hair_col": Color(1.0, 0.5, 0.15), "hat": "", "back": "jetpack", "extra": "", "build": 1.0, "sleeves": "long"},
	{"name": "Frostline", "skin": Color(0.85, 0.67, 0.55), "top": Color(0.92, 0.95, 1.0), "accent": Color(0.4, 0.75, 1.0), "pants": Color(0.3, 0.45, 0.65), "shoes": Color(0.9, 0.95, 1.0), "gloves": Color(0.4, 0.75, 1.0), "hair": HAIR_NONE, "hair_col": Color.BLACK, "hat": "hood", "back": "cape", "extra": "scarf", "build": 1.05, "sleeves": "long"},
	{"name": "Neon Vandal", "skin": Color(0.62, 0.45, 0.35), "top": Color(0.1, 0.1, 0.12), "accent": Color(1.0, 0.2, 0.7), "pants": Color(0.12, 0.12, 0.15), "shoes": Color(1.0, 0.2, 0.7), "gloves": Color(0.1, 0.1, 0.12), "hair": HAIR_MOHAWK, "hair_col": Color(1.0, 0.25, 0.75), "hat": "", "back": "", "extra": "goggles", "build": 0.95, "sleeves": "short"},
	{"name": "Cactus Kid", "skin": Color(0.88, 0.68, 0.5), "top": Color(0.85, 0.72, 0.5), "accent": Color(0.6, 0.3, 0.2), "pants": Color(0.35, 0.42, 0.6), "shoes": Color(0.5, 0.3, 0.18), "gloves": Color(0.5, 0.3, 0.18), "hair": HAIR_SHORT, "hair_col": Color(0.2, 0.12, 0.08), "hat": "cowboy", "back": "", "extra": "bandana", "build": 1.0, "sleeves": "long"},
	{"name": "Tidecaller", "skin": Color(0.55, 0.38, 0.27), "top": Color(0.1, 0.65, 0.7), "accent": Color(1.0, 0.85, 0.3), "pants": Color(0.08, 0.4, 0.5), "shoes": Color(0.1, 0.12, 0.15), "gloves": Color(0.1, 0.12, 0.15), "hair": HAIR_LONG, "hair_col": Color(0.05, 0.05, 0.08), "hat": "", "back": "tanks", "extra": "goggles", "build": 0.95, "sleeves": "long"},
	{"name": "Brickhouse", "skin": Color(0.78, 0.55, 0.42), "top": Color(1.0, 0.55, 0.1), "accent": Color(0.95, 0.95, 0.3), "pants": Color(0.25, 0.32, 0.5), "shoes": Color(0.35, 0.22, 0.12), "gloves": Color(0.9, 0.8, 0.4), "hair": HAIR_NONE, "hair_col": Color.BLACK, "hat": "hardhat", "back": "", "extra": "beard", "build": 1.25, "sleeves": "short"},
	{"name": "Captain Comet", "skin": Color(0.95, 0.8, 0.68), "top": Color(0.95, 0.95, 0.97), "accent": Color(0.95, 0.3, 0.25), "pants": Color(0.95, 0.95, 0.97), "shoes": Color(0.4, 0.42, 0.48), "gloves": Color(0.4, 0.42, 0.48), "hair": HAIR_NONE, "hair_col": Color.BLACK, "hat": "space", "back": "tanks", "extra": "", "build": 1.1, "sleeves": "long"},
	{"name": "Moss Ranger", "skin": Color(0.8, 0.6, 0.45), "top": Color(0.35, 0.45, 0.25), "accent": Color(0.55, 0.42, 0.25), "pants": Color(0.4, 0.35, 0.25), "shoes": Color(0.25, 0.2, 0.15), "gloves": Color(0.3, 0.25, 0.18), "hair": HAIR_SHORT, "hair_col": Color(0.45, 0.28, 0.15), "hat": "beanie", "back": "quiver", "extra": "beard", "build": 1.1, "sleeves": "long"},
	{"name": "Sugar Rush", "skin": Color(0.98, 0.84, 0.75), "top": Color(1.0, 0.55, 0.75), "accent": Color(0.55, 0.9, 1.0), "pants": Color(0.95, 0.95, 1.0), "shoes": Color(1.0, 0.55, 0.75), "gloves": Color(0.98, 0.84, 0.75), "hair": HAIR_BUN, "hair_col": Color(0.6, 0.85, 1.0), "hat": "", "back": "lollipop", "extra": "", "build": 0.9, "sleeves": "short"},
	{"name": "Night Owl", "skin": Color(0.45, 0.32, 0.25), "top": Color(0.25, 0.15, 0.35), "accent": Color(0.75, 0.6, 1.0), "pants": Color(0.12, 0.1, 0.16), "shoes": Color(0.1, 0.08, 0.12), "gloves": Color(0.12, 0.1, 0.16), "hair": HAIR_NONE, "hair_col": Color.BLACK, "hat": "hood", "back": "cape", "extra": "mask", "build": 1.0, "sleeves": "long"},
	{"name": "Sunny Daze", "skin": Color(0.72, 0.5, 0.35), "top": Color(1.0, 0.85, 0.2), "accent": Color(0.2, 0.75, 0.55), "pants": Color(0.25, 0.6, 0.85), "shoes": Color(0.95, 0.95, 0.95), "gloves": Color(0.72, 0.5, 0.35), "hair": HAIR_CURLY, "hair_col": Color(0.12, 0.08, 0.05), "hat": "", "back": "surfboard", "extra": "", "build": 1.0, "sleeves": "short"},
	{"name": "Iron Gale", "skin": Color(0.9, 0.72, 0.6), "top": Color(0.65, 0.68, 0.72), "accent": Color(0.85, 0.2, 0.2), "pants": Color(0.45, 0.47, 0.5), "shoes": Color(0.35, 0.36, 0.4), "gloves": Color(0.65, 0.68, 0.72), "hair": HAIR_NONE, "hair_col": Color.BLACK, "hat": "knight", "back": "shield", "extra": "pauldrons", "build": 1.15, "sleeves": "long"},
	{"name": "Pixel Punk", "skin": Color(0.96, 0.8, 0.68), "top": Color(0.2, 0.22, 0.3), "accent": Color(0.2, 0.9, 0.85), "pants": Color(0.55, 0.2, 0.3), "shoes": Color(0.95, 0.95, 0.95), "gloves": Color(0.2, 0.9, 0.85), "hair": HAIR_LONG, "hair_col": Color(0.2, 0.85, 0.8), "hat": "", "back": "backpack", "extra": "", "build": 0.92, "sleeves": "long"},
	{"name": "Rust Bucket", "skin": Color(0.7, 0.45, 0.3), "top": Color(0.72, 0.42, 0.25), "accent": Color(0.3, 0.85, 1.0), "pants": Color(0.5, 0.35, 0.25), "shoes": Color(0.3, 0.3, 0.32), "gloves": Color(0.4, 0.4, 0.42), "hair": HAIR_NONE, "hair_col": Color.BLACK, "hat": "robot", "back": "jetpack", "extra": "pauldrons", "build": 1.15, "sleeves": "long"},
	{"name": "Marigold", "skin": Color(0.95, 0.78, 0.62), "top": Color(0.95, 0.4, 0.35), "accent": Color(0.3, 0.45, 0.75), "pants": Color(0.3, 0.45, 0.75), "shoes": Color(0.4, 0.28, 0.15), "gloves": Color(0.95, 0.78, 0.62), "hair": HAIR_PONY, "hair_col": Color(0.95, 0.75, 0.3), "hat": "straw", "back": "", "extra": "overalls", "build": 0.95, "sleeves": "short"},
	{"name": "Volt Runner", "skin": Color(0.5, 0.35, 0.25), "top": Color(1.0, 0.9, 0.1), "accent": Color(0.1, 0.1, 0.1), "pants": Color(0.1, 0.1, 0.1), "shoes": Color(1.0, 0.9, 0.1), "gloves": Color(0.1, 0.1, 0.1), "hair": HAIR_SPIKY, "hair_col": Color(0.08, 0.08, 0.08), "hat": "visor", "back": "", "extra": "", "build": 0.95, "sleeves": "long"},
	{"name": "Coral Queen", "skin": Color(0.68, 0.48, 0.36), "top": Color(1.0, 0.5, 0.45), "accent": Color(1.0, 0.85, 0.3), "pants": Color(0.95, 0.65, 0.55), "shoes": Color(1.0, 0.85, 0.3), "gloves": Color(0.68, 0.48, 0.36), "hair": HAIR_LONG, "hair_col": Color(0.45, 0.15, 0.1), "hat": "crown", "back": "cape", "extra": "", "build": 0.92, "sleeves": "short"},
	{"name": "Shadow Fox", "skin": Color(0.95, 0.8, 0.68), "top": Color(0.12, 0.12, 0.14), "accent": Color(1.0, 0.5, 0.15), "pants": Color(0.12, 0.12, 0.14), "shoes": Color(0.95, 0.95, 0.95), "gloves": Color(1.0, 0.5, 0.15), "hair": HAIR_NONE, "hair_col": Color.BLACK, "hat": "foxhood", "back": "tail", "extra": "mask", "build": 0.95, "sleeves": "long"},
	{"name": "Glacier Yeti", "skin": Color(0.6, 0.75, 0.9), "top": Color(0.95, 0.97, 1.0), "accent": Color(0.55, 0.75, 0.95), "pants": Color(0.95, 0.97, 1.0), "shoes": Color(0.55, 0.75, 0.95), "gloves": Color(0.95, 0.97, 1.0), "hair": HAIR_CURLY, "hair_col": Color(0.95, 0.97, 1.0), "hat": "", "back": "", "extra": "fur", "build": 1.3, "sleeves": "long"},
]


static func count() -> int:
	return LIST.size()


static func get_def(i: int) -> Dictionary:
	return LIST[posmod(i, LIST.size())]
