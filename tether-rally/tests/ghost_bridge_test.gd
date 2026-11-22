extends SceneTree
# Ghosts stay on the bridge (Guillaume, 2026-11-22: "the ghosts jump on and off the bridges").
# A ghost replays positions only, and the 3D view finds its height on the road from them
# (WorldView.ghost_road, following on from last frame's segment). On every track, a ghost driving
# a whole lap from the start line, anywhere across the road, must sit at the height of the road
# it is really on: up on the deck over a bridge, down on the lane below under it. The nearest
# bit of road overall flips between the two where the road crosses itself.
const TrackData = preload("res://scripts/track.gd")
const Defs = preload("res://scripts/track_defs.gd")
const WorldView = preload("res://scripts/world_view.gd")

func _initialize() -> void:
	var bad := 0
	var bridges := 0
	for d in Defs.TRACKS:
		var tr := TrackData.new(d, "standard")
		bridges += tr.bridges.size()
		for off in [-0.7, -0.35, 0.0, 0.35, 0.7]:
			var hint := 0  # as in the game: a ghost's lap starts on the start line
			var wrong := 0
			var first := -1.0
			var sv := 0.0
			while sv < tr.L:  # samples about as far apart as a fast ghost's 30-a-second trace
				var q := tr.point_at(sv)
				var p: Vector2 = q["pos"] + TrackData.perp(q["dir"]) * off * TrackData.HW
				var gr := WorldView.ghost_road(tr, p, hint)
				hint = gr["seg"]
				if absf(float(gr["h"]) - tr.height_at(sv)) > TrackData.BRIDGE_H * 0.5:
					wrong += 1
					if first < 0.0:
						first = sv
				sv += 30.0
			if wrong:
				bad += 1
				printerr("%s: ghost %+.0f%% across the road: %d samples at the wrong height, first at s=%.0f (%s)" % [d["name"], off * 100.0, wrong, first, tr.point_at(first)["pos"]])
	if bridges == 0:
		bad += 1
		printerr("no bridges found on any track")
	printerr("bridges on the tracks: %d, failures: %d" % [bridges, bad])
	quit(1 if bad else 0)
