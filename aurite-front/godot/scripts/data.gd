extends Node
## Static game data: buildings, units, damage table, factions, missions.
## Autoloaded as `D`. Every def is normalised so optional keys always exist.

const T := 32
const MW := 64
const MH := 64
const WW := MW * T
const WH := MH * T
const GRASS := 0
const DIRT := 1
const SAND := 2
const ROCK := 3
const WATER := 4
const HARV_CAP := 700
const P0 := Vector2i(9, 53)
const ALT := 1.6

var BLD := {
	"hq": {"name": "Command Yard", "w": 3, "h": 3, "hp": 1600, "cost": 0, "time": 1, "pwr": 20, "sight": 7, "req": [], "capAdd": 20, "signal": 10.0, "hum": 6.0},
	"power": {"name": "Reactor", "no": ["ashen", "vanguard", "choir"], "w": 2, "h": 2, "hp": 600, "cost": 300, "time": 7, "pwr": 100, "sight": 4, "req": ["hq"]},
	"refinery": {"name": "Refinery", "no": ["choir", "ashen", "vanguard"], "dock": true, "w": 3, "h": 3, "hp": 1000, "cost": 1400, "time": 13, "pwr": -30, "sight": 5, "req": ["power"]},
	# Hollow Choir: no refinery or harvesters. A Garden sings the field beside it into growing and is paid for it.
	"garden": {"name": "Garden", "fac": "choir", "w": 2, "h": 2, "hp": 850, "cost": 1000, "time": 11, "pwr": 0, "sight": 5, "req": ["hq"], "grow": true, "drain": -8.0, "hum": 5.0, "rate": 15.0, "field": true},
	"barracks": {"name": "Barracks", "no": ["ashen", "choir"], "door": true, "w": 2, "h": 2, "hp": 700, "cost": 400, "time": 8, "pwr": -20, "sight": 5, "req": ["power"]},
	"factory": {"name": "War Factory", "no": ["ashen", "vanguard", "choir"], "door": true, "w": 3, "h": 3, "hp": 1100, "cost": 1600, "time": 15, "pwr": -30, "sight": 5, "req": ["refinery"]},
	"turret": {"name": "Sentry Gun", "no": ["ashen", "vanguard", "choir"], "w": 1, "h": 1, "hp": 500, "cost": 500, "time": 8, "pwr": -15, "sight": 7, "req": ["barracks"], "weapon": "shell", "dmg": 30, "range": 6.0, "rof": 1.3},
	"repair": {"name": "Repair Bay", "no": ["ashen", "vanguard", "choir"], "w": 3, "h": 3, "hp": 900, "cost": 900, "time": 11, "pwr": -25, "sight": 4, "req": ["factory"]},
	"burrow": {"name": "Burrow", "fac": "choir", "w": 2, "h": 2, "hp": 450, "cost": 450, "time": 6, "pwr": 0, "sight": 6, "req": ["garden"], "tun": true},
	"wall": {"name": "Barrier ×4", "no": ["choir"], "w": 1, "h": 1, "hp": 450, "cost": 160, "time": 4, "pwr": 0, "sight": 1, "req": ["barracks"], "kit": 4},
	"flak": {"name": "Flak Nest", "no": ["vanguard", "choir"], "w": 1, "h": 1, "hp": 450, "cost": 600, "time": 8, "pwr": -20, "sight": 8, "req": ["barracks"], "weapon": "flak", "dmg": 24, "range": 7.5, "rof": 0.55, "antiAir": true},
	"comms": {"name": "Comms Array", "no": ["ashen", "vanguard", "choir"], "w": 2, "h": 2, "hp": 700, "cost": 1000, "time": 10, "pwr": -40, "sight": 10, "req": ["refinery"]},
	"helipad": {"name": "Helipad", "no": ["ashen", "vanguard", "choir"], "w": 2, "h": 2, "hp": 650, "cost": 1100, "time": 11, "pwr": -20, "sight": 5, "req": ["comms"]},
	"tech": {"name": "Tech Lab", "no": ["ashen", "vanguard", "choir"], "w": 2, "h": 2, "hp": 800, "cost": 1500, "time": 14, "pwr": -60, "sight": 5, "req": ["factory", "comms"]},
	"bastion": {"name": "Bastion Rail Cannon", "fac": "vanguard", "w": 2, "h": 2, "hp": 1250, "cost": 1400, "time": 8, "pwr": -50, "sight": 9, "req": ["tech"], "weapon": "shell", "dmg": 80, "range": 9.0, "rof": 2.4, "sh": 300},
	"pylon": {"name": "Arc Pylon", "fac": "ashen", "w": 1, "h": 1, "hp": 700, "cost": 1200, "time": 12, "pwr": -75, "sight": 7, "req": ["works"], "weapon": "arc", "dmg": 62, "range": 5.5, "rof": 1.9, "needPower": true},
	"spire": {"name": "Shard Spire", "fac": "choir", "w": 1, "h": 1, "hp": 650, "cost": 900, "time": 10, "pwr": 0, "sight": 7, "req": ["garden"], "weapon": "shard", "dmg": 24, "range": 6.5, "rof": 0.5},
	# Hollow Choir (alien mutant): no Yard work, no power, nothing is built. Gardens sing a field into growing, give off the
	# Hum (the only ground the Choir can sprout on, where its forms heal and hurry) and ripen the Pods every form hatches from.
	# A Garden ages: Sprout, Bloom, Cathedral ("bloom" and "cathedral" below are not buildings, only what an aged Garden counts as).
	"thorn": {"name": "Thornglass ×4", "fac": "choir", "w": 1, "h": 1, "hp": 350, "cost": 100, "time": 4, "pwr": 0, "sight": 1, "req": ["garden"], "kit": 4, "thorn": 4.0},
	"bloom": {"name": "Bloom Garden", "fac": "choir", "w": 2, "h": 2, "hp": 1, "cost": 0, "time": 1, "pwr": 0, "sight": 1, "req": ["never"], "retired": true},
	"cathedral": {"name": "Cathedral Garden", "fac": "choir", "w": 2, "h": 2, "hp": 1, "cost": 0, "time": 1, "pwr": 0, "sight": 1, "req": ["never"], "retired": true},
	"skyfall": {"name": "Skyfall Battery", "fac": "vanguard", "w": 3, "h": 3, "hp": 1500, "cost": 3000, "time": 25, "pwr": -100, "sight": 5, "req": ["tech"], "sw": true, "charge": 240.0},
	"rift": {"name": "Rift Engine", "fac": "ashen", "w": 3, "h": 3, "hp": 1500, "cost": 3000, "time": 25, "pwr": -100, "sight": 5, "req": ["works"], "sw": true, "charge": 240.0},
	# Ashen Pact (raw power): Kilns burn aurite for power, Hearths raise the unit cap and sound the Muster once a match,
	# Muster Hall trains infantry and beasts, Workshop builds vehicles, Mooring Mast aircraft. No Repair Bay: Scrappers weld.
	"kiln": {"name": "Furnace", "fac": "ashen", "w": 2, "h": 2, "hp": 650, "cost": 300, "time": 7, "pwr": 100, "sight": 4, "req": ["hq"], "burn": 0.5},
	"hearth": {"name": "Hearth", "fac": "ashen", "w": 2, "h": 2, "hp": 500, "cost": 250, "time": 6, "pwr": 0, "sight": 4, "req": ["hq"], "capAdd": 10, "muster": 3},
	"smelter": {"name": "Smelter", "fac": "ashen", "dock": true, "w": 3, "h": 3, "hp": 1100, "cost": 1400, "time": 13, "pwr": -30, "sight": 5, "req": ["kiln"]},
	"muster": {"name": "Muster Hall", "fac": "ashen", "door": true, "w": 2, "h": 2, "hp": 800, "cost": 400, "time": 8, "pwr": -20, "sight": 5, "req": ["kiln"]},
	"workshop": {"name": "Workshop", "fac": "ashen", "door": true, "w": 3, "h": 3, "hp": 1300, "cost": 1600, "time": 15, "pwr": -30, "sight": 5, "req": ["smelter"]},
	"works": {"name": "Old Works", "fac": "ashen", "w": 2, "h": 2, "hp": 900, "cost": 1500, "time": 14, "pwr": -60, "sight": 5, "req": ["workshop"]},
	"mast": {"name": "Mooring Mast", "fac": "ashen", "w": 2, "h": 2, "hp": 700, "cost": 1200, "time": 12, "pwr": -20, "sight": 6, "req": ["workshop"]},
	"slipway": {"name": "Slipway", "fac": "ashen", "w": 2, "h": 2, "hp": 900, "cost": 1000, "time": 11, "pwr": -20, "sight": 6, "req": ["workshop"], "shore": true, "yard": true},
	"hammer": {"name": "Hammer Gun", "fac": "ashen", "w": 1, "h": 1, "hp": 700, "cost": 600, "time": 8, "pwr": -15, "sight": 6, "req": ["muster"], "weapon": "shell", "dmg": 60, "range": 5.0, "rof": 2.0},
	# Vanguard (high tech): no power. Buildings are prefabs dropped inside Signal (the Yard and Signal Masts send it; outside it
	# they go dark). Masts also raise Command (the unit cap). A Deep Drill pumps a field dry for good. Vehicles and aircraft
	# are flown in to a Landing Zone by dropship. Aegis shields ("sh") soak damage first and come back when left alone.
	"sigmast": {"name": "Signal Mast", "fac": "vanguard", "w": 1, "h": 1, "hp": 450, "cost": 400, "time": 8, "pwr": 0, "sight": 7, "req": ["hq"], "capAdd": 10, "signal": 8.0},
	"drill": {"name": "Deep Drill", "fac": "vanguard", "w": 2, "h": 2, "hp": 900, "cost": 1500, "time": 8, "pwr": 0, "sight": 5, "req": ["hq"], "pump": 50, "onore": true},
	"lz": {"name": "Landing Zone", "fac": "vanguard", "w": 3, "h": 3, "hp": 900, "cost": 800, "time": 8, "pwr": 0, "sight": 6, "req": ["barracks"], "pad": true},
	"uplink": {"name": "Uplink", "fac": "vanguard", "w": 2, "h": 2, "hp": 800, "cost": 1500, "time": 8, "pwr": 0, "sight": 10, "req": ["lz"]},
	"sentry": {"name": "Auto-Sentry", "fac": "vanguard", "w": 1, "h": 1, "hp": 450, "cost": 550, "time": 8, "pwr": 0, "sight": 7, "req": ["barracks"], "weapon": "bullet", "dmg": 28, "range": 5.5, "rof": 1.0, "sh": 150},
	"pdl": {"name": "Point Laser", "fac": "vanguard", "w": 1, "h": 1, "hp": 400, "cost": 650, "time": 8, "pwr": 0, "sight": 8, "req": ["barracks"], "weapon": "laser", "dmg": 16, "range": 7.5, "rof": 0.35, "antiAir": true, "sh": 150},
	"dome": {"name": "Shield Dome", "fac": "vanguard", "w": 2, "h": 2, "hp": 700, "cost": 1200, "time": 8, "pwr": 0, "sight": 5, "req": ["uplink"], "dome": 5.0, "sh": 800},
	"chorus": {"name": "Chorus Well", "fac": "choir", "w": 3, "h": 3, "hp": 1500, "cost": 3000, "time": 25, "pwr": -100, "sight": 5, "req": ["cathedral"], "sw": true, "charge": 240.0},
}

## In-place upgrades: select one of your buildings and press UPGRADE. It keeps working while the upgrade is paid and built,
## then swaps to its upgraded def (BLD2): the keys here replace the base ones. "cost" and "time" are the upgrade's own.
## yield: aurite multiplier (refinery deliveries, garden harvests). speed: training speed of that producer's queue.
var UPG := {
	"power": {"name": "Super Reactor", "cost": 450, "time": 12, "req": ["refinery"], "hp": 1000, "pwr": 250, "say": "+150 power"},
	"refinery": {"name": "Deep Refinery", "cost": 1000, "time": 15, "req": ["comms"], "hp": 1400, "yield": 1.25, "say": "+25% aurite per load"},
	"garden": {"name": "Bloom Garden", "cost": 900, "time": 60, "req": ["garden"], "hp": 1150, "hum": 7.0, "rate": 20.0, "say": "wider Hum, more aurite, new forms"},
	"barracks": {"name": "Drill Hall", "cost": 600, "time": 10, "req": ["factory"], "hp": 950, "speed": 1.35, "say": "infantry trains 35% faster"},
	"factory": {"name": "Heavy Works", "cost": 1200, "time": 16, "req": ["comms"], "hp": 1500, "speed": 1.3, "pwr": -40, "say": "vehicles build 30% faster"},
	"turret": {"name": "Heavy Sentry", "cost": 400, "time": 8, "req": ["factory"], "hp": 750, "dmg": 44, "range": 6.5, "say": "harder hitting, longer reach"},
	"kiln": {"name": "Roaring Furnace", "cost": 450, "time": 12, "req": ["smelter"], "hp": 1000, "pwr": 250, "say": "+150 power"},
	"smelter": {"name": "Deep Smelter", "cost": 1000, "time": 15, "req": ["works"], "hp": 1400, "yield": 1.25, "say": "+25% aurite per load"},
	"muster": {"name": "Drill Yard", "cost": 600, "time": 10, "req": ["workshop"], "hp": 1050, "speed": 1.35, "say": "infantry and beasts train 35% faster"},
	"workshop": {"name": "Great Workshop", "cost": 1200, "time": 16, "req": ["works"], "hp": 1700, "speed": 1.3, "pwr": -40, "say": "vehicles build 30% faster"},
	"hammer": {"name": "Sledge Gun", "cost": 400, "time": 8, "req": ["workshop"], "hp": 950, "dmg": 85, "range": 5.5, "say": "harder hitting, longer reach"},
	"sigmast": {"name": "Relay Mast", "cost": 350, "time": 10, "req": ["lz"], "hp": 700, "signal": 11.0, "capAdd": 16, "say": "wider Signal, +6 Command"},
	"drill": {"name": "Deep Bore", "cost": 1000, "time": 15, "req": ["uplink"], "hp": 1300, "yield": 1.3, "say": "pumps 30% faster"},
	"lz": {"name": "Twin Pad", "cost": 1000, "time": 14, "req": ["uplink"], "hp": 1300, "speed": 1.3, "say": "deliveries arrive 30% sooner"},
	"sentry": {"name": "Heavy Sentry", "cost": 400, "time": 8, "req": ["lz"], "hp": 700, "dmg": 40, "range": 6.2, "say": "harder hitting, longer reach"},
	"flak": {"name": "Flak Battery", "cost": 450, "time": 8, "req": ["factory"], "hp": 650, "dmg": 34, "range": 8.5, "say": "harder hitting, longer reach"},
}
## A second step for buildings that age twice (the Garden's Cathedral): applies to the upgraded def, giving BLD3.
var UPG3 := {
	"garden": {"name": "Cathedral Garden", "cost": 1800, "time": 90, "req": ["garden"], "hp": 1600, "hum": 9.0, "rate": 25.0, "say": "the widest Hum, the Carillon and the Cantor"},
}
var BLD3 := {}
## Upgraded building defs, built from BLD + UPG in _init. Their "cost" is base + upgrade (selling refunds half of both).
var BLD2 := {}
## AI upgrade order: the first one it can afford and that is worth it goes next.
const AI_UPG := ["garden", "drill", "lz", "sigmast", "sentry", "power", "kiln", "refinery", "smelter", "garden", "factory", "workshop", "barracks", "muster", "turret", "hammer", "flak"]

var UN := {
	"rifle": {"name": "Trooper", "no": ["choir", "ashen"], "cat": "inf", "cost": 120, "time": 4, "hp": 60, "spd": 1.15, "range": 4.2, "sight": 5, "dmg": 10, "rof": 0.7, "weapon": "bullet", "armor": "inf", "r": 6, "req": ["barracks"]},
	"lancer": {"name": "Lancer", "no": ["ashen", "choir"], "cat": "inf", "cost": 250, "time": 6, "hp": 55, "spd": 1.0, "range": 5, "sight": 6, "dmg": 34, "rof": 2.2, "weapon": "rocket", "armor": "inf", "r": 6, "req": ["barracks"]},
	"ranger": {"name": "Ranger", "fac": "vanguard", "cat": "inf", "cost": 450, "time": 7, "hp": 55, "spd": 1.1, "range": 7.5, "sight": 8, "dmg": 55, "rof": 2.4, "weapon": "snipe", "armor": "inf", "r": 6, "cloak": 3.0, "req": ["barracks", "comms"]},
	"pyro": {"name": "Pyro", "fac": "ashen", "cat": "inf", "cost": 300, "time": 6, "hp": 110, "spd": 1.0, "range": 2.3, "sight": 5, "dmg": 15, "rof": 0.3, "weapon": "flame", "armor": "inf", "r": 6, "req": ["muster"]},
	"raider": {"name": "Ram Bike", "fac": "ashen", "cat": "veh", "cost": 350, "time": 6, "hp": 160, "spd": 3.6, "range": 3.0, "sight": 7, "dmg": 10, "rof": 0.35, "weapon": "bullet", "armor": "light", "r": 9, "ram": 40.0, "req": ["workshop"]},
	"scorpion": {"name": "Anvil Tank", "kit": "cannon", "fac": "ashen", "cat": "veh", "cost": 850, "time": 12, "hp": 540, "spd": 1.5, "range": 4.2, "sight": 6, "dmg": 52, "rof": 1.8, "weapon": "shell", "armor": "heavy", "r": 13, "turret": true, "req": ["workshop"]},
	"anvilf": {"name": "Anvil Tank", "kit": "flamer", "fac": "ashen", "cat": "veh", "cost": 850, "time": 12, "hp": 520, "spd": 1.5, "range": 2.8, "sight": 6, "dmg": 22, "rof": 0.35, "weapon": "flame", "armor": "heavy", "r": 13, "turret": true, "req": ["workshop"]},
	"anvila": {"name": "Anvil Tank", "kit": "arc coil", "fac": "ashen", "cat": "veh", "cost": 850, "time": 12, "hp": 520, "spd": 1.5, "range": 3.8, "sight": 6, "dmg": 36, "rof": 1.4, "weapon": "arc", "armor": "heavy", "r": 13, "turret": true, "req": ["workshop", "works"]},
	"bulwark": {"name": "Bulwark Tank", "fac": "vanguard", "retired": true, "cat": "veh", "cost": 1600, "time": 18, "hp": 850, "spd": 1.15, "range": 5.2, "sight": 6, "dmg": 58, "rof": 1.5, "weapon": "shell", "armor": "heavy", "r": 15, "turret": true, "req": ["factory", "tech"]},
	"arcc": {"name": "Arc Crawler", "fac": "ashen", "cat": "veh", "cost": 1500, "time": 17, "hp": 650, "spd": 1.3, "range": 4.2, "sight": 6, "dmg": 60, "rof": 1.7, "weapon": "arc", "armor": "heavy", "r": 14, "req": ["workshop", "works"]},
	"skyhawk": {"name": "Skyhawk Gunship", "fac": "vanguard", "cat": "air", "sh": 100, "cost": 1300, "time": 20, "hp": 280, "spd": 3.0, "range": 5.5, "sight": 8, "dmg": 34, "rof": 1.3, "weapon": "rocket", "armor": "light", "r": 14, "air": true, "req": ["helipad"]},
	"wasp": {"name": "Wasp Drone", "fac": "vanguard", "retired": true, "cat": "air", "cost": 800, "time": 9, "hp": 160, "spd": 4.4, "range": 3.8, "sight": 7, "dmg": 11, "rof": 0.32, "weapon": "bullet", "armor": "light", "r": 11, "air": true, "req": ["never"]},
	"buggy": {"name": "Hover Scout", "fac": "vanguard", "cat": "veh", "mob": 2, "sh": 60, "cost": 450, "time": 15, "hp": 140, "spd": 3.6, "range": 4.2, "sight": 9, "dmg": 11, "rof": 0.45, "weapon": "bullet", "armor": "light", "r": 10, "req": ["factory"]},
	"tank": {"name": "Warden Tank", "fac": "vanguard", "cat": "veh", "sh": 150, "cost": 900, "time": 20, "hp": 380, "spd": 1.7, "range": 5.0, "sight": 6, "dmg": 44, "rof": 1.7, "weapon": "shell", "armor": "heavy", "r": 12, "turret": true, "req": ["factory"]},
	"medic": {"name": "Field Medic", "no": ["ashen", "choir"], "cat": "inf", "cost": 180, "time": 5, "hp": 55, "spd": 1.1, "range": 2.5, "sight": 5, "heal": 14, "rof": 0.7, "armor": "inf", "r": 6, "req": ["barracks"]},
	"engineer": {"name": "Engineer", "no": ["ashen", "choir"], "cat": "inf", "cost": 500, "time": 8, "hp": 45, "spd": 1.05, "sight": 4, "armor": "inf", "r": 6, "eng": true, "req": ["barracks", "factory"]},
	"arty": {"name": "Howler Mortar", "no": ["choir", "ashen", "vanguard"], "cat": "veh", "cost": 950, "time": 13, "hp": 170, "spd": 1.4, "range": 9, "minr": 2.2, "sight": 6, "dmg": 65, "rof": 3.6, "weapon": "arty", "splash": 46, "armor": "light", "r": 12, "turret": true, "req": ["factory", "repair"]},
	# Vanguard (high tech): long reach and Aegis shields ("sh") over modest hulls. Vehicles and aircraft fly in to a Landing Zone.
	"jump": {"name": "Jump Trooper", "fac": "vanguard", "cat": "inf", "cost": 450, "time": 8, "hp": 80, "spd": 1.4, "range": 4.0, "sight": 6, "dmg": 12, "rof": 0.5, "weapon": "bullet", "armor": "inf", "r": 6, "jump": 6.0, "req": ["barracks", "lz"]},
	"k9": {"name": "K9 Team", "fac": "vanguard", "cat": "inf", "cost": 220, "time": 4, "hp": 70, "spd": 3.0, "range": 0.8, "sight": 7, "dmg": 25, "rof": 0.8, "weapon": "bite", "armor": "light", "r": 6, "detect": 5.0, "req": ["barracks"]},
	"railtank": {"name": "Railtank", "fac": "vanguard", "cat": "veh", "sh": 200, "cost": 1700, "time": 25, "hp": 520, "spd": 1.2, "range": 7.0, "sight": 7, "dmg": 90, "rof": 3.0, "weapon": "rail", "armor": "heavy", "r": 14, "turret": true, "pierce": true, "req": ["lz", "uplink"]},
	"walker": {"name": "Sentinel Walker", "fac": "vanguard", "cat": "veh", "sh": 500, "cost": 3800, "time": 35, "hp": 1400, "spd": 1.1, "range": 6.0, "sight": 8, "dmg": 40, "rof": 1.2, "weapon": "laser", "armor": "heavy", "r": 18, "turret": true, "salvo": 2, "lim": 1, "capCost": 6, "req": ["lz", "uplink"]},
	"spotter": {"name": "Spotter Drone", "fac": "vanguard", "cat": "air", "cost": 500, "time": 15, "hp": 90, "spd": 3.5, "sight": 10, "armor": "light", "r": 9, "air": true, "mark": 4.5, "capCost": 1, "req": ["lz"]},
	"hornets": {"name": "Hornet Drones", "fac": "vanguard", "cat": "air", "cost": 700, "time": 15, "hp": 50, "spd": 4.6, "range": 3.0, "sight": 7, "dmg": 6, "rof": 0.3, "weapon": "bullet", "armor": "light", "r": 7, "air": true, "pack": 4, "capCost": 1, "req": ["lz"]},
	"hydrofoil": {"name": "Hydrofoil Monitor", "fac": "vanguard", "cat": "veh", "mob": 1, "sh": 200, "cost": 1600, "time": 25, "hp": 500, "spd": 2.8, "range": 8.0, "sight": 8, "dmg": 70, "rof": 2.8, "weapon": "rail", "armor": "light", "r": 14, "turret": true, "req": ["lz", "uplink"]},
	# packages: one dropship, several machines, 5% off
	"pk_strike": {"name": "Strike Package", "fac": "vanguard", "cat": "veh", "cost": 2140, "time": 28, "hp": 1, "spd": 1, "sight": 1, "armor": "heavy", "r": 1, "cargo": ["tank", "tank", "buggy"], "capCost": 8, "req": ["lz"]},
	"pk_wing": {"name": "Air Wing Package", "fac": "vanguard", "cat": "air", "cost": 2370, "time": 28, "hp": 1, "spd": 1, "sight": 1, "armor": "light", "r": 1, "cargo": ["skyhawk", "hornets", "spotter"], "capCost": 8, "req": ["lz", "uplink"]},
	# the delivery dropship: flies in from the map edge to a Landing Zone; shot down, its cargo is lost and half the cost comes back
	"dropship": {"name": "Kite Dropship", "fac": "vanguard", "cat": "air", "cost": 0, "time": 1, "hp": 600, "spd": 4.2, "sight": 4, "armor": "light", "r": 16, "air": true, "ship": true, "capCost": 0, "req": ["never"]},
	# Hollow Choir: cheap, quick and fragile. No heavy armour; crystal weapons; the Cantor is their one hero, trained once at a time.
	"thrall": {"name": "Hollow Thralls", "fac": "choir", "cat": "inf", "pack": 3, "cost": 210, "time": 4, "hp": 45, "spd": 1.35, "range": 3.4, "sight": 5, "dmg": 7, "rof": 0.6, "weapon": "shard", "armor": "inf", "r": 5, "fuse": "knot", "mut": {"hp": 1.4}, "req": ["garden"]},
	"wretch": {"name": "Wretch", "fac": "choir", "cat": "inf", "cost": 0, "time": 3, "hp": 35, "spd": 0.9, "range": 0.7, "sight": 5, "dmg": 6, "rof": 1.0, "weapon": "gore", "armor": "inf", "r": 5, "wither": 1.0, "free": true, "retired": true, "req": ["never"]},
	"knot": {"name": "Knot", "fac": "choir", "cat": "inf", "cost": 0, "time": 10, "hp": 700, "spd": 1.0, "range": 0.9, "sight": 5, "dmg": 35, "rof": 1.2, "weapon": "crush", "splash": 32, "armor": "light", "r": 11, "mut": {"range": 4.0, "weapon": "shard", "splash": 0.0}, "retired": true, "req": ["never"]},
	"keener": {"name": "Keener", "fac": "choir", "cat": "inf", "cost": 350, "time": 6, "hp": 70, "spd": 1.1, "range": 5.0, "sight": 7, "dmg": 5, "rof": 1.0, "weapon": "shard", "armor": "inf", "r": 6, "cry": 2.5, "mut": {"cry": 3.5}, "req": ["garden", "bloom"]},
	"sapper": {"name": "Burster", "fac": "choir", "cat": "inf", "cost": 300, "time": 6, "hp": 70, "spd": 1.25, "range": 1.1, "sight": 5, "dmg": 180, "rof": 2.6, "weapon": "charge", "armor": "inf", "r": 6, "burrow": true, "suicide": true, "mut": {"shards": 1}, "req": ["garden"]},
	"cantor": {"name": "The Cantor", "fac": "choir", "cat": "inf", "cost": 1800, "time": 20, "hp": 520, "spd": 1.2, "range": 5.0, "sight": 8, "dmg": 26, "rof": 0.9, "weapon": "shard", "armor": "inf", "r": 7, "hero": true, "lim": 1, "aura": 4.5, "req": ["garden", "cathedral"]},
	"skitter": {"name": "Skitter", "fac": "choir", "cat": "veh", "cost": 240, "time": 5, "hp": 110, "spd": 4.2, "range": 3.4, "sight": 7, "dmg": 8, "rof": 0.4, "weapon": "shard", "armor": "light", "r": 9, "mut": {"spd": 1.2}, "req": ["garden"]},
	"mantis": {"name": "Glass Mantis", "fac": "choir", "cat": "veh", "cost": 650, "time": 9, "hp": 320, "spd": 2.4, "range": 3.0, "sight": 6, "dmg": 38, "rof": 1.3, "weapon": "spine", "armor": "light", "r": 11, "mut": {"dmg": 1.5}, "req": ["garden", "bloom"]},
	"geode": {"name": "Geode Lobber", "fac": "choir", "cat": "veh", "cost": 1100, "time": 13, "hp": 260, "spd": 1.3, "range": 9, "minr": 2.4, "sight": 6, "dmg": 50, "rof": 3.4, "weapon": "geode", "splash": 40, "armor": "light", "r": 12, "turret": true, "mut": {"dmg": 1.3}, "req": ["garden", "bloom"]},
	"undertow": {"name": "Undertow", "fac": "choir", "cat": "veh", "mob": 1, "cost": 700, "time": 9, "hp": 380, "spd": 3.2, "range": 2.0, "sight": 6, "dmg": 36, "rof": 1.2, "weapon": "spine", "armor": "light", "r": 12, "cloak": 2.0, "mut": {"dmg": 1.3}, "req": ["garden", "bloom"]},
	"carillon": {"name": "Carillon", "fac": "choir", "cat": "veh", "cost": 3000, "time": 40, "hp": 1800, "spd": 0.7, "range": 3.0, "sight": 7, "dmg": 40, "rof": 3.0, "weapon": "toll", "splash": 70, "armor": "light", "r": 18, "hum": 6.0, "lim": 1, "mut": {"hum": 8.0}, "req": ["garden", "cathedral"]},
	"moth": {"name": "Glassmoth", "fac": "choir", "cat": "air", "cost": 550, "time": 8, "hp": 120, "spd": 3.6, "range": 3.4, "sight": 9, "dmg": 7, "rof": 0.45, "weapon": "shard", "armor": "light", "r": 10, "air": true, "mut": {"dmg": 1.4}, "req": ["garden", "bloom"]},
	# Ashen Pact (raw power): heavy, slow, short-ranged and brutal. Shared names map to these through FACS.ashen.sub.
	"militia": {"name": "Militia Rifleman", "fac": "ashen", "cat": "inf", "cost": 100, "time": 4, "hp": 75, "spd": 1.05, "range": 3.4, "sight": 5, "dmg": 11, "rof": 0.8, "weapon": "bullet", "armor": "inf", "r": 6, "req": ["muster"]},
	"brute": {"name": "Rivet Brute", "fac": "ashen", "cat": "inf", "cost": 300, "time": 7, "hp": 200, "spd": 0.8, "range": 3.0, "sight": 5, "dmg": 22, "rof": 1.0, "weapon": "rivet", "armor": "inf", "r": 7, "tough": 0.3, "req": ["muster", "smelter"]},
	"grenadier": {"name": "Pipe Grenadier", "fac": "ashen", "cat": "inf", "cost": 220, "time": 6, "hp": 80, "spd": 1.0, "range": 4.5, "minr": 1.5, "sight": 6, "dmg": 30, "rof": 2.0, "weapon": "grenade", "splash": 38, "armor": "inf", "r": 6, "req": ["muster"]},
	"boars": {"name": "Slag Boars", "fac": "ashen", "cat": "inf", "cost": 300, "time": 6, "hp": 110, "spd": 2.8, "range": 0.8, "sight": 6, "dmg": 20, "rof": 0.9, "weapon": "gore", "armor": "light", "r": 7, "pack": 3, "charge": 3.0, "req": ["muster", "smelter"]},
	"scrapper": {"name": "Scrapper", "fac": "ashen", "cat": "inf", "cost": 450, "time": 8, "hp": 70, "spd": 1.05, "sight": 6, "armor": "inf", "r": 6, "eng": true, "scrap": true, "req": ["muster", "workshop"]},
	"kettle": {"name": "Kettle Ram", "fac": "ashen", "cat": "veh", "cost": 700, "time": 10, "hp": 600, "spd": 1.4, "range": 0.9, "sight": 5, "dmg": 120, "rof": 2.5, "weapon": "ram", "armor": "heavy", "r": 13, "bldOnly": true, "req": ["workshop"]},
	"howler": {"name": "Big Howler", "fac": "ashen", "cat": "veh", "cost": 1100, "time": 14, "hp": 260, "spd": 1.1, "range": 8, "minr": 2.5, "sight": 6, "dmg": 90, "rof": 4.5, "weapon": "arty", "splash": 51, "armor": "light", "r": 13, "turret": true, "req": ["workshop", "works"]},
	"jugg": {"name": "Foundry Juggernaut", "fac": "ashen", "cat": "veh", "cost": 3500, "time": 35, "hp": 2400, "spd": 0.8, "range": 5.0, "sight": 7, "dmg": 80, "rof": 2.0, "weapon": "shell", "armor": "heavy", "r": 20, "turret": true, "salvo": 2, "w2": {"weapon": "flame", "dmg": 18, "range": 2.5, "rof": 0.3, "splash": 0.0}, "lim": 1, "capCost": 6, "req": ["workshop", "works"]},
	"gyro": {"name": "Gyro Hammer", "fac": "ashen", "cat": "air", "cost": 1100, "time": 12, "hp": 450, "spd": 2.2, "range": 4.0, "sight": 7, "dmg": 45, "rof": 1.6, "weapon": "shell", "armor": "heavy", "r": 12, "air": true, "req": ["mast"]},
	"zeppelin": {"name": "Ember Zeppelin", "fac": "ashen", "cat": "air", "cost": 1800, "time": 20, "hp": 900, "spd": 0.9, "range": 0.8, "sight": 7, "dmg": 150, "rof": 4.0, "weapon": "bomb", "splash": 64, "armor": "light", "r": 18, "air": true, "req": ["mast", "works"]},
	"ironclad": {"name": "River Ironclad", "fac": "ashen", "cat": "veh", "from": "slipway", "mob": 1, "cost": 1400, "time": 15, "hp": 900, "spd": 1.0, "range": 7.0, "minr": 2.0, "sight": 7, "dmg": 70, "rof": 3.5, "weapon": "arty", "splash": 45, "armor": "heavy", "r": 16, "turret": true, "w2": {"weapon": "flame", "dmg": 18, "range": 2.6, "rof": 0.3, "splash": 0.0}, "req": ["slipway"]},
	"crawler": {"name": "Ore Crawler", "fac": "ashen", "cat": "veh", "cost": 1200, "time": 14, "hp": 750, "spd": 1.25, "sight": 4, "armor": "heavy", "r": 14, "harv": true, "drain": 20.0, "req": ["workshop", "smelter"]},
	# heroes and mission-only units: never trained, a mission brings them
	"vey": {"name": "Kestrel Vey", "fac": "ashen", "cat": "inf", "cost": 0, "time": 1, "hp": 460, "spd": 1.35, "range": 5.2, "sight": 8, "dmg": 30, "rof": 0.7, "weapon": "arc", "armor": "inf", "r": 7, "hero": true, "req": ["never"]},
	"furnace": {"name": "The Furnace", "fac": "ashen", "cat": "veh", "cost": 0, "time": 1, "hp": 1500, "spd": 1.3, "range": 4.8, "sight": 7, "dmg": 72, "rof": 1.6, "weapon": "arc", "armor": "heavy", "r": 16, "hero": true, "req": ["never"]},
	"harrow": {"name": "Ilse Harrow", "fac": "vanguard", "cat": "inf", "cost": 0, "time": 1, "hp": 420, "spd": 1.3, "range": 7.5, "sight": 9, "dmg": 58, "rof": 1.4, "weapon": "rail", "armor": "inf", "r": 7, "hero": true, "req": ["never"]},
	"saint": {"name": "Iron Saint", "fac": "vanguard", "cat": "veh", "cost": 0, "time": 1, "hp": 1900, "spd": 1.15, "range": 5.6, "sight": 7, "dmg": 72, "rof": 1.3, "weapon": "shell", "armor": "heavy", "r": 17, "turret": true, "hero": true, "req": ["never"]},
	"deepmaw": {"name": "The Deepmaw", "fac": "choir", "cat": "veh", "cost": 0, "time": 1, "hp": 1700, "spd": 1.4, "range": 4.6, "sight": 7, "dmg": 66, "rof": 1.5, "weapon": "spine", "armor": "heavy", "r": 17, "hero": true, "req": ["never"]},
	"truck": {"name": "Convoy Truck", "cat": "veh", "cost": 0, "time": 1, "hp": 520, "spd": 1.6, "sight": 5, "armor": "heavy", "r": 13, "req": ["never"]},
	"harv": {"name": "Harvester", "no": ["choir", "ashen", "vanguard"], "cat": "veh", "cost": 1200, "time": 14, "hp": 650, "spd": 1.35, "sight": 4, "armor": "heavy", "r": 14, "harv": true, "drain": 20.0, "req": ["factory", "refinery"]},
}

const MOD := {
	"snipe": {"inf": 1.6, "light": 0.3, "heavy": 0.1, "bld": 0.05}, "flame": {"inf": 1.4, "light": 0.7, "heavy": 0.35, "bld": 0.9},
	"arc": {"inf": 1.1, "light": 1.05, "heavy": 0.85, "bld": 0.7}, "flak": {"inf": 0.25, "light": 1.2, "heavy": 0.8, "bld": 0.1},
	"sw": {"inf": 1, "light": 1, "heavy": 1, "bld": 1}, "arty": {"inf": 0.9, "light": 0.8, "heavy": 0.6, "bld": 1.1},
	"bullet": {"inf": 1, "light": 0.6, "heavy": 0.22, "bld": 0.25}, "rocket": {"inf": 0.35, "light": 1.1, "heavy": 1.15, "bld": 0.75},
	"shell": {"inf": 0.45, "light": 0.9, "heavy": 1, "bld": 1}, "rail": {"inf": 1.4, "light": 0.9, "heavy": 0.5, "bld": 0.55},
	"shard": {"inf": 1.15, "light": 1.0, "heavy": 0.3, "bld": 0.35}, "spine": {"inf": 0.4, "light": 1.1, "heavy": 1.05, "bld": 0.6},
	"geode": {"inf": 1.0, "light": 0.85, "heavy": 0.45, "bld": 0.9}, "charge": {"inf": 0.3, "light": 0.8, "heavy": 0.9, "bld": 1.6},
	"rivet": {"inf": 1.0, "light": 0.8, "heavy": 0.6, "bld": 0.5}, "grenade": {"inf": 1.2, "light": 0.6, "heavy": 0.3, "bld": 1.3},
	"gore": {"inf": 1.4, "light": 0.8, "heavy": 0.3, "bld": 0.1}, "ram": {"inf": 0.0, "light": 0.0, "heavy": 0.0, "bld": 1.0},
	"bomb": {"inf": 1.0, "light": 1.0, "heavy": 0.9, "bld": 1.2},
	"crush": {"inf": 1.3, "light": 0.9, "heavy": 0.5, "bld": 0.6}, "toll": {"inf": 1.0, "light": 0.0, "heavy": 0.0, "bld": 0.0},
	"laser": {"inf": 0.9, "light": 0.9, "heavy": 0.9, "bld": 0.7}, "bite": {"inf": 1.4, "light": 0.6, "heavy": 0.12, "bld": 0.05},
}
const CATS := {
	"bld": ["power", "sigmast", "kiln", "hearth", "drill", "refinery", "smelter", "garden", "barracks", "muster", "burrow", "factory", "lz", "workshop", "slipway", "turret", "sentry", "hammer", "flak", "pdl", "wall", "repair", "comms", "helipad", "mast", "tech", "uplink", "works", "dome", "bastion", "pylon", "spire", "thorn", "skyfall", "rift", "chorus"],
	"inf": ["rifle", "militia", "thrall", "keener", "lancer", "grenadier", "medic", "k9", "engineer", "scrapper", "ranger", "jump", "pyro", "brute", "boars", "sapper", "cantor"],
	"veh": ["buggy", "raider", "skitter", "tank", "scorpion", "anvilf", "anvila", "mantis", "kettle", "arty", "howler", "geode", "undertow", "carillon", "bulwark", "railtank", "arcc", "walker", "jugg", "pk_strike", "harv", "crawler", "ironclad", "hydrofoil"],
	"air": ["spotter", "hornets", "skyhawk", "pk_wing", "gyro", "zeppelin", "wasp", "moth"],
}
const CAT_ORDER := ["bld", "inf", "veh", "air"]
const PRODUCER := {"inf": "barracks", "veh": "factory", "air": "helipad"}
const AIRW := ["bullet", "rocket", "flak", "rivet", "laser", "shard"]
## Weapons that lob over hills; everything else needs a clear line of fire.
## Projectile speeds in pixels per second (lobbed shots not listed here fly at 230, the rest at 290).
const PSPD := {"shell": 440.0, "flak": 560.0, "spine": 330.0, "rivet": 360.0, "bomb": 120.0}
const INDIRECT := ["arty", "geode", "grenade"]
const FACS := {
	"vanguard": {"name": "Vanguard", "lv": "buggy", "mt": "tank", "ht": "railtank", "air": "skyhawk", "inf": "ranger", "def": "bastion", "sw": "skyfall", "cap_bld": "sigmast",
		"ai_inf": ["rifle", "rifle", "lancer", "lancer", "k9", "jump", "ranger", "medic"], "ai_veh": ["buggy", "tank", "tank", "tank", "railtank", "railtank", "walker", "pk_strike"],
		"ai_air": ["skyhawk", "skyhawk", "hornets", "spotter"], "ai_sea": ["hydrofoil"],
		"sub": {"power": "sigmast", "refinery": "drill", "factory": "lz", "helipad": "lz", "comms": "", "repair": "", "tech": "uplink", "turret": "sentry", "flak": "pdl",
			"harv": "", "arty": "railtank", "bulwark": "railtank", "wasp": "hornets"}},
	"ashen": {"name": "Ashen Pact", "cap_bld": "hearth",
		"ai_order": ["power", "refinery", "barracks", "refinery", "factory", "turret", "NAVAL", "flak", "refinery", "power", "DEF", "turret", "helipad", "power", "tech", "DEF", "power", "flak", "SW", "power", "DEF", "turret", "power"], "lv": "raider", "mt": "scorpion", "ht": "arcc", "air": "gyro", "inf": "pyro", "def": "pylon", "sw": "rift",
		"ai_inf": ["militia", "militia", "brute", "brute", "grenadier", "pyro", "boars"], "ai_veh": ["raider", "scorpion", "scorpion", "scorpion", "anvilf", "anvila", "scorpion", "howler", "arcc", "arcc", "jugg", "kettle"],
		"ai_air": ["gyro", "gyro", "zeppelin"], "naval": "slipway", "ai_sea": ["ironclad"],
		"sub": {"rifle": "militia", "lancer": "grenadier", "medic": "", "engineer": "scrapper", "arty": "howler", "harv": "crawler", "refinery": "smelter",
			"power": "kiln", "barracks": "muster", "factory": "workshop", "helipad": "mast", "comms": "", "repair": "", "tech": "works", "turret": "hammer",
			"wasp": "gyro"}},
	"choir": {"name": "Hollow Choir", "lv": "skitter", "mt": "mantis", "ht": "geode", "air": "moth", "inf": "sapper", "def": "spire", "sw": "chorus", "tun": "burrow", "hero": "cantor",
		"ai_order": ["garden", "garden", "spire", "TUN", "spire", "TUN", "garden", "spire", "SW", "garden", "spire", "TUN", "spire"],
		"ai_inf": ["thrall", "thrall", "thrall", "sapper", "keener", "keener"], "ai_veh": ["skitter", "mantis", "mantis", "mantis", "geode", "geode", "carillon"], "ai_air": ["moth"], "ai_sea": ["undertow"],
		"sub": {"refinery": "garden", "power": "", "barracks": "garden", "factory": "garden", "helipad": "garden", "comms": "", "repair": "", "tech": "", "turret": "spire", "flak": "spire",
			"wall": "thorn", "rifle": "thrall", "lancer": "keener", "medic": "", "engineer": "", "arty": "geode", "harv": "", "wasp": "moth"}},
}
const FAC_ORDER := ["vanguard", "ashen", "choir"]
## Faction rules (faction redesign, phase 2 groundwork). Each faction plays by its own rules instead of shared ones.
## Today all three still use the old rules; the Pact, Vanguard and Choir phases switch theirs.
##   power: its buildings make and use power (low power slows production, weapons and superweapons).
##   place: where it may put a building: "near" = within 2 tiles of one of its own buildings.
##   cap:   a unit cap is on (buildings with capAdd raise it, every unit uses capCost).
##   prod:  the building that makes each unit category, when it is not D.PRODUCER's.
var RULES := {
	"vanguard": {"power": false, "place": "signal", "cap": true, "swap": true, "pods": false, "prod": {"veh": "lz", "air": "lz"}},
	"ashen": {"power": true, "place": "near", "cap": true, "swap": true, "pods": false, "prod": {"inf": "muster", "veh": "workshop", "air": "mast"}},
	"choir": {"power": false, "place": "hum", "cap": false, "swap": true, "pods": true, "prod": {"inf": "garden", "veh": "garden", "air": "garden"}},
}
func rule(fac: String, key: String):
	return RULES[fac][key] if RULES.has(fac) else RULES.vanguard[key]
## The building type that makes units of a category for this faction ("" for "bld").
func producer(fac: String, cat: String) -> String:
	return rule(fac, "prod").get(cat, PRODUCER.get(cat, ""))
## Unit cap: what each unit costs when the faction has a cap (an override "capCost" in a unit def wins).
const CAP_COST := {"inf": 1, "veh": 2, "air": 3}
## Living fields: every ore tile has a vitality (0..100). Earners lower it as they take ore ("drain": vitality lost
## when a whole tile is emptied, negative heals); a tile left alone for "rest" seconds regrows ore up to its start
## amount scaled by vitality, and its vitality slowly comes back. At 0 the tile is dead for good (grey, no ore).
## Pact Furnaces: seconds of fuel kept back from spending (Sim.fuel_reserve).
const FUEL_KEEP := 20.0
## Pact salvage: a wreck starts this intact and burns down; above "revive" a Scrapper rebuilds it, below it only strips it.
## Vanguard: Aegis shields come back at "regen" of the full shield a second once "rest" seconds pass without a hit; arcs drain
## them "arc" times as fast. A lost vehicle leaves a beacon for "beacon" seconds: hold it "hold" seconds for "back" of its cost.
## Every prefab takes "prefab" seconds to arrive. A spotted target takes "mark" times the damage.
## Hollow Choir. Pods: each Garden ripens one every "pod" seconds and holds "hold". In the Hum its forms heal "heal" of their
## hp a second and move "haste" faster; living crystal cuts human infantry for "cut" hp a second; human infantry killed in
## the Hum rise as Wretches after "rise" seconds. A form mutates after "mut" kills. A Keener's cry lasts "jam" seconds, every "cry".
const HUM := {"pod": 15.0, "hold": 3, "heal": 0.02, "haste": 1.15, "cut": 3.0, "rise": 3.0, "mut": 3, "jam": 4.0, "cry": 15.0, "fuse": 4, "spread": 60.0}
const AEGIS := {"regen": 0.10, "rest": 6.0, "arc": 2.0, "beacon": 30.0, "hold": 5.0, "back": 0.4, "prefab": 8.0, "mark": 1.25, "lost": 0.5}
const WRECK := {"start": 0.6, "decay": 0.006, "revive": 0.3, "revive_t": 12.0, "strip_t": 8.0, "strip": 0.4, "fix": 25.0}
const FIELD := {"tick": 2.0, "rest": 30.0, "ore": 0.02, "vit": 0.2}
## The faction's own version of a shared type: the Choir has gardens for refineries, thralls for riflemen.
## "" when the faction has none.
static func sub(fac: String, t: String) -> String:
	return FACS[fac].get("sub", {}).get(t, t) if FACS.has(fac) else t
## Campaign difficulty the player picks on the briefing: shifts the mission's own enemy strength one step and
## scales enemy starting aurite, waves and scripted attacks.
const LEVELS := {
	"easy": {"name": "Easy", "shift": -1, "credits": 0.6, "waves": 0.6, "first": 120},
	"normal": {"name": "Normal", "shift": 0, "credits": 1.0, "waves": 1.0, "first": 0},
	"hard": {"name": "Hard", "shift": 1, "credits": 1.3, "waves": 1.3, "first": -40},
}
const DIFF_ORDER := ["recruit", "easy", "normal", "hard"]
const DIFF := {
	"recruit": {"prod": 0.5, "inc": 0.6, "first": 420, "start": 2500},
	"easy": {"prod": 0.7, "inc": 0.8, "first": 330, "start": 3000},
	"normal": {"prod": 1.0, "inc": 1.0, "first": 210, "start": 3000},
	"hard": {"prod": 1.3, "inc": 1.35, "first": 140, "start": 4000},
}
## Colours follow the faction: the Vanguard is blue, the Ashen Pact red. TEAMC and MINI_COL are
## indexed by team and set for each match by set_team_colors().
const FCOL := {
	"vanguard": {"col": Color("#3fb4e8"), "dk": Color("#174a63"), "lt": Color("#a6e3ff"), "mini": Color("#5cc8ff")},
	"ashen": {"col": Color("#e0423a"), "dk": Color("#5e1512"), "lt": Color("#ffb0a8"), "mini": Color("#ff5a4f")},
	"choir": {"col": Color("#3cc457"), "dk": Color("#14481f"), "lt": Color("#a8f0b4"), "mini": Color("#4fe06a")},
}
var TEAMC: Array = [FCOL.vanguard, FCOL.ashen]
var MINI_COL: Array = [FCOL.vanguard.mini, FCOL.ashen.mini]

## Returns true when the colours changed (cached models must be rebuilt).
func set_team_colors(f0: String, f1: String) -> bool:
	if TEAMC[0] == FCOL[f0] and TEAMC[1] == FCOL[f1]: return false
	TEAMC = [FCOL[f0], FCOL[f1]]; MINI_COL = [FCOL[f0].mini, FCOL[f1].mini]
	return true
const TCOL := [Color8(74, 98, 50), Color8(112, 94, 64), Color8(158, 140, 98), Color8(98, 92, 86), Color8(34, 76, 98)]
## Landscapes. Colours are sRGB 0..1. grass = base + noise * var. trees: "pine" (two cones), "snowpine" (pine with a white cap),
## "broad" (round crowns), "dead" (bare trunks), "palm"-less on purpose: the valley has none.
const THEMES := {
	"temperate": {"name": "Green river country", "grass": [0.30, 0.42, 0.20], "gvar": [0.12, 0.10, 0.04], "dirt": [0.50, 0.40, 0.27], "sand": [0.68, 0.60, 0.42], "rock": [0.40, 0.37, 0.33],
		"cliff": [0.44, 0.41, 0.37], "bed": [0.22, 0.30, 0.30], "trees": "pine", "tcol": ["3f6b2c", "4f7d33", "355e2a", "6b8a3a"], "trunk": "5a4130", "bush": "4f7a34", "stone": "8a8174",
		"tden": 0.075, "bden": 0.085, "water": [0.227, 0.525, 0.659, 0.84], "sun": "fff0d8", "sunE": 1.05, "amb": "aeb6be", "ambE": 0.75},
	"autumn": {"name": "Autumn foundry country", "grass": [0.42, 0.38, 0.18], "gvar": [0.14, 0.08, 0.03], "dirt": [0.50, 0.38, 0.25], "sand": [0.66, 0.57, 0.40], "rock": [0.42, 0.38, 0.34],
		"cliff": [0.45, 0.40, 0.35], "bed": [0.22, 0.27, 0.26], "trees": "broad", "tcol": ["b4562a", "d08a2e", "8f3e22", "c7a03a"], "trunk": "4a3428", "bush": "8a6a2c", "stone": "857a6c",
		"tden": 0.09, "bden": 0.08, "water": [0.25, 0.45, 0.50, 0.86], "sun": "ffe2b8", "sunE": 1.0, "amb": "b8aa9c", "ambE": 0.75},
	"arid": {"name": "Dust flats", "grass": [0.62, 0.52, 0.32], "gvar": [0.10, 0.08, 0.05], "dirt": [0.58, 0.42, 0.26], "sand": [0.76, 0.66, 0.45], "rock": [0.56, 0.42, 0.30],
		"cliff": [0.60, 0.44, 0.30], "bed": [0.36, 0.32, 0.24], "trees": "dead", "tcol": ["7a6a3a", "8a7a44", "6a5a32", "9a8a52"], "trunk": "5e4a36", "bush": "8c8550", "stone": "a08060",
		"tden": 0.018, "bden": 0.05, "water": [0.36, 0.48, 0.44, 0.86], "sun": "fff2d0", "sunE": 1.12, "amb": "c4b8a4", "ambE": 0.78},
	"snow": {"name": "Ironpine snowfields", "grass": [0.80, 0.83, 0.86], "gvar": [0.08, 0.07, 0.05], "dirt": [0.58, 0.56, 0.54], "sand": [0.70, 0.72, 0.74], "rock": [0.42, 0.43, 0.46],
		"cliff": [0.48, 0.49, 0.52], "bed": [0.24, 0.32, 0.38], "trees": "snowpine", "tcol": ["24452f", "2c5236", "1f3d2a", "35603e"], "trunk": "4a3a30", "bush": "c6ccd0", "stone": "7c8088",
		"tden": 0.085, "bden": 0.05, "water": [0.42, 0.60, 0.70, 0.90], "sun": "e8f0ff", "sunE": 0.95, "amb": "b0bccc", "ambE": 0.72},
	"ash": {"name": "Cinder hills", "grass": [0.26, 0.24, 0.22], "gvar": [0.08, 0.06, 0.05], "dirt": [0.36, 0.29, 0.24], "sand": [0.46, 0.40, 0.34], "rock": [0.24, 0.22, 0.21],
		"cliff": [0.30, 0.27, 0.25], "bed": [0.30, 0.12, 0.06], "trees": "dead", "tcol": ["2a2420", "322a24", "241e1a", "3a3028"], "trunk": "2a2420", "bush": "4a3e30", "stone": "4a4440",
		"tden": 0.05, "bden": 0.04, "water": [0.85, 0.32, 0.10, 0.92], "lava": true, "sun": "ffc8a0", "sunE": 0.95, "amb": "a89c98", "ambE": 0.72},
	"marsh": {"name": "Reedmarsh", "grass": [0.24, 0.34, 0.20], "gvar": [0.08, 0.10, 0.05], "dirt": [0.36, 0.33, 0.22], "sand": [0.48, 0.46, 0.32], "rock": [0.34, 0.34, 0.30],
		"cliff": [0.38, 0.38, 0.33], "bed": [0.16, 0.22, 0.18], "trees": "broad", "tcol": ["2f4a26", "3a5a2c", "28401f", "4a5e30"], "trunk": "3e3226", "bush": "6a7a3a", "stone": "6e6c60",
		"tden": 0.05, "bden": 0.16, "water": [0.20, 0.36, 0.34, 0.86], "sun": "f2ecd0", "sunE": 0.95, "amb": "a8b0a4", "ambE": 0.74},
}
## Dusk light for some missions: low warm sun, cooler shadows.
const DUSK := {"sun": "ffa868", "sunE": 0.85, "amb": "8890a8", "ambE": 0.62}

## Minimap colours for a landscape: grass, dirt, sand, rock, water.
var _tcol := {}
func tcol(theme: String) -> Array:
	if not _tcol.has(theme):
		var TH: Dictionary = THEMES[theme]
		var c := func(a: Array) -> Color: return Color(a[0], a[1], a[2])
		_tcol[theme] = [c.call(TH.grass), c.call(TH.dirt), c.call(TH.sand), c.call(TH.rock), c.call(TH.water)]
	return _tcol[theme]

const BH := {"thorn": 0.6, "sigmast": 2.2, "drill": 1.6, "lz": 0.4, "uplink": 2.0, "sentry": 0.7, "pdl": 0.9, "dome": 1.0, "kiln": 1.4, "hearth": 0.9, "smelter": 1.3, "muster": 1.0, "workshop": 1.3, "works": 1.3, "mast": 2.0, "slipway": 1.0, "hammer": 0.8, "hq": 1.55, "power": 1.25, "refinery": 1.3, "barracks": 0.95, "factory": 1.2, "turret": 0.7, "repair": 1.0, "wall": 0.6, "flak": 0.8, "comms": 2.2, "helipad": 0.5, "tech": 1.3, "bastion": 1.2, "pylon": 1.9, "skyfall": 1.0, "rift": 2.2, "garden": 1.3, "burrow": 0.7, "spire": 1.8, "chorus": 2.0}
const UH := {"wretch": 0.45, "knot": 0.7, "keener": 0.55, "undertow": 0.3, "carillon": 1.4, "jump": 0.55, "k9": 0.35, "railtank": 0.5, "walker": 1.0, "spotter": 0.2, "hornets": 0.15, "hydrofoil": 0.45, "dropship": 0.5, "ironclad": 0.6, "militia": 0.5, "brute": 0.6, "grenadier": 0.55, "boars": 0.3, "scrapper": 0.5, "anvilf": 0.45, "anvila": 0.45, "kettle": 0.45, "howler": 0.6, "jugg": 0.8, "gyro": 0.4, "zeppelin": 0.5, "crawler": 0.58, "rifle": 0.5, "lancer": 0.55, "medic": 0.5, "engineer": 0.5, "ranger": 0.5, "pyro": 0.55, "buggy": 0.42, "raider": 0.45, "tank": 0.48, "scorpion": 0.4, "bulwark": 0.6, "arcc": 0.85, "arty": 0.55, "harv": 0.58, "skyhawk": 0.4, "wasp": 0.25, "vey": 0.62, "harrow": 0.62, "furnace": 0.95, "saint": 0.8, "truck": 0.6, "deepmaw": 0.9, "thrall": 0.48, "sapper": 0.45, "cantor": 0.7, "skitter": 0.4, "mantis": 0.6, "geode": 0.6, "moth": 0.25}

const ALLB := ["thorn", "sigmast", "drill", "lz", "uplink", "sentry", "pdl", "dome", "power", "kiln", "hearth", "refinery", "smelter", "garden", "barracks", "muster", "burrow", "factory", "workshop", "slipway", "turret", "hammer", "flak", "wall", "repair", "comms", "helipad", "mast", "tech", "works", "bastion", "pylon", "spire", "skyfall", "rift", "chorus"]
## "DEF", "SW" and "TUN" are the faction's defence, superweapon and tunnel (skipped when it has none); shared types go through sub().
const AI_ORDER := ["power", "refinery", "barracks", "power", "factory", "TUN", "turret", "power", "refinery", "NAVAL", "flak", "comms", "repair", "TUN", "power", "DEF", "turret", "helipad", "power", "tech", "DEF", "TUN", "power", "flak", "SW", "power", "DEF", "turret", "power"]

var CAMPAIGNS: Array = []

## Who talks on the radio and in debriefs (mission lines name them with "who"). Portraits are drawn by UI.Portrait
## from these: skin, hair, uniform, gear (cap · helmet · goggles · hood), beard (full · moustache), long hair, age,
## brow (frown), smile, scar, patch, glow (Choir eyes), jaw width, flash (shoulder and frame colour), tint (screen).
const SPEAKERS := {
	"vey": {"name": "Kestrel Vey", "role": "Pact cell leader", "skin": Color("c98f6c"), "hair": Color("7a2e1c"), "long": true, "uniform": Color("5a2c22"),
		"gear": "goggles", "scar": true, "brow": 0.6, "smile": 0.4, "jaw": 0.11, "age": 0.25, "flash": Color("e5483f"), "tint": Color("4a2a20")},
	"brann": {"name": "Old Brann", "role": "Foundry master", "skin": Color("b97a58"), "hair": Color("b9b2a6"), "uniform": Color("4a3a2a"),
		"beard": "full", "hair_top": false, "age": 0.9, "brow": 0.3, "smile": 0.6, "jaw": 0.15, "flash": Color("d9a441"), "tint": Color("4a3020")},
	"foreman": {"name": "The Foreman", "role": "Pact adviser", "skin": Color("d39a78"), "hair": Color("3a2620"), "uniform": Color("3f2a24"),
		"gear": "cap", "cap": Color("2a1d19"), "band": Color("e5483f"), "beard": "moustache", "brow": 0.8, "smile": -0.3, "jaw": 0.16, "age": 0.6, "flash": Color("e5483f"), "tint": Color("40261e")},
	"dace": {"name": "Marshal Corwin Dace", "role": "Vanguard commander", "skin": Color("e0b294"), "hair": Color("2c2a28"), "uniform": Color("2f3e4c"),
		"gear": "cap", "cap": Color("26323e"), "band": Color("3fb4e8"), "patch": true, "brow": 0.9, "smile": 0.5, "jaw": 0.14, "age": 0.6, "flash": Color("3fb4e8"), "tint": Color("1f2e3a")},
	"harrow": {"name": "Captain Ilse Harrow", "role": "Vanguard officer", "skin": Color("eac3a3"), "hair": Color("c9a86a"), "uniform": Color("34495a"),
		"gear": "helmet", "cap": Color("4a5a66"), "brow": 0.4, "jaw": 0.11, "age": 0.3, "flash": Color("3fb4e8"), "tint": Color("22323e")},
	"pact_hq": {"name": "Pact radio", "role": "Signals", "skin": Color("c48e6e"), "hair": Color("2a1c16"), "uniform": Color("4a2a22"), "gear": "helmet", "cap": Color("4a3a30"),
		"jaw": 0.13, "flash": Color("e5483f"), "tint": Color("3a241c")},
	"van_hq": {"name": "Vanguard command", "role": "Signals", "skin": Color("d8ae90"), "hair": Color("3a3024"), "uniform": Color("2f3e4c"), "gear": "helmet", "cap": Color("46555f"),
		"jaw": 0.13, "flash": Color("3fb4e8"), "tint": Color("1f2e3a")},
	"choir_hq": {"name": "The Choir", "role": "Many voices", "skin": Color("9fa898"), "hair": Color("2a2e2a"), "uniform": Color("1e2a24"), "gear": "hood", "glow": true,
		"jaw": 0.12, "flash": Color("3fbf7a"), "tint": Color("102018")},
}

func _init() -> void:
	for k in BLD:
		var d: Dictionary = BLD[k]
		d.type = k
		for kv in [["fac", ""], ["weapon", ""], ["dmg", 0], ["range", 0.0], ["rof", 1.0], ["antiAir", false], ["needPower", false], ["sw", false], ["charge", 0.0], ["kit", 0], ["splash", 0.0], ["minr", 0.0], ["air", false], ["heal", 0], ["eng", false], ["harv", false], ["turret", false], ["armor", "bld"], ["no", []], ["grow", false], ["tun", false], ["lim", 0], ["capAdd", 0], ["drain", 0.0], ["shore", false], ["yard", false], ["burn", 0.0], ["muster", 0], ["dock", false], ["door", false], ["signal", 0.0], ["pump", 0], ["onore", false], ["pad", false], ["dome", 0.0], ["sh", 0], ["hum", 0.0], ["rate", 0.0], ["field", false], ["thorn", 0.0], ["retired", false]]:
			if not d.has(kv[0]): d[kv[0]] = kv[1]
	for k in UPG:
		var u: Dictionary = UPG[k]; var b: Dictionary = BLD[k].duplicate(true)
		for kk in u:
			if not ["cost", "time", "req", "say"].has(kk): b[kk] = u[kk]
		b.cost = BLD[k].cost + u.cost; b.lv = 2; b.base = BLD[k].name
		if not b.has("speed"): b.speed = 1.0
		if not b.has("yield"): b["yield"] = 1.0
		BLD2[k] = b
		for kv in [["speed", 1.0], ["yield", 1.0]]:
			if not u.has(kv[0]): u[kv[0]] = kv[1]
	for k in UPG3:
		var u: Dictionary = UPG3[k]; var b: Dictionary = BLD2[k].duplicate(true)
		for kk in u:
			if not ["cost", "time", "req", "say"].has(kk): b[kk] = u[kk]
		b.cost = BLD2[k].cost + u.cost; b.lv = 3; b.base = BLD[k].name
		BLD3[k] = b
		for kv in [["speed", 1.0], ["yield", 1.0]]:
			if not u.has(kv[0]): u[kv[0]] = kv[1]
	for k in BLD:
		for kv in [["lv", 1], ["speed", 1.0], ["yield", 1.0]]:
			if not BLD[k].has(kv[0]): BLD[k][kv[0]] = kv[1]
	for k in UN:
		var d: Dictionary = UN[k]
		d.type = k
		for kv in [["fac", ""], ["weapon", ""], ["dmg", 0], ["range", 0.0], ["rof", 1.0], ["air", false], ["turret", false], ["heal", 0], ["eng", false], ["harv", false], ["minr", 0.0], ["splash", 0.0], ["antiAir", false], ["hero", false], ["no", []], ["burrow", false], ["lim", 0], ["aura", 0.0], ["drain", 0.0], ["mob", 0], ["from", ""], ["tough", 0.0], ["pack", 1], ["charge", 0.0], ["ram", 0.0], ["bldOnly", false], ["salvo", 1], ["w2", null], ["scrap", false], ["kit", ""], ["retired", false], ["sh", 0], ["cloak", 0.0], ["jump", 0.0], ["detect", 0.0], ["pierce", false], ["mark", 0.0], ["cargo", []], ["ship", false], ["hum", 0.0], ["mut", {}], ["cry", 0.0], ["suicide", false], ["wither", 0.0], ["fuse", ""], ["free", false]]:
			if not d.has(kv[0]): d[kv[0]] = kv[1]
		if not d.has("capCost"): d.capCost = CAP_COST.get(d.cat, 1)
	CAMPAIGNS = Campaign.all()
	for c in CAMPAIGNS:
		for i in c.missions.size():
			var m: Dictionary = c.missions[i]
			m.idx = i; m.camp = c.id; m.fac = c.fac
			if not m.has("mood"): m.mood = Campaign.mood(c.id, i)
			for kv in [["aiBuild", true], ["aiProd", true], ["aiFirst", -1], ["waves", null], ["swCh", 0.0], ["tech", null], ["aiTech", null], ["phq", true],
					["pbase", []], ["punits", []], ["pheroes", []], ["ehq", "hq"], ["ebase", []], ["eunits", []], ["eheroes", []], ["posts", []], ["captives", []],
					["events", []], ["efac", ""], ["keep", []], ["limit", 0.0], ["credits", [3000, 3000]], ["diff", "normal"], ["heroes", []], ["theatre", ""], ["pvip", []]]:
				if not m.has(kv[0]): m[kv[0]] = kv[1]
			for g in m.goals:
				for kv in [["waves", null], ["done", null], ["label", ""], ["r", 2.5], ["who", "any"], ["need", 1], ["t", 0.0], ["types", []], ["tag", ""], ["protect", []], ["zone", null], ["zones", []], ["at", null], ["n", 0]]:
					if not g.has(kv[0]): g[kv[0]] = kv[1]

func camp(id: String) -> Dictionary:
	for c in CAMPAIGNS:
		if c.id == id: return c
	return CAMPAIGNS[0]

func def_of(t: String) -> Dictionary:
	return BLD[t] if BLD.has(t) else UN[t]

static func fmt(t: float) -> String:
	var s := int(ceil(max(0.0, t)))
	return "%d:%02d" % [s / 60, s % 60]
