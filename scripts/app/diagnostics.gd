## 可关闭诊断显示（4 Hz 更新）+ 轻量逐帧采样缓冲（供性能路线写盘）。
extends PanelContainer

var info_label: Label
var sampler_enabled := false

var _update_accum := 0.0
var _frame_deltas := PackedFloat32Array()
var _draw_call_peak := 0
var _map_node_count := 0
var _extra_info := ""


func _init() -> void:
	custom_minimum_size = Vector2(360, 0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.08, 0.11, 0.82)
	style.border_color = Color(0.35, 0.77, 0.76, 0.6)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.content_margin_left = 10.0
	style.content_margin_right = 10.0
	style.content_margin_top = 6.0
	style.content_margin_bottom = 6.0
	add_theme_stylebox_override("panel", style)
	info_label = Label.new()
	info_label.add_theme_font_size_override("font_size", 13)
	add_child(info_label)
	visible = false


func set_map_node_count(count: int) -> void:
	_map_node_count = count


func set_extra_info(text: String) -> void:
	_extra_info = text


func begin_sampling() -> void:
	_frame_deltas = PackedFloat32Array()
	_draw_call_peak = 0
	sampler_enabled = true


func end_sampling() -> Dictionary:
	sampler_enabled = false
	var deltas := _frame_deltas
	_frame_deltas = PackedFloat32Array()
	var stats := {
		"samples": deltas.size(),
		"avg_fps": 0.0, "p50_ms": 0.0, "p95_ms": 0.0, "p99_ms": 0.0,
		"stutter_over_100ms": 0, "draw_call_peak": _draw_call_peak,
	}
	if deltas.size() < 10:
		return stats
	var total := 0.0
	var stutter := 0
	for d in deltas:
		total += d
		if d > 0.1:
			stutter += 1
	var sorted := deltas.duplicate()
	sorted.sort()
	stats["avg_fps"] = deltas.size() / total if total > 0.0 else 0.0
	stats["p50_ms"] = sorted[int(sorted.size() * 0.50)]
	stats["p95_ms"] = sorted[int(mini(sorted.size() - 1, int(sorted.size() * 0.95)))]
	stats["p99_ms"] = sorted[int(mini(sorted.size() - 1, int(sorted.size() * 0.99)))]
	stats["stutter_over_100ms"] = stutter
	return stats


func get_renderer_name() -> String:
	if RenderingServer.has_method("get_current_rendering_method"):
		return str(RenderingServer.call("get_current_rendering_method"))
	return "unknown"


func get_adapter_name() -> String:
	if RenderingServer.has_method("get_video_adapter_name"):
		return str(RenderingServer.call("get_video_adapter_name"))
	return "unknown"


func _process(delta: float) -> void:
	if sampler_enabled:
		_frame_deltas.append(delta)
		var dc := int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
		if dc > _draw_call_peak:
			_draw_call_peak = dc
	_update_accum += delta
	if _update_accum < 0.25 or not visible:
		return
	_update_accum = 0.0
	var fps := Engine.get_frames_per_second()
	var dc := int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	var prim := int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
	var video_mem := Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / (1024.0 * 1024.0)
	var static_mem := Performance.get_monitor(Performance.MEMORY_STATIC) / (1024.0 * 1024.0)
	var nodes := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	info_label.text = "FPS %d | 绘制 %d | 三角 %dk | 节点 %d (地图 %d)\n显存(引擎估) %.0f MiB | 静态内存 %.0f MiB\n渲染器 %s | %s%s" % [
		fps, dc, prim / 1000, nodes, _map_node_count, video_mem, static_mem,
		get_renderer_name(), get_adapter_name(),
		("\n" + _extra_info) if not _extra_info.is_empty() else "",
	]
