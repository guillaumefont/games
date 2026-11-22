extends RefCounted
## Graphics level (Guillaume 2026-11-22: premium low-poly look, levels the player can change, fitting most phones).
## Preload it (`const GFX := preload("res://scripts/gfx.gd")`); no class_name, so the self-update pack can carry it.
##
##   0 Classic  the old flat look, kept only to compare while the premium look is built (removed in the last phase)
##   1 Low      older and budget phones: rounded edges on larger parts, baked crease shadow, no sun shadows
##   2 Medium   typical mid-range phones: every part rounded, smooth cylinders, sun shadows
##   3 High     Pixel 11 Pro and recent flagships: soft sun shadows over a longer range, finer shadow map

const NAMES := ["Classic", "Low", "Medium", "High"]
const CLASSIC := 0
const LOW := 1
const MEDIUM := 2
const HIGH := 3

static var level := HIGH

static func premium() -> bool:
	return level > CLASSIC

## The level saved in prefs, or AF_GFX (0-3) for tests and screenshots, or a guess from the phone's memory.
static func init_level(prefs: Dictionary) -> void:
	var env := OS.get_environment("AF_GFX")
	if env != "": level = clampi(int(env), CLASSIC, HIGH)
	elif prefs.has("gfx"): level = clampi(int(prefs.gfx), CLASSIC, HIGH)
	else: level = auto_level()

static func auto_level() -> int:
	if not OS.has_feature("mobile"): return HIGH
	var mem: int = int(OS.get_memory_info().get("physical", -1))
	if mem <= 0: return MEDIUM
	var gb := mem / 1073741824.0
	if gb >= 11.0: return HIGH
	if gb >= 5.5: return MEDIUM
	return LOW

## Next level for the menu button: High, Medium, Low, Classic, then back to High.
static func next_level(l: int) -> int:
	return HIGH if l == CLASSIC else l - 1

# ---------------- model detail per level ----------------
## Edge rounding size (model units) and the smallest part that still gets rounded.
## A part's rounding grows with its thinnest side, so big blocks get a visible soft edge and small parts a fine one.
static func bevel(smin: float) -> float:
	return 0.0 if level == CLASSIC else clampf(smin * 0.14, 0.006, 0.05)

static func bevel_min() -> float:
	return 0.06 if level == LOW else 0.025

## Cylinders with at least this many sides get smooth (round) shading and, from Medium up, at least `round_seg` sides.
const SMOOTH_SEG := 8
static func round_seg() -> int:
	return 12 if level >= MEDIUM else 8

# ---------------- light ----------------
## Warm sun, cool shadows. `L` is the theme's light (sun, sunE, amb, ambE); Classic keeps it untouched.
static func light(sun: DirectionalLight3D, env: Environment, L: Dictionary) -> void:
	var sc := Color(L.sun); var ac := Color(L.amb)
	if level == CLASSIC:
		sun.light_color = sc; sun.light_energy = L.sunE
		env.ambient_light_color = ac; env.ambient_light_energy = L.ambE
		sun.shadow_enabled = true; sun.shadow_blur = 1.4
		RenderingServer.directional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_LOW)
		return
	sun.light_color = sc.lerp(Color("ffdcae"), 0.45)
	sun.light_energy = L.sunE * 1.12
	env.ambient_light_color = ac.lerp(Color("8fa7c8"), 0.4)
	env.ambient_light_energy = L.ambE * 0.95
	sun.shadow_enabled = level >= MEDIUM
	sun.shadow_blur = 2.0 if level == HIGH else 1.4
	RenderingServer.directional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM if level == HIGH else RenderingServer.SHADOW_QUALITY_SOFT_LOW)
	RenderingServer.directional_shadow_atlas_set_size(4096 if level == HIGH else 2048, true)

## How far sun shadows reach, as a multiple of the camera distance.
static func shadow_reach() -> float:
	return 3.2 if level == HIGH else 2.6
