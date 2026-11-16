class_name SaveData
extends RefCounted
## The player's save: one versioned JSON file in user://.
##
## Every field has a default in DEFAULTS, so an older or partial file loads fine. When a field's
## meaning changes, bump VERSION and add a step to _migrate() that upgrades older files; never
## reuse a field name for something else. Written to a temporary file first, then renamed, so a
## crash mid-write never leaves a broken save.

const VERSION := 1
const DEFAULTS := {
	"best": 0, ## best score in the endless mode
	"runs": 0, ## runs finished
	"sparks": 0, ## sparks collected, all time (the future currency)
	"settings": {"sound": false, "vibration": true},
}

var path := "user://save.json"
var data: Dictionary = {}


func _init(path_in := "user://save.json") -> void:
	path = path_in
	data = DEFAULTS.duplicate(true)


func load_file() -> void:
	data = DEFAULTS.duplicate(true)
	if not FileAccess.file_exists(path):
		return
	var text := FileAccess.get_file_as_string(path)
	var json := JSON.new()
	var parsed: Variant = json.data if json.parse(text) == OK else null
	if parsed is not Dictionary:
		push_warning("Save file %s is unreadable; starting fresh" % path)
		return
	var loaded: Dictionary = _migrate(parsed)
	for key in loaded:
		if key == "settings" and loaded[key] is Dictionary:
			data.settings.merge(loaded[key], true)
		elif key in data:
			data[key] = loaded[key]
	# JSON numbers come back as floats
	for key in ["best", "runs", "sparks"]:
		data[key] = int(data[key])


func save_file() -> bool:
	var out := data.duplicate(true)
	out["version"] = VERSION
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		push_warning("Could not write %s" % tmp)
		return false
	f.store_string(JSON.stringify(out, "\t"))
	f.close()
	return DirAccess.rename_absolute(tmp, path) == OK


## Upgrades an older save to the current VERSION, one version at a time.
static func _migrate(d: Dictionary) -> Dictionary:
	var v := int(d.get("version", 1))
	# Example for the next change:
	# if v < 2:
	# 	d["new_field"] = ...
	# 	v = 2
	d["version"] = v
	return d


func get_setting(key: String) -> Variant:
	return data.settings.get(key, DEFAULTS.settings.get(key))


func set_setting(key: String, value: Variant) -> void:
	data.settings[key] = value
