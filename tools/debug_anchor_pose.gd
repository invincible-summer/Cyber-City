## 一次性诊断：打印室内图 4 锚点 Marker 的实际前向/俯仰（排查 gallery_view 取景偏差）。
extends SceneTree


func _init() -> void:
	var ps: PackedScene = load("res://maps/m01_repair_interior/map.tscn")
	if ps == null:
		push_error("map.tscn 加载失败")
		quit(1)
		return
	var root := ps.instantiate()
	root.process_mode = Node.PROCESS_MODE_DISABLED
	get_root().add_child(root)
	var anchors := root.get_node_or_null("CameraAnchors")
	if anchors == null:
		push_error("无 CameraAnchors")
		quit(1)
		return
	var spec: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(
		"res://maps/m01_repair_interior/generated/interior_spec.json"))
	for k in ["entry_view", "workbench_view", "gallery_view", "dining_view"]:
		var m: Marker3D = anchors.get_node_or_null(NodePath(k)) as Marker3D
		if m == null:
			print(k, ": MISSING")
			continue
		var fwd: Vector3 = -m.transform.basis.z
		var pitch_deg: float = rad_to_deg(asin(clampf(fwd.y, -1.0, 1.0)))
		var spec_a: Dictionary = spec["anchors"][k]
		var want: Vector3 = (Vector3(spec_a["look"][0], spec_a["look"][1], spec_a["look"][2])
			- Vector3(spec_a["pos"][0], spec_a["pos"][1], spec_a["pos"][2])).normalized()
		var want_deg: float = rad_to_deg(asin(clampf(want.y, -1.0, 1.0)))
		print("%s pos=%s fwd=%s pitch=%.2f° | 期望 pitch=%.2f° %s"
			% [k, m.transform.origin.round(), fwd.round(), pitch_deg, want_deg,
			"OK" if absf(pitch_deg - want_deg) < 0.5 else "MISMATCH"])
	root.queue_free()
	quit(0)
