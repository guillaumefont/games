extends RefCounted
## In-campaign tutorial text and rules: unit cards, enemy cards, pointer lessons and drills, mission by mission.
## All tutorial words live here (ready for translation later). Approved by Guillaume on 2026-11-20
## ("Aurite Front: unit tutorial script"). Campaign I cards were rewritten for the Pact roster in the faction redesign
## (decided 2026-11-21: merge the tutorial first, update its cards in the Pact phase). Campaigns II and III teach only
## what is new in their own army: the controls and the shared basics are taught once, in campaign I.
##
## Limits checked by tests/sim_test.gd tutorial_tests(): job and tip at most 60 characters, a speaker line at most 64,
## a lesson hint at most 60.

## Unit and lesson cards. A key is the unit or building type it explains, or "l_<name>" for a lesson card.
##   job, tip, who (Data.SPEAKERS), say: the card's words. gw: replaces the computed good/weak line (no weapon, special).
##   home: [campaign, mission index] where the card belongs. Before that mission it shows only when the player trains or
##   builds the thing; from that mission on it shows as soon as the player has one.
const CARDS := {
	# ---- campaign I, mission 1: Smoke on the River
	"vey": {"job": "Hero with an arc rifle. If she falls, you lose.", "tip": "Keep the Medic close to her",
		"who": "foreman", "say": "That's Vey. Keep her breathing or we all go home.", "home": ["ashen", 0]},
	"militia": {"job": "Cheap town militia. Fires at aircraft too.", "tip": "Double-tap one to select them all",
		"who": "vey", "say": "Militia. Foundry hands with rifles. They'll stand.", "home": ["ashen", 0]},
	"pyro": {"job": "Short-range flamer. Clears infantry fast.", "tip": "Get close: its reach is barely two tiles",
		"who": "foreman", "say": "Pyros! Point them at soldiers, not at tanks.", "home": ["ashen", 0]},
	"medic": {"job": "A town doctor. Heals nearby infantry.", "tip": "Keep her just behind the front line", "gw": "Heals infantry only, not vehicles",
		"who": "vey", "say": "Doc stays behind me. Nobody bleeds out on my hill.", "home": ["ashen", 0]},
	# ---- mission 2: Kettleford
	"grenadier": {"job": "Lobs pipe bombs over cover. Cracks buildings.", "tip": "Keep enemies at range: it can't fire up close",
		"who": "foreman", "say": "Grenadiers! Duck when they wind up, boss.", "home": ["ashen", 1]},
	"raider": {"job": "Fast bike. Rams infantry flat as it passes.", "tip": "Drive it through a squad, then away",
		"who": "brann", "say": "Fastest thing on wheels. Aim it at their boots.", "home": ["ashen", 1]},
	"boars": {"job": "Pack of three war boars. Charge, gore, knock down.", "tip": "Rest them between fights: the charge comes back",
		"who": "vey", "say": "Slag Boars. Don't stand in front of them. Ever.", "home": ["ashen", 1]},
	"hammer": {"job": "Short fat cannon. Guards the base from vehicles.", "tip": "Put it where enemies come in, behind Barriers",
		"who": "foreman", "say": "Hammer Gun's up! Loves tanks. Infantry, not so much.", "home": ["ashen", 1]},
	"wall": {"name": "Barrier", "job": "Four wall pieces per purchase. Blocks and funnels.", "tip": "Tap the map four times to lay all four", "gw": "No weapon",
		"who": "vey", "say": "Walls don't win fights. They pick where fights happen.", "home": ["ashen", 1]},
	"hearth": {"job": "Houses your army: +10 units. Can muster Militia.", "tip": "Tap MUSTER once a battle: 3 free Militia each", "gw": "No weapon",
		"who": "foreman", "say": "No Hearth, no bunks, no army. Build more, boss!", "home": ["ashen", 1]},
	"smelter": {"job": "Turns aurite into money. Comes with a Crawler.", "tip": "Build it close to an ore field", "gw": "No weapon",
		"who": "brann", "say": "Short trips, fat profits. Build it by the ore.", "home": ["ashen", 1]},
	"crawler": {"job": "Slow armoured miner. Hauls aurite home. No gun.", "tip": "Tap aurite to send it mining", "gw": "No weapon, heavy armour",
		"who": "brann", "say": "My Crawlers. Scratch the paint, I scratch you.", "home": ["ashen", 1]},
	"workshop": {"job": "Builds vehicles. Needs a Smelter.", "tip": "Select it and tap the map to set a rally", "gw": "No weapon",
		"who": "brann", "say": "The Workshop's warm. Let's make something heavy.", "home": ["ashen", 1]},
	# ---- mission 3: Dust and Ore
	"scorpion": {"job": "Pact battle tank. Slow, thick, hits like a hammer.", "tip": "Send infantry with it to handle rifles",
		"who": "vey", "say": "Anvils. Slow as a funeral, twice as final.", "home": ["ashen", 2]},
	"anvilf": {"name": "Anvil Tank (flamer)", "job": "Anvil with a flamer kit. Burns out infantry.", "tip": "Lead into trenches and towns",
		"who": "brann", "say": "Same Anvil, new kit. Bolt it on, light it up.", "home": ["ashen", 2]},
	"brute": {"job": "Big man in plate. Rifle fire barely scratches him.", "tip": "Walk them in front of your Militia",
		"who": "foreman", "say": "Rivet Brutes! Bullets bounce, boss. Rockets don't.", "home": ["ashen", 2]},
	"kettle": {"job": "Boiler on tracks. Smashes buildings, nothing else.", "tip": "Escort it to the walls, then let it knock",
		"who": "brann", "say": "The Kettle doesn't shoot. It knocks. Once.", "home": ["ashen", 2]},
	# ---- mission 4: Refugee Road
	"truck": {"job": "Carries the families. No gun. Two must arrive.", "tip": "Clear the road first, then move the trucks", "gw": "No weapon, heavy armour",
		"who": "vey", "say": "Every truck is forty people. Guard it like it's me.", "home": ["ashen", 3]},
	"l_groups": {"name": "Squads", "job": "Order a few units together: they become a squad.", "tip": "Tap a squad's chip to select, again to jump", "gw": "",
		"who": "foreman", "say": "Move them as one and they're a squad. Number one!", "home": ["ashen", 3], "glyph": "all"},
	# ---- mission 5: Ironpine Pass
	"flak": {"job": "Anti-air guns. Shreds aircraft, ignores the ground.", "tip": "Build two so they cover each other", "gw": "Hits aircraft only",
		"who": "foreman", "say": "Flak Nest! Gunships hate it. Tanks don't care.", "home": ["ashen", 4]},
	"howler": {"job": "Siege mortar. Lobs huge shells over hills.", "tip": "Keep it behind the wall, out of reach",
		"gw": "Good: buildings, splash · Cannot fire up close or at aircraft",
		"who": "brann", "say": "The Big Howler. Lobs a shell over any hill you like.", "home": ["ashen", 4]},
	"l_upgrades": {"name": "Upgrades", "job": "Select a building, tap UPGRADE. It keeps working.", "tip": "A Sledge Gun hits harder and reaches further", "gw": "",
		"who": "brann", "say": "Same Hammer, bigger head. Pay me and watch.", "home": ["ashen", 4], "glyph": "up"},
	# ---- mission 6: Silent Wires
	"scrapper": {"job": "Revives wrecks or strips them. Welds vehicles.", "tip": "Tap a fresh wreck to rebuild it for your side", "gw": "No weapon · Captures enemy buildings (used up)",
		"who": "brann", "say": "Nothing's dead till my Scrappers say so.", "home": ["ashen", 5]},
	"furnace": {"job": "Brann's hero tank. Arc cannon, huge armour.", "tip": "Lead with it: it soaks what others can't",
		"who": "brann", "say": "Slow to start, slower to stop. Just point her.", "home": ["ashen", 5]},
	# ---- mission 7: The Iron Saint
	"works": {"name": "Old Works", "job": "Pre-war foundry. Unlocks the Pact's best weapons.", "tip": "Build a Furnace first", "gw": "No weapon · Uses 60 power",
		"who": "brann", "say": "The Old Works. Don't touch anything that glows.", "home": ["ashen", 6]},
	"mast": {"job": "Builds aircraft. Needs the Old Works.", "tip": "Set its rally away from enemy flak", "gw": "No weapon",
		"who": "brann", "say": "A mast for the gyros. Mind your heads.", "home": ["ashen", 6]},
	"gyro": {"job": "Heavy gyrocopter with a cannon. Hits the ground.", "tip": "Send it ahead to look before the army moves",
		"who": "foreman", "say": "Gyro Hammers! Loud, slow, and they bite tanks.", "home": ["ashen", 6]},
	"arcc": {"job": "Heavy arc tank. Strong against almost all.", "tip": "Slow: escort it with Grenadiers",
		"who": "vey", "say": "Lightning on tracks. Point them at the Saint.", "home": ["ashen", 6]},
	"anvila": {"name": "Anvil Tank (arc coil)", "job": "Anvil with an arc coil. Chains between targets.", "tip": "Best into packed infantry",
		"who": "brann", "say": "Arc kit's done. Mind the hair on your arms.", "home": ["ashen", 6]},
	"pylon": {"job": "Arc tower. Deadly, but dark without power.", "tip": "Keep your Furnaces fed or it shuts off",
		"who": "brann", "say": "Pylons drink power. Cold Furnace, no lightning.", "home": ["ashen", 6]},
	# ---- mission 8: Embers
	"rift": {"job": "Superweapon. Charges 4 minutes, tears a hole.", "tip": "Select it, tap LAUNCH, then tap the target", "gw": "Hits everything in a wide circle",
		"who": "foreman", "say": "Rift's charged! Pick something big, boss.", "home": ["ashen", 7]},
	"jugg": {"name": "Foundry Juggernaut", "job": "A rolling foundry. Two big guns, side flamers.", "tip": "Only one at a time: keep it alive",
		"who": "brann", "say": "She's the whole foundry on tracks. Don't lose her.", "home": ["ashen", 7]},
	"zeppelin": {"job": "Slow airship. Drops firebombs on what's below.", "tip": "Clear their flak first, then send it",
		"who": "vey", "say": "The Zeppelin's up. Everybody look busy below it.", "home": ["ashen", 7]},
	# ================= campaign II: the Vanguard =================
	# ---- mission 1: Second Landfall
	"harrow": {"job": "Hero sniper. Her rail rifle outranges everything.", "tip": "Keep her behind the Troopers and let her pick",
		"who": "dace", "say": "Captain Harrow has the field. Follow her shots.", "home": ["vanguard", 0]},
	"rifle": {"job": "Line infantry. Steady, cheap, fires at aircraft too.", "tip": "Double-tap one to select them all",
		"who": "harrow", "say": "Troopers. Drilled, and they do not run.", "home": ["vanguard", 0]},
	"lancer": {"job": "Rocket soldier. Cracks vehicles, slow against men.", "tip": "Keep Troopers in front of them",
		"who": "harrow", "say": "Lancers for the armour. Screen them with rifles.", "home": ["vanguard", 0]},
	"buggy": {"job": "Fast hover scout with a shield. Crosses water.", "tip": "Scout over the river where tanks cannot go",
		"who": "van_hq", "say": "Hover Scout up. Rivers are roads to it.", "home": ["vanguard", 0]},
	"ranger": {"job": "Sniper. Cloaks when still, deadly to infantry.", "tip": "Park it and wait: it vanishes after 3 seconds",
		"who": "harrow", "say": "Rangers. Still as stone, then one shot.", "home": ["vanguard", 0]},
	"tank": {"job": "Main battle tank behind an Aegis shield.", "tip": "Pull it back a moment and the shield returns",
		"who": "dace", "say": "Wardens. Shield first, armour second. Lovely.", "home": ["vanguard", 0]},
	"k9": {"job": "War dog. Bites infantry, smells out the hidden.", "tip": "Run it ahead: it uncovers cloaked and buried units",
		"who": "van_hq", "say": "K9 Team deployed. Nothing hides from that nose.", "home": ["vanguard", 0]},
	"sigmast": {"job": "Sends Signal 8 tiles and adds 10 Command.", "tip": "Prefabs land only inside Signal: chain Masts out", "gw": "No weapon",
		"who": "van_hq", "say": "Mast up. Signal is green, Command is rising.", "home": ["vanguard", 0]},
	"drill": {"job": "Lands on a field and pumps aurite. No harvesters.", "tip": "It kills the field in time: sell it, drill another", "gw": "No weapon",
		"who": "dace", "say": "Deep Drill is down. The valley pays its own way.", "home": ["vanguard", 0]},
	"lz": {"job": "Dropships land vehicles and aircraft here.", "tip": "Select it to order: it flies in from the map edge", "gw": "No weapon",
		"who": "van_hq", "say": "Landing Zone marked. Orders arrive by air.", "home": ["vanguard", 0]},
	"sentry": {"job": "Automatic gun behind an Aegis shield.", "tip": "It needs Signal: lose the Mast and it goes dark",
		"who": "van_hq", "say": "Auto-Sentry online. It does not sleep.", "home": ["vanguard", 0]},
	"l_signal": {"name": "Signal", "job": "Buildings land and work only inside the blue rings.", "tip": "Outside Signal a building goes dark. Keep Masts alive", "gw": "",
		"who": "van_hq", "say": "Signal is the leash, Captain. Stay on it.", "home": ["vanguard", 0], "glyph": "info"},
	"l_aegis": {"name": "Aegis shields", "job": "A shield takes the hits first, then recharges.", "tip": "Six calm seconds bring it back: pull hurt units out", "gw": "",
		"who": "harrow", "say": "A shield is a loan. Step back and it is repaid.", "home": ["vanguard", 0], "glyph": "info"},
	# ---- mission 2: Night Wires
	"engineer": {"job": "Captures enemy buildings. Repairs your own.", "tip": "Tap an enemy building to take it. He is used up", "gw": "No weapon",
		"who": "harrow", "say": "Engineers. Guard them: they carry no rifle.", "home": ["vanguard", 1]},
	# ---- mission 3: Chainbreak
	"l_recover": {"name": "Recovery beacons", "job": "A lost vehicle leaves a beacon for 30 seconds.", "tip": "Hold a unit on it 5 seconds: 40% of the cost returns", "gw": "",
		"who": "van_hq", "say": "Beacon lit. Recover the wreck and we are paid.", "home": ["vanguard", 2], "glyph": "info"},
	# ---- mission 4: Glass Flats
	"jump": {"job": "Jet-pack infantry. Hops cliffs and rivers.", "tip": "Order a long move and they jump the gap",
		"who": "harrow", "say": "Jump Troopers. The map has no walls for them.", "home": ["vanguard", 3]},
	"railtank": {"job": "Rail gun on tracks. One slug pierces a whole line.", "tip": "Line the enemy up, then fire down the row",
		"who": "dace", "say": "Railtank. Line them up for me, Captain.", "home": ["vanguard", 3]},
	"spotter": {"job": "Unarmed drone. What it sees takes 25% more damage.", "tip": "Park it over the fight, away from flak", "gw": "No weapon",
		"who": "van_hq", "say": "Spotter up. Targets marked for all guns.", "home": ["vanguard", 3]},
	"hornets": {"job": "Three small attack drones. They chew up infantry.", "tip": "Send them at mortars and snipers",
		"who": "van_hq", "say": "Hornets away. Three of them, all angry.", "home": ["vanguard", 3]},
	"pk_strike": {"job": "One drop: two Warden Tanks and a Hover Scout.", "tip": "They land together, ready to push", "gw": "A delivery, not a unit",
		"who": "dace", "say": "A Strike Package. Order in bulk, Captain.", "home": ["vanguard", 3]},
	"pdl": {"job": "Laser turret. Burns aircraft and infantry.", "tip": "Place two so their fire overlaps",
		"who": "van_hq", "say": "Point Laser tracking. The sky is closed.", "home": ["vanguard", 3]},
	# ---- mission 5: Breakwater
	"skyhawk": {"job": "Rocket gunship. Hits the ground and the air.", "tip": "Pull it out when flak opens up",
		"who": "dace", "say": "Skyhawks. The Pact looks up and regrets it.", "home": ["vanguard", 4]},
	"walker": {"job": "Giant walker. Twin lasers, a huge shield. One only.", "tip": "Lead the push with it and let the shield soak",
		"who": "dace", "say": "The Sentinel walks. Everything else follows.", "home": ["vanguard", 4]},
	"hydrofoil": {"job": "Rail gunboat. Outranges everything from the water.", "tip": "It is set down on the nearest open water",
		"who": "van_hq", "say": "Hydrofoil on the river. Eight tiles of reach.", "home": ["vanguard", 4]},
	"pk_wing": {"job": "One drop: a Skyhawk, Hornets and a Spotter.", "tip": "A whole air group in one delivery", "gw": "A delivery, not a unit",
		"who": "dace", "say": "An Air Wing, boxed and delivered.", "home": ["vanguard", 4]},
	"bastion": {"job": "Heavy gun tower. Outranges every tank.", "tip": "Guard it from infantry: it fires slowly",
		"who": "van_hq", "say": "Bastion ranged in. Nine tiles, Marshal.", "home": ["vanguard", 4]},
	"uplink": {"job": "Link to the fleet. Unlocks rail, Walker and Dome.", "tip": "Protect it: without it the best gear stops coming", "gw": "No weapon",
		"who": "van_hq", "say": "Uplink live. The fleet is listening.", "home": ["vanguard", 4]},
	"dome": {"job": "Throws a shield over everything within 5 tiles.", "tip": "Put it in the middle of the base", "gw": "No weapon",
		"who": "van_hq", "say": "Dome is up. Let them knock.", "home": ["vanguard", 4]},
	# ---- mission 6: Three Spires
	"saint": {"job": "Dace's command tank. Huge armour, huge gun.", "tip": "Lead with it, but never alone",
		"who": "dace", "say": "My Saint. Try not to scratch her, Captain.", "home": ["vanguard", 5]},
	# ---- mission 8: Rift Breaker
	"skyfall": {"job": "Superweapon. Charges 4 minutes, hits anywhere.", "tip": "Select it, tap LAUNCH, then tap the target", "gw": "Hits everything in a wide circle",
		"who": "dace", "say": "Skyfall is ready. Choose well, Captain.", "home": ["vanguard", 7]},
	# ================= campaign III: the Hollow Choir =================
	# ---- mission 1: First Song
	"cantor": {"job": "Hero singer. Its song lifts every form near it.", "tip": "Keep Thralls round it, and keep it alive",
		"who": "choir_hq", "say": "The Cantor sings and we are more. Guard the voice.", "home": ["choir", 0]},
	"thrall": {"job": "Brood of three husks with shard throwers. Cheap.", "tip": "Select four and tap FUSE to make a Knot",
		"who": "choir_hq", "say": "We were miners once. Now we are many.", "home": ["choir", 0]},
	"sapper": {"job": "Tunnels unseen, then bursts. It is its own charge.", "tip": "Send it at buildings and tanks: it dies in the blast",
		"who": "choir_hq", "say": "One of us goes under. One of them stops.", "home": ["choir", 0]},
	"knot": {"job": "Four Thralls fused. Slow, huge, crushes what is near.", "tip": "Fuse spare Thralls before a hard fight",
		"who": "choir_hq", "say": "Four of us, closer than before.", "home": ["choir", 0]},
	"l_mutation": {"name": "Mutation", "job": "A form's third kill changes it for good.", "tip": "Keep your killers alive: crystal marks the changed", "gw": "",
		"who": "choir_hq", "say": "What kills, grows. Let it grow.", "home": ["choir", 0], "glyph": "up"},
	# ---- mission 2: Gardens of Glass
	"garden": {"job": "Earns aurite, ripens Pods, spreads the Hum.", "tip": "Root it beside aurite. Tap UPGRADE to age it", "gw": "No weapon",
		"who": "choir_hq", "say": "Plant us by the crystal. We will sing it awake.", "home": ["choir", 1]},
	"skitter": {"job": "Fast six-legged scout with a shard gun.", "tip": "Use it to find fields for new Gardens",
		"who": "choir_hq", "say": "Small, quick, hungry. It finds the way.", "home": ["choir", 1]},
	"burrow": {"job": "Tunnel mouth. Walk in one, come out of another.", "tip": "Dig one forward, then order the army into the first", "gw": "No weapon",
		"who": "choir_hq", "say": "The ground is ours. We walk under their walls.", "home": ["choir", 1]},
	"spire": {"job": "Crystal tower. Shreds infantry, weak on armour.", "tip": "It grows only inside the Hum (the green rings)",
		"who": "choir_hq", "say": "A spire to watch the dark for us.", "home": ["choir", 1]},
	"thorn": {"name": "Thornglass", "job": "Four pieces of crystal hedge. Cuts who leans on it.", "tip": "Tap the map four times to lay all four", "gw": "Cuts infantry beside it",
		"who": "choir_hq", "say": "Let them lean on our walls. Once.", "home": ["choir", 1]},
	"l_hum": {"name": "The Hum", "job": "Growths go only inside the green rings.", "tip": "In the Hum your forms heal and hurry", "gw": "",
		"who": "choir_hq", "say": "Inside the ring we mend. Outside we fade.", "home": ["choir", 1], "glyph": "info"},
	"l_pods": {"name": "Pods", "job": "Each Garden ripens a Pod every 15 seconds, holds 3.", "tip": "Every form hatches from a Pod: more Gardens, more army", "gw": "",
		"who": "choir_hq", "say": "A Pod, a body. No Pod, no body.", "home": ["choir", 1], "glyph": "all"},
	# ---- mission 3: Under the Wall
	"keener": {"job": "Its cry jams guns and drops shields for 4 seconds.", "tip": "Walk it into their tanks just as you attack", "gw": "Jams machines and guns · Weak weapon",
		"who": "choir_hq", "say": "It opens its throat and their engines forget.", "home": ["choir", 2]},
	"mantis": {"job": "Fast beast with spines. Kills vehicles.", "tip": "Needs a Bloom Garden. Send it at tanks, not soldiers",
		"who": "choir_hq", "say": "It was a mule once. It has grown since.", "home": ["choir", 2]},
	"wretch": {"job": "A risen soldier. Free, weak, withers outside the Hum.", "tip": "Throw them forward: they cost nothing",
		"who": "choir_hq", "say": "They came to burn us. Now they sing too.", "home": ["choir", 2]},
	"l_hollowing": {"name": "The Hollowing", "job": "Soldiers who die in the Hum rise as Wretches.", "tip": "Fight on your own crystal: it cuts them, too", "gw": "",
		"who": "choir_hq", "say": "Nothing that falls here is wasted.", "home": ["choir", 2], "glyph": "info"},
	# ---- mission 5: The Hum Below
	"geode": {"job": "Siege beast. Lobs geodes that leave shard fields.", "tip": "Keep it far back: it cannot fire up close",
		"who": "choir_hq", "say": "It throws pieces of us. They keep cutting.", "home": ["choir", 4]},
	"undertow": {"job": "Glass eel. Hides under water, tears boats apart.", "tip": "It surfaces in the nearest water. Still means hidden",
		"who": "choir_hq", "say": "The river is ours as well. Ask their boats.", "home": ["choir", 4]},
	"moth": {"job": "Flying glass drone. Fast eyes, a light sting.", "tip": "Scout with it and chase aircraft",
		"who": "choir_hq", "say": "It sees for all of us.", "home": ["choir", 4]},
	# ---- mission 7: Iron in the Garden
	"carillon": {"job": "Walking cathedral. Carries the Hum, tolls on infantry.", "tip": "Walk it forward and grow Spires beside it", "gw": "Its toll hits infantry only",
		"who": "choir_hq", "say": "Where it walks, we are home.", "home": ["choir", 6]},
	"chorus": {"job": "Superweapon. Charges 4 minutes, sings a storm.", "tip": "Select it, tap LAUNCH, then tap the target", "gw": "Hits everything in a wide circle, leaves shards",
		"who": "choir_hq", "say": "All of us at once. Choose where.", "home": ["choir", 6]},
	"deepmaw": {"job": "Huge burrowing beast. Its spines break armour.", "tip": "Lead with it: nothing else you have is this tough",
		"who": "choir_hq", "say": "It slept under the valley. It follows the song.", "home": ["choir", 6]},
}

## Enemy cards ("Know your enemy"): shown once, the first time that enemy type is in sight. They do not pause.
## Keyed by campaign, then type.
const ENEMY := {
	"ashen": {
		"rifle": {"name": "Vanguard Trooper", "text": "Same rifle as ours, blue coat. Pyros eat them.", "who": "foreman", "say": "Blue coats on the hill! Same rifles, worse manners."},
		"buggy": {"text": "Quick gun buggy. Lancers and Sentries stop it.", "who": "foreman", "say": "Buggies! Quick little things. Lancers, boss!"},
		"tank": {"text": "Main battle tank. Bullets bounce off. Use Lancers.", "who": "foreman", "say": "Tank! Rifles, back off. Lancers, forward!"},
		"skyhawk": {"text": "Flies over walls. Flak, rockets and rifles reach it.", "who": "foreman", "say": "Gunships! Cannons can't touch them. Flak!"},
		"railtank": {"text": "Rail gun tank. Its slug goes through a whole line.", "who": "foreman", "say": "Railtank! Don't stand in a row, boss!"},
		"ranger": {"text": "Vanguard sniper. Deadly to infantry, harmless to tanks.", "who": "vey", "say": "Sniper in the reeds! Send a bike, not a rifle."},
		"saint": {"text": "Dace's command tank. Huge armour, huge gun.", "who": "brann", "say": "That's the Saint. Lancers and Crawlers, all at once."},
		"harrow": {"text": "Vanguard hero sniper. Longest reach on the field.", "who": "vey", "say": "Harrow's on the cliffs. Send bikes, not rifles."},
		"bastion": {"text": "Heavy gun tower. Outranges your tanks.", "who": "foreman", "say": "Bastion! Howlers outrange it, boss."},
		"skyfall": {"text": "Missile battery. Charges, then hits anywhere.", "who": "foreman", "say": "Watch the Skyfall timer. When it's low, scatter!"},
	},
	"vanguard": {
		"militia": {"name": "Pact Militia", "text": "Cheap rifles in a crowd. Rangers thin them out.", "who": "harrow", "say": "Militia. Brave, badly drilled. Rangers, take them."},
		"pyro": {"text": "Flamer. Deadly up close, harmless at range.", "who": "harrow", "say": "Pyro! Drop him before he gets close."},
		"grenadier": {"text": "Lobs pipe bombs. Hurts infantry and buildings.", "who": "harrow", "say": "Grenadiers. Spread out and close in."},
		"raider": {"text": "Fast bike. Runs infantry down.", "who": "van_hq", "say": "Raider bikes. Lancers and Sentries stop them."},
		"boars": {"text": "War boars. They charge and knock soldiers flat.", "who": "harrow", "say": "Boars! Shoot them before they reach the line."},
		"brute": {"text": "Armoured giant. Rifles barely hurt him. Snipe him.", "who": "harrow", "say": "A Rivet Brute. Rangers, take the big one."},
		"hammer": {"text": "Short, fat base gun. Outrange it.", "who": "van_hq", "say": "Hammer Gun ahead. Stay outside its reach."},
		"scorpion": {"text": "Pact tank. Tough, slow, short reach. Keep your distance.", "who": "dace", "say": "Anvils. They hit hard and reach short. Keep back."},
		"kettle": {"text": "Rams buildings apart. Harmless to units.", "who": "van_hq", "say": "A Kettle! Stop it before it reaches the Masts."},
		"howler": {"text": "Siege mortar. Long reach, blind up close.", "who": "van_hq", "say": "Howler shelling us. Send a Hover Scout."},
		"scrapper": {"text": "Rebuilds wrecks for the Pact. Shoot it first.", "who": "harrow", "say": "Scrappers. Kill them or fight that tank twice."},
		"pylon": {"text": "Arc tower. Arcs drain Aegis shields twice as fast.", "who": "van_hq", "say": "Arc Pylon. Shields mean nothing to it. Rail it."},
		"arcc": {"text": "Heavy arc tank. Its arcs eat shields.", "who": "dace", "say": "Arc Crawler. Do not trust your shields."},
		"gyro": {"text": "Slow gyrocopter with a cannon.", "who": "van_hq", "say": "Gyro overhead. Point Lasers will have it."},
		"zeppelin": {"text": "Airship. Firebombs whatever is under it.", "who": "van_hq", "say": "Zeppelin inbound. Lasers up."},
		"vey": {"text": "Pact hero. Arc rifle, very hard to pin down.", "who": "dace", "say": "Kestrel Vey. I want her, Captain."},
		"furnace": {"text": "Brann's hero tank. Arc cannon, huge armour.", "who": "dace", "say": "Old Brann's Furnace. Rail guns, all of them."},
		"jugg": {"text": "A rolling foundry. Two big guns, side flamers.", "who": "dace", "say": "Juggernaut! Everything on it, now."},
		"rift": {"text": "Superweapon. Charges, then tears a hole anywhere.", "who": "dace", "say": "The Rift Engine is charging. Break it."},
	},
	"choir": {
		"rifle": {"name": "Vanguard Trooper", "text": "A soldier. The crystal cuts him, then he is ours.", "who": "choir_hq", "say": "They walk on us in boots. Let them."},
		"drill": {"text": "It pumps a field until the field dies. Break it.", "who": "choir_hq", "say": "It drinks the crystal dry. It kills us. Break it."},
		"sigmast": {"text": "Their buildings go dark without it.", "who": "choir_hq", "say": "Cut the mast and their machines sleep."},
		"sentry": {"text": "Shielded gun. A Keener's cry drops the shield.", "who": "choir_hq", "say": "It wears a shell of light. Sing at it."},
		"tank": {"text": "Shielded tank. Shards barely scratch it. Use Mantises.", "who": "choir_hq", "say": "Iron with a shell. Send the Mantis."},
		"ranger": {"text": "Hidden sniper. Skitters run him down.", "who": "choir_hq", "say": "One of them hides and takes us one by one."},
		"pdl": {"text": "Laser turret. Keep Glassmoths away from it.", "who": "choir_hq", "say": "Light that burns. The moths must not go near."},
		"bastion": {"text": "Long gun tower. Tunnel under its reach.", "who": "choir_hq", "say": "It reaches far. We go beneath."},
		"harrow": {"text": "Their sniper captain. She kills at any distance.", "who": "choir_hq", "say": "The quiet one. She never misses."},
		"saint": {"text": "Dace's command tank. Bring the Deepmaw.", "who": "choir_hq", "say": "Their iron saint. We have a saint of our own."},
		"militia": {"name": "Pact Militia", "text": "Many rifles, no armour. They die well in the Hum.", "who": "choir_hq", "say": "So many. So soon ours."},
		"pyro": {"text": "Fire shatters crystal. Kill him far from the Gardens.", "who": "choir_hq", "say": "Fire. We do not like fire."},
		"scorpion": {"text": "Slow Pact tank. A Burster ends it.", "who": "choir_hq", "say": "Slow iron. One of us goes under it."},
		"kettle": {"text": "Rams buildings. It is coming for the Gardens.", "who": "choir_hq", "say": "It knocks on Gardens. Do not let it knock."},
		"arcc": {"text": "Heavy arc tank. Arcs shatter crystal.", "who": "choir_hq", "say": "Lightning breaks us. Burst it from below."},
		"vey": {"text": "Pact hero with an arc rifle. Keep her off the Gardens.", "who": "choir_hq", "say": "The red one burns. Keep her from the Gardens."},
		"rift": {"text": "Their superweapon. It can erase a Garden.", "who": "choir_hq", "say": "They tear holes in the world. Stop the engine."},
	},
}

## Pointer lessons: steps shown one at a time, each waiting for the one before. A step:
##   hint (the banner by the pointer), say (a radio line, by the lesson's speaker), ptr (what the pointer rings),
##   done (what finishes it), when (optional: wait for this before showing the step), skip_if (a building type:
##   the step is skipped when the player already has one).
## ptr: {"hero"} own hero · {"unit": type} first own unit of a type · {"enemy"} nearest enemy in sight · {"ahead"} a spot
##   up the map from the hero · {"view"} the middle of the map view · {"ui": name} a HUD control (power, ready, place, sw) ·
##   {"item": "cat:type"} a build button (or the top-bar chip of the building that makes it, or the panel button while hidden) · {"bld": type} own building.
## done: {"ev": name, ...} an event (see Tutor.ev) · {"t": seconds} after a while.
const LESSONS := {
	"controls": {"who": "foreman", "steps": [
		{"hint": "Tap Vey to select her", "say": "Tap the lady with the goggles, boss.", "ptr": {"hero": true}, "done": {"ev": "select", "hero": true}},
		{"hint": "Tap the ground to move", "say": "Now tap where you want her. Simple!", "ptr": {"ahead": true}, "done": {"ev": "move"}},
		{"hint": "Hold, then drag over the squad to select it", "say": "Hold your finger, then drag. Grab the lot!", "ptr": {"unit": "militia"}, "done": {"ev": "box"}},
		{"hint": "Tap an enemy to attack", "say": "That's a Vanguard picket. Tap it. Hard.", "ptr": {"enemy": true}, "done": {"ev": "attack"}, "when": "enemy_seen"},
		{"hint": "Double-tap a unit to pick every one of its type", "say": "Double-tap a rifle, get all the rifles.", "ptr": {"unit": "militia"}, "done": {"ev": "dbl"}},
		{"hint": "Drag to look around, pinch to zoom", "say": "Drag the map to look about. Pinch for close-ups.", "ptr": {"view": true}, "done": {"ev": "cam"}},
	]},
	"base": {"who": "foreman", "steps": [
		{"hint": "Furnaces burn aurite to make power", "say": "See the power bar? Feed the Furnaces, keep it green.", "ptr": {"ui": "power"}, "done": {"t": 7.0}},
		{"hint": "Hearths house your army. Watch UNITS", "say": "Out of bunks, no more troops. Build a Hearth, boss.", "ptr": {"ui": "power"}, "done": {"t": 7.0}},
		{"hint": "Tap a building to start it", "say": "Tap the Workshop. Brann's lads do the rest.", "ptr": {"item": "bld:workshop"}, "done": {"ev": "order", "type": "workshop"}, "skip_if": "workshop"},
		{"hint": "When it is ready, drag it onto the map", "say": "It's ready! Drag it out where you want it.", "ptr": {"item": "bld:workshop"}, "done": {"ev": "placing"}, "when": "bld_ready", "skip_if": "workshop"},
		{"hint": "Tap it to build there", "say": "Tap it again to drop it. Bang. Workshop.", "ptr": {"ui": "place"}, "done": {"ev": "made", "type": "workshop"}, "skip_if": "workshop"},
		{"hint": "Select the Muster Hall, tap the map: rally", "say": "Pick the Muster Hall, tap the map. Recruits go there.", "ptr": {"bld": "muster"}, "done": {"ev": "rally"}},
		{"hint": "Hold a unit button to queue five", "say": "Hold the button to order five at once!", "ptr": {"item": "inf:militia"}, "done": {"ev": "queue5"}},
	]},
	"signal": {"who": "dace", "steps": [
		{"hint": "Blue rings are Signal. Prefabs land only inside", "say": "Signal is the leash, Captain. Stay on it.", "ptr": {"bld": "hq"}, "done": {"t": 7.0}, "when": "has:hq"},
		{"hint": "Tap the Signal Mast to order one", "say": "Order a Mast. It drops from orbit, ready-made.", "ptr": {"item": "bld:sigmast"}, "done": {"ev": "order", "type": "sigmast"}},
		{"hint": "When it is ready, drag it onto the map", "say": "", "ptr": {"item": "bld:sigmast"}, "done": {"ev": "placing"}, "when": "bld_ready"},
		{"hint": "Tap inside a blue ring to land it", "say": "Inside the ring. It lands in eight seconds.", "ptr": {"ui": "place"}, "done": {"ev": "made", "type": "sigmast"}},
		{"hint": "UNITS is Command. Every Mast adds ten", "say": "Every Mast is ten more seats at the table.", "ptr": {"ui": "cap"}, "done": {"t": 7.0}},
		{"hint": "Land a Deep Drill on the aurite field", "say": "No harvesters. The Drill sits on the ore and drinks.", "ptr": {"item": "bld:drill"}, "done": {"ev": "made", "type": "drill"}},
		{"hint": "Build a Landing Zone: vehicles fly in to it", "say": "A Landing Zone. The fleet does the rest.", "ptr": {"item": "bld:lz"}, "done": {"ev": "made", "type": "lz"}},
	]},
	"hum": {"who": "choir_hq", "steps": [
		{"hint": "The green ring is the Hum. Growths go inside it", "say": "Hear it? Inside the ring we mend.", "ptr": {"bld": "hq"}, "done": {"t": 7.0}},
		{"hint": "Tap the Garden to start one", "say": "A Garden first. Always a Garden first.", "ptr": {"item": "bld:garden"}, "done": {"ev": "order", "type": "garden"}},
		{"hint": "When it is ready, drag it onto the map", "say": "", "ptr": {"item": "bld:garden"}, "done": {"ev": "placing"}, "when": "bld_ready"},
		{"hint": "Root it beside the aurite, in the Hum or out of it", "say": "Beside the crystal. It needs to hear it.", "ptr": {"ui": "place"}, "done": {"ev": "made", "type": "garden"}},
		{"hint": "PODS: each Garden ripens one every 15 seconds", "say": "A Pod, a body. No Pod, no body.", "ptr": {"ui": "cap"}, "done": {"t": 8.0}},
		{"hint": "Hatch a brood of Thralls from a Pod", "say": "Open one. Let them out.", "ptr": {"item": "inf:thrall"}, "done": {"ev": "made", "type": "thrall"}},
		{"hint": "Select a Garden and tap UPGRADE to age it", "say": "Let it grow old. Old Gardens know more forms.", "ptr": {"bld": "garden"}, "done": {"t": 10.0}},
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
const LESSON_ONLY := ["hq", "power", "barracks", "kiln", "muster", "dropship"]
const DRILL_BONUS := 200
const MISSIONS := {
	"ashen": [
		{"lesson": "controls", "drills": [
			{"text": "Burn a picket with your Pyros", "check": {"ev": "kill", "by": "pyro"}, "ptr": "pyro"},
			{"text": "Let the Medic patch up Vey", "check": {"ev": "heal", "target": "vey"}, "ptr": "medic"}]},
		{"lesson": "base", "drills": [
			{"text": "Train two Grenadiers", "check": {"ev": "made", "type": "grenadier", "n": 2}},
			{"text": "Set a rally point", "check": {"ev": "rally"}}]},
		{"drills": [
			{"text": "Build a second Ore Crawler", "check": {"have": "crawler", "n": 2}},
			{"text": "Wipe out a buggy raid", "check": {"raid": true}}]},
		{"cards": ["l_groups"], "drills": [
			{"text": "Order squad 1, then call it with its chip", "check": {"ev": "group_recall", "i": 0}},
			{"text": "Bring all three trucks home", "check": {"arrived": 3}}]},
		{"cards": ["l_upgrades"], "drills": [
			{"text": "Shell a column with a Big Howler", "check": {"ev": "kill", "by": "howler"}},
			{"text": "Shoot down a gunship", "check": {"ev": "kill", "by": "flak", "air": true}},
			{"text": "Upgrade a Hammer Gun", "check": {"ev": "upgrade", "type": "hammer"}}]},
		{"drills": [
			{"text": "Revive a wreck with a Scrapper", "check": {"ev": "revive"}, "ptr": "scrapper"}]},
		{"drills": [
			{"text": "Find the Iron Saint with a Gyro Hammer", "check": {"spot": "saint", "by": "gyro"}},
			{"text": "Build an Arc Pylon", "check": {"ev": "made", "type": "pylon"}}]},
		{"lesson": "launch", "drills": [
			{"text": "Fire the Rift Engine", "check": {"ev": "launch"}}]},
	],
	"vanguard": [
		{"lesson": "signal", "cards": ["l_signal"], "drills": [
			{"text": "Take a shot with Captain Harrow", "check": {"ev": "kill", "by": "harrow"}, "ptr": "harrow"},
			{"text": "Land a Deep Drill on a field", "check": {"ev": "made", "type": "drill"}}]},
		{"cards": ["l_aegis"], "drills": [
			{"text": "Pick off a guard with a Ranger", "check": {"ev": "kill", "by": "ranger"}, "ptr": "ranger"}]},
		{"cards": ["l_recover"], "drills": [
			{"text": "Call squad 1 with its chip", "check": {"ev": "group_recall", "i": 0}}]},
		{"drills": [
			{"text": "Run two Deep Drills at once", "check": {"have": "drill", "n": 2}},
			{"text": "Fly in a Warden Tank", "check": {"ev": "made", "type": "tank"}}]},
		{"drills": [
			{"text": "Raise a Shield Dome", "check": {"ev": "made", "type": "dome"}},
			{"text": "Upgrade a Signal Mast", "check": {"ev": "upgrade", "type": "sigmast"}}]},
		{"drills": [
			{"text": "Kill with a Railtank", "check": {"ev": "kill", "by": "railtank"}}]},
		{"drills": [
			{"text": "Find Kestrel Vey with a Spotter Drone", "check": {"spot": "vey", "by": "spotter"}}]},
		{"lesson": "launch", "drills": [
			{"text": "Fire the Skyfall Battery", "check": {"ev": "launch"}}]},
	],
	"choir": [
		{"cards": ["l_mutation"], "drills": [
			{"text": "Break a drill with a Burster", "check": {"ev": "kill", "by": "sapper"}, "ptr": "sapper"},
			{"text": "Fuse four Thralls into a Knot", "check": {"have": "knot", "n": 1}, "ptr": "thrall"}]},
		{"lesson": "hum", "cards": ["l_hum", "l_pods"], "drills": [
			{"text": "Grow three Gardens", "check": {"have": "garden", "n": 3}},
			{"text": "Age a Garden into a Bloom", "check": {"ev": "upgrade", "type": "garden"}}]},
		{"cards": ["l_hollowing"], "drills": [
			{"text": "Raise a Wretch from a fallen soldier", "check": {"have": "wretch", "n": 1}},
			{"text": "Dig a second Burrow", "check": {"have": "burrow", "n": 2}}]},
		{"drills": [
			{"text": "Kill with the Cantor", "check": {"ev": "kill", "by": "cantor"}, "ptr": "cantor"}]},
		{"drills": [
			{"text": "Shell a column with a Geode Lobber", "check": {"ev": "kill", "by": "geode"}},
			{"text": "Hatch two Glassmoths", "check": {"have": "moth", "n": 2}}]},
		{"drills": [
			{"text": "Fuse a Knot for the push", "check": {"have": "knot", "n": 1}}]},
		{"drills": [
			{"text": "Hatch a Carillon", "check": {"have": "carillon", "n": 1}},
			{"text": "Find the Iron Saint with a Glassmoth", "check": {"spot": "saint", "by": "moth"}}]},
		{"lesson": "launch", "drills": [
			{"text": "Sing the Chorus Well", "check": {"ev": "launch"}}]},
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
## The enemy card of a type: the one written for this campaign, else the first campaign that has one ({} when none).
static func enemy_card(type: String, camp := "") -> Dictionary:
	if ENEMY.has(camp) and ENEMY[camp].has(type): return ENEMY[camp][type]
	for c in ENEMY:
		if ENEMY[c].has(type): return ENEMY[c][type]
	return {}

## Every enemy type that has a card, each once, in campaign order.
static func enemy_types() -> Array:
	var out: Array = []
	for c in ENEMY:
		for t in ENEMY[c]:
			if not out.has(t): out.append(t)
	return out

## The army a type belongs to (for the colours of its card).
static func fac_of(type: String) -> String:
	var f: String = D.def_of(type).get("fac", "")
	return f if f != "" else "vanguard"

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

