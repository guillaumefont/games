extends RefCounted
## In-campaign tutorial text and rules: unit cards, enemy cards, pointer lessons and drills, mission by mission.
## All tutorial words live here (ready for translation later). Approved by Guillaume on 2026-11-20
## ("Aurite Front: unit tutorial script"). Campaign I only for now; II and III follow in their own PR.
##
## Limits checked by tests/sim_test.gd tutorial_tests(): job and tip at most 60 characters, a speaker line at most 64,
## a lesson hint at most 60.

## Unit and lesson cards. A key is the unit or building type it explains, or "l_<name>" for a lesson card.
##   job, tip, who (Data.SPEAKERS), say: the card's words. gw: replaces the computed good/weak line (no weapon, special).
##   home: [campaign, mission index] where the card belongs. Before that mission it shows only when the player trains or
##   builds the thing; from that mission on it shows as soon as the player has one.
const CARDS := {
	# ---- campaign I, mission 1: Smoke on the River
	"vey": {"job": "Hero with an arc rifle. If she falls, you lose.", "tip": "Keep a Medic close to her",
		"who": "foreman", "say": "That's Vey. Keep her breathing or we all go home.", "home": ["ashen", 0]},
	"rifle": {"job": "Cheap all-round infantry. Fires at aircraft too.", "tip": "Double-tap one to select them all",
		"who": "vey", "say": "Riflemen. Cheap, cheerful, and they shoot at the sky.", "home": ["ashen", 0]},
	"pyro": {"job": "Short-range flamer. Clears infantry fast.", "tip": "Get close: its reach is barely two tiles",
		"who": "foreman", "say": "Pyros! Point them at soldiers, not at tanks.", "home": ["ashen", 0]},
	"medic": {"job": "Heals nearby infantry. Carries no weapon.", "tip": "Keep it just behind the front line", "gw": "Heals infantry only, not vehicles",
		"who": "vey", "say": "Doc stays behind me. Nobody bleeds out on my hill.", "home": ["ashen", 0]},
	# ---- mission 2: Kettleford
	"lancer": {"job": "Rocket trooper. Cracks tanks, swats aircraft.", "tip": "Mix with Riflemen so infantry can't rush them",
		"who": "foreman", "say": "Lancers! Rockets for tanks. Keep them off rifles.", "home": ["ashen", 1]},
	"raider": {"job": "Fast gun bike. Hits and runs.", "tip": "Strike, then pull back before tanks arrive",
		"who": "brann", "say": "Fastest thing on wheels. Don't park it by a tank.", "home": ["ashen", 1]},
	"turret": {"job": "Cannon turret. Guards the base from vehicles.", "tip": "Put it where enemies come in, behind Barriers",
		"who": "foreman", "say": "Sentry's up! Loves tanks. Infantry, not so much.", "home": ["ashen", 1]},
	"wall": {"name": "Barrier", "job": "Four wall pieces per purchase. Blocks and funnels.", "tip": "Tap the map four times to lay all four", "gw": "No weapon",
		"who": "vey", "say": "Walls don't win fights. They pick where fights happen.", "home": ["ashen", 1]},
	# ---- mission 3: Dust and Ore
	"refinery": {"job": "Turns aurite into money. Comes with a Harvester.", "tip": "Build it close to an ore field", "gw": "No weapon",
		"who": "brann", "say": "Short trips, fat profits. Build it by the ore.", "home": ["ashen", 1]},
	"harv": {"job": "Mines aurite and hauls it home. No gun.", "tip": "Tap aurite to send it mining", "gw": "No weapon, heavy armour",
		"who": "brann", "say": "My harvesters. Scratch the paint, I scratch you.", "home": ["ashen", 1]},
	"factory": {"job": "Builds vehicles. Needs a Refinery.", "tip": "Select it and tap the map to set a rally", "gw": "No weapon",
		"who": "brann", "say": "The factory's warm. Let's make something heavy.", "home": ["ashen", 2]},
	"scorpion": {"job": "Pact battle tank. Quick for its weight.", "tip": "Send infantry with it to handle rifles",
		"who": "vey", "say": "Scorpions bite tanks. Bring rifles for the infantry.", "home": ["ashen", 2]},
	# ---- mission 4: Refugee Road
	"truck": {"job": "Carries the families. No gun. Two must arrive.", "tip": "Clear the road first, then move the trucks", "gw": "No weapon, heavy armour",
		"who": "vey", "say": "Every truck is forty people. Guard it like it's me.", "home": ["ashen", 3]},
	"l_groups": {"name": "Army groups", "job": "Store a squad on 1 to 4, call it back with a tap.", "tip": "Hold a number to store, tap it to select", "gw": "",
		"who": "foreman", "say": "Squad one, squad two! Hold the button to name them.", "home": ["ashen", 3], "glyph": "all"},
	# ---- mission 5: Ironpine Pass
	"flak": {"job": "Anti-air guns. Shreds aircraft, ignores the ground.", "tip": "Build two so they cover each other", "gw": "Hits aircraft only",
		"who": "foreman", "say": "Flak Nest! Gunships hate it. Tanks don't care.", "home": ["ashen", 4]},
	"arty": {"job": "Long-range mortar. Lobs shells over hills.", "tip": "Keep it behind the wall, out of reach",
		"gw": "Good: buildings, splash · Cannot fire up close or at aircraft",
		"who": "brann", "say": "The Howler. Lobs a shell over any hill you like.", "home": ["ashen", 4]},
	"repair": {"job": "Fixes vehicles parked beside it, for aurite.", "tip": "Select hurt tanks, then tap the Bay", "gw": "No weapon",
		"who": "brann", "say": "Bring them back dented. I send them out shiny.", "home": ["ashen", 4]},
	"l_upgrades": {"name": "Upgrades", "job": "Select a building, tap UPGRADE. It keeps working.", "tip": "A Heavy Sentry hits harder and reaches further", "gw": "",
		"who": "brann", "say": "Same Sentry, two barrels. Pay me and watch.", "home": ["ashen", 4], "glyph": "up"},
	# ---- mission 6: Silent Wires
	"engineer": {"job": "Captures enemy buildings, fully fixes yours.", "tip": "Select it, then tap the building", "gw": "No weapon · Used up when it does the job",
		"who": "vey", "say": "Engineers walk in, the building's ours. Cover them.", "home": ["ashen", 5]},
	"furnace": {"job": "Brann's hero tank. Arc cannon, huge armour.", "tip": "Lead with it: it soaks what others can't",
		"who": "brann", "say": "Slow to start, slower to stop. Just point her.", "home": ["ashen", 5]},
	"comms": {"job": "Radar mast. Sees far, unlocks advanced tech.", "tip": "Unlocks Pyros, the Helipad, the top upgrades", "gw": "No weapon",
		"who": "foreman", "say": "Our own mast! Now we hear everything too.", "home": ["ashen", 5]},
	# ---- mission 7: The Iron Saint
	"helipad": {"job": "Builds aircraft. Needs a Comms Array.", "tip": "Set its rally away from enemy flak", "gw": "No weapon",
		"who": "brann", "say": "A pad for the drones. Mind your heads.", "home": ["ashen", 6]},
	"wasp": {"job": "Fast gun drone. Scouts and hunts infantry.", "tip": "Send it ahead to look before the army moves",
		"who": "foreman", "say": "Wasps! Fast, nosy, and they bite infantry.", "home": ["ashen", 6]},
	"tech": {"job": "Unlocks the Pact's best weapons.", "tip": "Build a Reactor first", "gw": "No weapon · Uses 60 power",
		"who": "brann", "say": "My Tech Lab. Don't touch anything that glows.", "home": ["ashen", 6]},
	"arcc": {"job": "Heavy arc tank. Strong against almost all.", "tip": "Slow: escort it with Lancers",
		"who": "vey", "say": "Lightning on tracks. Point them at the Saint.", "home": ["ashen", 6]},
	"pylon": {"job": "Arc tower. Deadly, but dark without power.", "tip": "Keep spare power or it shuts off",
		"who": "brann", "say": "Pylons drink power. Low power, no lightning.", "home": ["ashen", 6]},
	# ---- mission 8: Embers
	"rift": {"job": "Superweapon. Charges 4 minutes, tears a hole.", "tip": "Select it, tap LAUNCH, then tap the target", "gw": "Hits everything in a wide circle",
		"who": "foreman", "say": "Rift's charged! Pick something big, boss.", "home": ["ashen", 7]},
}

## Enemy cards ("Know your enemy"): shown once, the first time that enemy type is in sight. They do not pause.
## Keyed by campaign, then type.
const ENEMY := {
	"ashen": {
		"rifle": {"name": "Vanguard Rifleman", "text": "Same rifle as ours, blue coat. Pyros eat them.", "who": "foreman", "say": "Blue coats on the hill! Same rifles, worse manners."},
		"buggy": {"text": "Quick gun buggy. Lancers and Sentries stop it.", "who": "foreman", "say": "Buggies! Quick little things. Lancers, boss!"},
		"tank": {"text": "Main battle tank. Bullets bounce off. Use Lancers.", "who": "foreman", "say": "Tank! Rifles, back off. Lancers, forward!"},
		"skyhawk": {"text": "Flies over walls. Flak, rockets and rifles reach it.", "who": "foreman", "say": "Gunships! Cannons can't touch them. Flak!"},
		"bulwark": {"text": "Heavy tank. Slow, huge, armoured like a vault.", "who": "foreman", "say": "A Bulwark! Lancers, in a crowd, boss!"},
		"ranger": {"text": "Vanguard sniper. Deadly to infantry, harmless to tanks.", "who": "vey", "say": "Sniper in the reeds! Send a bike, not a rifle."},
		"saint": {"text": "Dace's command tank. Huge armour, huge gun.", "who": "brann", "say": "That's the Saint. Lancers and Crawlers, all at once."},
		"harrow": {"text": "Vanguard hero sniper. Longest reach on the field.", "who": "vey", "say": "Harrow's on the cliffs. Send bikes, not rifles."},
		"bastion": {"text": "Heavy gun tower. Outranges your tanks.", "who": "foreman", "say": "Bastion! Howlers outrange it, boss."},
		"skyfall": {"text": "Missile battery. Charges, then hits anywhere.", "who": "foreman", "say": "Watch the Skyfall timer. When it's low, scatter!"},
	},
}

## Pointer lessons: steps shown one at a time, each waiting for the one before. A step:
##   hint (the banner by the pointer), say (a radio line, by the lesson's speaker), ptr (what the pointer rings),
##   done (what finishes it), when (optional: wait for this before showing the step), skip_if (a building type:
##   the step is skipped when the player already has one).
## ptr: {"hero"} own hero · {"unit": type} first own unit of a type · {"enemy"} nearest enemy in sight · {"ahead"} a spot
##   up the map from the hero · {"view"} the middle of the map view · {"ui": name} a HUD control (power, ready, place, sw) ·
##   {"item": "cat:type"} a build button (or its tab, or the panel button while hidden) · {"bld": type} own building.
## done: {"ev": name, ...} an event (see Tutor.ev) · {"t": seconds} after a while.
const LESSONS := {
	"controls": {"who": "foreman", "steps": [
		{"hint": "Tap Vey to select her", "say": "Tap the lady with the goggles, boss.", "ptr": {"hero": true}, "done": {"ev": "select", "hero": true}},
		{"hint": "Tap the ground to move", "say": "Now tap where you want her. Simple!", "ptr": {"ahead": true}, "done": {"ev": "move"}},
		{"hint": "Hold, then drag over the squad to select it", "say": "Hold your finger, then drag. Grab the lot!", "ptr": {"unit": "rifle"}, "done": {"ev": "box"}},
		{"hint": "Tap an enemy to attack", "say": "That's a Vanguard picket. Tap it. Hard.", "ptr": {"enemy": true}, "done": {"ev": "attack"}, "when": "enemy_seen"},
		{"hint": "Double-tap a unit to pick every one of its type", "say": "Double-tap a rifle, get all the rifles.", "ptr": {"unit": "rifle"}, "done": {"ev": "dbl"}},
		{"hint": "Drag to look around, pinch to zoom", "say": "Drag the map to look about. Pinch for close-ups.", "ptr": {"view": true}, "done": {"ev": "cam"}},
	]},
	"base": {"who": "foreman", "steps": [
		{"hint": "Every building needs power. Reactors make it", "say": "See the power bar? Keep it green, boss.", "ptr": {"ui": "power"}, "done": {"t": 7.0}},
		{"hint": "Tap a building to start it", "say": "Tap the War Factory. Brann's lads do the rest.", "ptr": {"item": "bld:factory"}, "done": {"ev": "order", "type": "factory"}, "skip_if": "factory"},
		{"hint": "When it is ready, drag it onto the map", "say": "It's ready! Drag it out where you want it.", "ptr": {"item": "bld:factory"}, "done": {"ev": "placing"}, "when": "bld_ready", "skip_if": "factory"},
		{"hint": "Tap it to build there", "say": "Tap it again to drop it. Bang. Factory.", "ptr": {"ui": "place"}, "done": {"ev": "made", "type": "factory"}, "skip_if": "factory"},
		{"hint": "Select the Barracks, tap the map: rally point", "say": "Pick the Barracks, tap the map. Recruits go there.", "ptr": {"bld": "barracks"}, "done": {"ev": "rally"}},
		{"hint": "Hold a unit button to queue five", "say": "Hold the button to order five at once!", "ptr": {"item": "inf:rifle"}, "done": {"ev": "queue5"}},
	]},
	"launch": {"who": "foreman", "steps": [
		{"hint": "Tap LAUNCH", "say": "", "ptr": {"ui": "sw"}, "done": {"ev": "aim"}, "when": "sw_ready"},
		{"hint": "Tap the target", "say": "", "ptr": {"view": true}, "done": {"ev": "launch"}},
	]},
}

## Per mission: the pointer lesson, lesson cards that open with the mission, and the optional drills.
## Drill: text, check (see Tutor._drill_check), ptr (a unit type pulsed for a few seconds when the drill appears).
## Done drills give +200 aurite in missions with a base (DRILL_BONUS), a tick only in the others.
## Basics the "base" lesson teaches instead of a card (the tests skip them).
const LESSON_ONLY := ["hq", "power", "barracks"]
const DRILL_BONUS := 200
const MISSIONS := {
	"ashen": [
		{"lesson": "controls", "drills": [
			{"text": "Burn a picket with your Pyros", "check": {"ev": "kill", "by": "pyro"}, "ptr": "pyro"},
			{"text": "Let the Medic patch up Vey", "check": {"ev": "heal", "target": "vey"}, "ptr": "medic"}]},
		{"lesson": "base", "drills": [
			{"text": "Train two Lancers", "check": {"ev": "made", "type": "lancer", "n": 2}},
			{"text": "Set a rally point", "check": {"ev": "rally"}}]},
		{"drills": [
			{"text": "Build a second Harvester", "check": {"have": "harv", "n": 2}},
			{"text": "Wipe out a buggy raid", "check": {"raid": true}}]},
		{"cards": ["l_groups"], "drills": [
			{"text": "Put your army in group 1 and call it back", "check": {"ev": "group_recall", "i": 0}},
			{"text": "Bring all three trucks home", "check": {"arrived": 3}}]},
		{"cards": ["l_upgrades"], "drills": [
			{"text": "Shell a column with a Howler", "check": {"ev": "kill", "by": "arty"}},
			{"text": "Shoot down a gunship", "check": {"ev": "kill", "by": "flak", "air": true}},
			{"text": "Upgrade a Sentry Gun", "check": {"ev": "upgrade", "type": "turret"}}]},
		{"drills": [
			{"text": "Fix a damaged building with an Engineer", "check": {"ev": "eng_fix"}, "ptr": "engineer"}]},
		{"drills": [
			{"text": "Find the Iron Saint with a Wasp", "check": {"spot": "saint", "by": "wasp"}},
			{"text": "Build an Arc Pylon", "check": {"ev": "made", "type": "pylon"}}]},
		{"lesson": "launch", "drills": [
			{"text": "Fire the Rift Engine", "check": {"ev": "launch"}}]},
	],
}

## Interface words.
const TXT := {
	"mode": {"full": "Full", "cards": "Cards only", "off": "Off"},
	"setting": "Tutorial",
	"reset": "Reset tutorial",
	"reset_arm": "Tap again to reset",
	"reset_done": "Tutorial reset: every card and drill will show again",
	"brief_on": "Tutorial tips: on",
	"brief_off": "Tutorial tips: off",
	"got_it": "Got it",
	"good": "Good against",
	"weak": "Weak against",
	"unarmed": "Unarmed",
	"enemy": "Know your enemy",
	"drill": "Drill (optional)",
	"drill_done": "Drill done · +%d aurite",
	"drill_done_nb": "Drill done",
	"skip": "Skip lesson",
	"manual": "Field manual",
	"tabs": ["Yours", "Enemy", "Lessons"],
	"locked": "Not met yet",
	"new_unit": "New unit",
	"new_bld": "New building",
	"lesson": "Field lesson",
	"none": "none",
	"hits_air": "Hits aircraft",
	"no_air": "Cannot hit aircraft",
	"no_close": "Cannot fire up close",
}

# ---------------- card words (computed) ----------------
static func card_name(key: String) -> String:
	var c: Dictionary = CARDS[key]
	if c.has("name"): return c.name
	return D.def_of(key).name.replace(" ×4", "")

## Good / weak lines of a unit or building from the damage table (D.MOD), or the card's own words ("gw").
## Returns [good, weak, extra]; empty strings are left out.
static func good_weak(key: String) -> Array:
	var c: Dictionary = CARDS.get(key, {})
	if c.has("gw"): return ["", "", c.gw]
	return gw_of(key)

static func gw_of(type: String) -> Array:
	if not D.UN.has(type) and not D.BLD.has(type): return ["", "", ""]
	var d: Dictionary = D.def_of(type)
	var w: String = d.weapon
	if w == "" or not D.MOD.has(w): return ["", "", TXT.unarmed]
	var names := {"inf": "infantry", "light": "light vehicles", "heavy": "tanks", "bld": "buildings"}
	var good: Array = []; var weak: Array = []
	for k in ["inf", "light", "heavy", "bld"]:
		if D.MOD[w][k] >= 1.0: good.append(names[k])
		elif D.MOD[w][k] <= 0.45: weak.append(names[k])
	var extra: Array = []
	if d.minr > 0: extra.append(TXT.no_close)
	extra.append(TXT.hits_air if D.AIRW.has(w) else TXT.no_air)
	return [", ".join(good), ", ".join(weak), " · ".join(extra)]

static func card_kind(key: String) -> String:
	if key.begins_with("l_"): return "lesson"
	return "u" if D.UN.has(key) else "b"

