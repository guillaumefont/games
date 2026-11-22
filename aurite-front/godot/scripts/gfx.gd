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
## Per theme: how far the sun is pushed warm and the shadows cool, the ambient energy, an ambient tint, and the
## ground brightness (scripts/ground.gd). Ash keeps its dark, smoky mood; snow gets the coolest shadows.
const MOOD := {
	"temperate": {"warm": 0.45, "cool": 0.4, "amb": 0.95, "tint": Color("8fa7c8"), "ground": 0.8},
	"autumn": {"warm": 0.5, "cool": 0.3, "amb": 0.95, "tint": Color("9aa4c0"), "ground": 0.8},
	"arid": {"warm": 0.35, "cool": 0.25, "amb": 0.92, "tint": Color("a7b0c8"), "ground": 0.68},
	"snow": {"warm": 0.2, "cool": 0.5, "amb": 0.9, "tint": Color("8ea6d0"), "ground": 0.76},
	"ash": {"warm": 0.1, "cool": 0.12, "amb": 0.85, "tint": Color("9c8a86"), "ground": 0.6},
	"marsh": {"warm": 0.25, "cool": 0.45, "amb": 0.95, "tint": Color("8faea8"), "ground": 0.76},
}
## Chapter grading (Guillaume's tone: pulpy at first, grim once the Choir appears): campaign I (Ashen Pact) is warm
## and punchy, II (Vanguard) neutral, III (Hollow Choir) cold, flat and dim. Skirmish is neutral.
const GRADE := {
	"pulp": {"sat": 1.12, "con": 1.06, "sun": 1.0, "tint": Color(1, 1, 1), "tint_k": 0.0},
	"neutral": {"sat": 1.04, "con": 1.05, "sun": 1.0, "tint": Color(1, 1, 1), "tint_k": 0.0},
	"grim": {"sat": 0.8, "con": 1.1, "sun": 0.9, "tint": Color("7f9688"), "tint_k": 0.22},
}

static func mood_of(fac) -> String:
	return {"ashen": "pulp", "choir": "grim"}.get(fac, "neutral") if fac != null else "neutral"

## Warm sun, cool shadows. `L` is the theme's light (sun, sunE, amb, ambE); Classic keeps it untouched.
static func light(sun: DirectionalLight3D, env: Environment, L: Dictionary, theme := "temperate", grade := "neutral") -> void:
	var sc := Color(L.sun); var ac := Color(L.amb)
	if level == CLASSIC:
		sun.light_color = sc; sun.light_energy = L.sunE
		env.ambient_light_color = ac; env.ambient_light_energy = L.ambE
		sun.shadow_enabled = true; sun.shadow_blur = 1.4
		RenderingServer.directional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_LOW)
		if RenderingServer.get_current_rendering_method() != "gl_compatibility":
			env.adjustment_saturation = 1.05; env.adjustment_contrast = 1.07   # View3D._ready's classic grading
		return
	var M: Dictionary = MOOD.get(theme, MOOD.temperate); var G: Dictionary = GRADE.get(grade, GRADE.neutral)
	sun.light_color = sc.lerp(Color("ffdcae"), M.warm).lerp(G.tint, G.tint_k * 0.5)
	sun.light_energy = L.sunE * 1.12 * G.sun
	env.ambient_light_color = ac.lerp(M.tint, M.cool).lerp(G.tint, G.tint_k)
	env.ambient_light_energy = L.ambE * M.amb
	if RenderingServer.get_current_rendering_method() != "gl_compatibility":
		env.adjustment_enabled = true; env.adjustment_saturation = G.sat; env.adjustment_contrast = G.con
	sun.shadow_enabled = level >= MEDIUM
	sun.shadow_blur = 2.0 if level == HIGH else 1.4
	RenderingServer.directional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM if level == HIGH else RenderingServer.SHADOW_QUALITY_SOFT_LOW)
	RenderingServer.directional_shadow_atlas_set_size(4096 if level == HIGH else 2048, true)

## How far sun shadows reach, as a multiple of the camera distance.
static func shadow_reach() -> float:
	return 3.2 if level == HIGH else 2.6
