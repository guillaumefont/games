class_name Ent
extends RefCounted
## One unit ("u") or building ("b"). Positions are in world pixels (32 per tile), like the web version.

var id := 0
var kind := "u"
var type := ""
var team := 0
var d: Dictionary
var x := 0.0
var y := 0.0
var hp := 0.0
var max_hp := 0.0
var alive := true
var sel := false
var r := 6.0
var cd := 0.0
var flash := 0.0
var hit_t := 0.0
var scan := 0.0
var target: Ent = null
var tang := 0.0

# buildings
var tx := 0
var ty := 0
var w := 1
var h := 1
var rally = null  # Vector2 or null
var seen := false
var smoke_t := 0.0
var born := 0.0
var repairing := false
var rp_t := 0.0
var busy := false
var ch := 0.0
var rdy := false
var end_kind := ""  # "sell" or "die": the view plays a dismantle or collapse before dropping the model
var end_t := 0.0
var out_t := -9.0  # last time a unit rolled out (factory door)
var unload_t := -9.0  # last time a harvester unloaded here (refinery conveyor)
var lv := 1            # 2 once upgraded (d is then D.BLD2[type])
var upg := -1.0        # upgrade progress 0..1 while upgrading, -1 otherwise
var upaid := 0.0       # aurite paid so far into the running upgrade
var up_t := -9.0       # when the last upgrade finished (the view plays a reveal)

# units
var ang := 0.0
var path: Array = []  # Array of Vector2i
var order := "none"
var auto := false
var guard = null  # Vector2 or null
var dest = null  # Vector2i or null
var rp := 0.0
var load := 0.0
var hs := ""
var it := 0.0
var mt := 0.0
var moving := false
var stuck_t := 0.0
var stuck := 0
var lx := 0.0
var ly := 0.0
var pref := -1
var ref: Ent = null
var retry := 0
var ot := -1
var fspd := 0.0
var esc: Array = []
var ecx = null
var ecy = null
var ht: Ent = null
var path_len := 0.0
var los_t := 0.0
var los_ok := true
var los_of: Ent = null
var dump := 0.0  # aurite delivered in the current unload
var tag := ""          # mission tag: "vip", "hero", a post tag such as "guns"
var captive := false   # a prisoner: does nothing, cannot be hurt or selected until a friendly unit reaches it
var post := false      # holds its position: the AI never pulls it into an attack wave
var face = null  # Vector2 facing to adopt when the move ends (formation drag)
# Hollow Choir
var under := false     # burrowed (a moving sapper, or a unit in a tunnel): cannot be seen by the enemy, targeted or hurt
var intun := 0.0       # seconds left travelling through a tunnel (hidden, frozen at the entrance)
var tun = null         # tunnel plan {a, b, dest, order}: walk to burrow a, come out of burrow b, go on to dest
var aura_t := 0.0      # inside a Cantor's aura for this long: fires faster, mends slowly
var gt := 0.0          # crystal garden: time since the last harvest pulse
# Ashen Pact
var stun := 0.0        # knocked down (a boar charge, a Ram Bike): cannot move or fire
var fired_t := -99.0   # when it last fired (a boar charges again after resting)
var ram_t := -99.0     # Ram Bike: when it may ram again
var cd2 := 0.0         # second weapon cooldown (the Juggernaut's side flamers)
var cold := false      # a Furnace with nothing to burn: makes no power
var wk = null          # Scrapper: the wreck it is working on
var wk_t := 0.0        # Scrapper: seconds spent on that wreck
# Vanguard
var sh := 0.0          # Aegis shield left (soaks damage before hp)
var sh_max := 0.0
var sh_t := -99.0      # when the shield was last hit (it comes back after a rest)
var dark := false      # a building outside Signal: does nothing until a Mast covers it again
var cloak := false     # a Ranger standing still: unseen until something sniffs it out or it fires
var still_t := 0.0     # seconds standing still without firing
var reveal_t := -99.0  # sniffed out (by a K9) until this time: can be seen and shot even cloaked or burrowed
var mark_t := -99.0    # spotted by a drone until this time: takes more damage
var jump_t := 0.0      # Jump Trooper: when it may jump again
var hop = null         # a jump in flight: {x0, y0, x1, y1, t, d}
var cargo: Array = []  # dropship: unit types on board
var paid := 0.0        # dropship: what the cargo cost
var lz: Ent = null     # dropship: the Landing Zone it is flying to
var leaving := false   # dropship: cargo set down, flying off the map
var pump_t := 0.0      # Deep Drill: time since the last pump
var dry := false       # Deep Drill: nothing left to pump
