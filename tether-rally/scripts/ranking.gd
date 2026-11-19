# Special Stages ranking (Guillaume, 2026-11-18): a Special Stage is about time and rank, never
# medals. Each track has one board of best laps (Standard layout), and a player's place is shown
# against the world first. Narrower boards (continent, country, zip code) open on their own once
# enough players share the player's region: see OPEN_AT and shown_scopes().
#
# The board server is `server/` (a Cloudflare Worker): it places a player from their connection
# (continent, country, postal code), keeps one best time per player and board, and answers with
# the player's rank and the board size in every scope. The game only sends its own best lap.
# While URL is empty (no server deployed yet) nothing is sent and ranks read "offline".
#
# Everything a menu shows comes from static functions over the cached reply (rank_lines(),
# card_line()), so headless tests can check them without a network.
extends RefCounted

const Records = preload("res://scripts/records.gd")

# the deployed Worker, no trailing slash, e.g. "https://tether-boards.<account>.workers.dev"
const URL := ""
const PATH := "user://ranking.cfg"
const TIMEOUT := 8.0

# widest first; the world board is always shown
const SCOPES := ["world", "continent", "country", "zip"]
# a narrower board opens once the player's own region has at least this many players on it
const OPEN_AT := { "continent": 200, "country": 100, "zip": 25 }

static var _cfg: ConfigFile
static var _url_override := ""   # tests point this at a fake server; "" uses URL

static func _load() -> ConfigFile:
	if _cfg == null:
		_cfg = ConfigFile.new()
		_cfg.load(PATH)
	return _cfg

static func _save() -> void:
	_load().save(PATH)

static func base_url() -> String:
	return _url_override if _url_override != "" else URL

static func online() -> bool:
	return base_url() != ""

# a random id made once per install (no account, no name): the server keys best times by it
static func player_id() -> String:
	var id := String(_load().get_value("player", "id", ""))
	if id.length() != 32:
		var c := Crypto.new()
		id = c.generate_random_bytes(16).hex_encode()
		_cfg.set_value("player", "id", id)
		_save()
	return id

# one board per track and layout version: a layout bump starts every board again
static func board(track_name: String) -> String:
	return "%d/%s" % [Records.LAYOUT_VERSION, track_name]

# ---------------------------------------------------------------- cached replies
# The last reply for a board: { "best": float, "ranks": { scope: { rank, total, name } } }
static func cached(track_name: String) -> Dictionary:
	var v = _load().get_value("boards", board(track_name), {})
	return v if v is Dictionary else {}

static func store(track_name: String, reply: Dictionary) -> void:
	var clean := parse(reply)
	if clean.is_empty():
		return
	_load().set_value("boards", board(track_name), clean)
	_save()

# a server reply, checked: anything malformed is dropped rather than shown
static func parse(reply) -> Dictionary:
	if not reply is Dictionary or not reply.get("ranks") is Dictionary:
		return {}
	var ranks := {}
	for s in SCOPES:
		var r = reply["ranks"].get(s)
		if not r is Dictionary:
			continue
		var rank := int(r.get("rank", 0))
		var total := int(r.get("total", 0))
		if rank < 1 or total < rank:
			continue
		ranks[s] = { "rank": rank, "total": total, "name": String(r.get("name", "")) }
	if not ranks.has("world"):
		return {}
	return { "best": float(reply.get("best", -1.0)), "ranks": ranks }

# the scopes to show, widest first: the world, then the narrowest region with enough players
# (Guillaume: "start with a world ranking, lower the bar as users pour in")
static func shown_scopes(ranks: Dictionary) -> Array:
	if not ranks.has("world"):
		return []
	var out := ["world"]
	for k in range(SCOPES.size() - 1, 0, -1):
		var s: String = SCOPES[k]
		var r = ranks.get(s)
		if r is Dictionary and String(r.get("name", "")) != "" and int(r.get("total", 0)) >= int(OPEN_AT[s]):
			out.append(s)
			break
	return out

static func scope_name(scope: String, r: Dictionary) -> String:
	if scope == "world":
		return "World"
	return String(r.get("name", scope.capitalize()))

# 12345 -> "12,345"
static func num(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if n < 0 else "") + s + out

# the rows a page shows: [[label, "#rank of total"], ...], widest first; empty with no rank yet
static func rank_lines(reply: Dictionary) -> Array:
	var ranks: Dictionary = reply.get("ranks", {})
	var out := []
	for s in shown_scopes(ranks):
		var r: Dictionary = ranks[s]
		out.append([scope_name(s, r), "#%s of %s" % [num(r["rank"]), num(r["total"])]])
	return out

# a lap time as the menus write it, 0:12.34 (same as UI.fmt2: menu.gd can't preload ui.gd)
static func fmt2(t: float) -> String:
	t = snappedf(t, 0.01)
	var m := int(t / 60.0)
	var s := t - m * 60.0
	return "%d:%s%.2f" % [m, "0" if s < 9.995 else "", s]

# the short line under a Special Stage card's name
static func card_line(best: float, reply: Dictionary) -> String:
	if best <= 0.0:
		return "No time yet"
	var line := "Best %s" % fmt2(best)
	var ranks: Dictionary = reply.get("ranks", {})
	var sc := shown_scopes(ranks)
	if not sc.is_empty():
		var s: String = sc[-1]
		line += "  ·  %s #%s" % [scope_name(s, ranks[s]), num(ranks[s]["rank"])]
	return line

# a cached rank is only good for the best time it was given for
static func fresh(track_name: String, best: float) -> Dictionary:
	var c := cached(track_name)
	if c.is_empty() or best <= 0.0 or absf(float(c.get("best", -1.0)) - best) > 0.0005:
		return {}
	return c

# ---------------------------------------------------------------- network
# Send a best lap (submit) or ask for the current rank (fetch). `done` gets the checked reply,
# or {} when offline or on any error. `owner` is any node in the tree (HTTPRequest needs one).
static func submit(owner: Node, track_name: String, best: float, done: Callable = Callable()) -> void:
	var body := JSON.stringify({ "player": player_id(), "time": snappedf(best, 0.001) })
	_request(owner, track_name, HTTPClient.METHOD_POST, "", body, done)

static func fetch(owner: Node, track_name: String, done: Callable = Callable()) -> void:
	_request(owner, track_name, HTTPClient.METHOD_GET, "?player=" + player_id(), "", done)

static func _request(owner: Node, track_name: String, method: int, query: String, body: String, done: Callable) -> void:
	if not online() or owner == null or not owner.is_inside_tree():
		if done.is_valid():
			done.call({})
		return
	var req := HTTPRequest.new()
	req.timeout = TIMEOUT
	owner.add_child(req)
	var url := "%s/v1/boards/%s%s" % [base_url(), board(track_name).uri_encode(), query]
	req.request_completed.connect(func(result: int, code: int, _h: PackedStringArray, data: PackedByteArray):
		req.queue_free()
		var reply := {}
		if result == HTTPRequest.RESULT_SUCCESS and code == 200:
			reply = parse(JSON.parse_string(data.get_string_from_utf8()))
		if not reply.is_empty():
			store(track_name, reply)
		if done.is_valid():
			done.call(reply))
	var err := req.request(url, ["Content-Type: application/json"], method, body)
	if err != OK:
		req.queue_free()
		if done.is_valid():
			done.call({})

# Settings > Reset progress: a new id, so the old best times stay with the old one
static func reset() -> void:
	_cfg = ConfigFile.new()
	_save()
