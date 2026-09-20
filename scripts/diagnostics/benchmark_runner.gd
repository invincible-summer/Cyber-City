## 基准运行器（chapter1-1 §8.2 BenchmarkRunner 合同）。
## 采样：单调实际时钟（Time.get_ticks_usec）逐帧记录；分位数 nearest-rank；
## 预热/稳态分段标记；正常 capped 运行保持节流，采样期失焦/最小化即中止并标记无效。
extends Node

signal benchmark_started(run_id: String)
signal benchmark_completed(run_id: String, output_directory: String)
signal benchmark_aborted(run_id: String, reason: String)

const OUTPUT_ROOT := "user://benchmarks"
const SUMMARY_CSV := "user://benchmarks/summary.csv"

const CSV_HEADER := "run_id,map_id,content_revision,route_id,profile_id,mode,valid,invalid_reason,engine_version,build_type,renderer,gpu_name,cpu_name,system_ram_mib,window_width,window_height,render_scale,frame_cap,vsync_mode,occlusion_enabled,sample_count,elapsed_seconds,average_fps,p50_ms,p95_ms,p99_ms,stutters_over_100ms,draw_calls_peak,visible_primitives_peak,map_node_count,process_working_set_mib_peak,process_private_bytes_mib_peak,engine_video_memory_mib_peak,os_gpu_memory_mib_peak,cpu_frame_ms_median,gpu_frame_ms_median,resource_load_ms,activation_ms,notes"

var _guard: ActivityGuard = null
var _map_manager = null
var _quality = null
var _camera = null
var _main = null                       # 组合根（失焦节流的正常执行者）

var _running := false
var _run_id := ""
var _config: Dictionary = {}
var _token: int = 0
var _phase := ""                       # warmup / steady
var _elapsed := 0.0
var _last_us := 0
var _start_us := 0
var _samples: Array = []               # {sample_index,timestamp_us,frame_interval_ms,phase,segment_id}
var _draw_call_peak := 0
var _primitives_peak := 0
var _video_mem_peak := 0.0
var _saved_quality: Dictionary = {}
var _saved_ambient: Dictionary = {}
var _saved_camera_pose: CameraPose = null
var _saved_vsync: DisplayServer.VSyncMode = DisplayServer.VSYNC_ENABLED
var _saved_max_fps := 30
var _invalid_reason := ""


func setup(guard: ActivityGuard, map_manager, quality, camera, main = null) -> void:
	_guard = guard
	_map_manager = map_manager
	_quality = quality
	_camera = camera
	_main = main


func is_running() -> bool:
	return _running


func get_run_status() -> Dictionary:
	return {
		"running": _running,
		"run_id": _run_id,
		"phase": _phase,
		"elapsed_seconds": _elapsed,
		"sample_count": _samples.size(),
		"invalid_reason": _invalid_reason,
	}


## 校验并受理一次基准。config 见 §8.2 表格。
func start_run(config: Dictionary) -> Error:
	if _running:
		return ERR_BUSY
	if _map_manager == null or _quality == null or _camera == null:
		return ERR_UNCONFIGURED
	if _map_manager.get_state_snapshot().get("state", "") != "READY":
		return ERR_INVALID_PARAMETER  # 地图必须 READY
	var err := _validate_config(config)
	if err != OK:
		return err
	if DisplayServer.get_name() == "headless":
		push_error("BenchmarkRunner: headless 环境不提供真实渲染结果")
		return ERR_UNAVAILABLE
	var token := 0
	if _guard != null:
		token = _guard.try_begin(ActivityGuard.KIND_BENCHMARK)
		if token == 0:
			return ERR_BUSY
	_token = token
	_config = config.duplicate(true)
	_run_id = str(_config["run_id"])
	_invalid_reason = ""
	_samples = []
	_draw_call_peak = 0
	_primitives_peak = 0
	_video_mem_peak = 0.0
	_elapsed = 0.0
	_phase = "warmup"
	# 快照用户设置、相机和环境状态；禁用人工相机输入
	_saved_quality = _quality.capture_runtime_state()
	_saved_camera_pose = _camera.get_pose()
	var mm_state: Dictionary = _map_manager.get_map_ambient_state()
	_saved_ambient = mm_state
	_camera.set_input_enabled(false)
	if _main != null:
		_main.set_automation_measure(true)  # 测量期间主循环不改节流（由本类负责失焦中止）
	_quality.set_profile(StringName(str(_config["profile_id"])), false)
	if str(_config.get("mode", "capped")) == "headroom":
		_saved_vsync = DisplayServer.window_get_vsync_mode()
		_saved_max_fps = Engine.max_fps
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		Engine.max_fps = 0
	var occ := str(_config.get("occlusion_override", "default"))
	var vp := get_viewport()
	if occ == "on":
		vp.use_occlusion_culling = true
	elif occ == "off":
		vp.use_occlusion_culling = false
	_start_us = Time.get_ticks_usec()
	_last_us = _start_us
	_running = true
	set_process(true)
	benchmark_started.emit(_run_id)
	return OK


func abort_run(reason: String) -> void:
	if not _running:
		return
	_invalid_reason = reason if not reason.is_empty() else "aborted"
	_finish(true)


func _validate_config(config: Dictionary) -> Error:
	if int(config.get("schema_version", 0)) != 1:
		push_error("BenchmarkRunner: schema_version 必须为 1")
		return ERR_INVALID_PARAMETER
	var run_id := str(config.get("run_id", ""))
	if run_id.is_empty():
		push_error("BenchmarkRunner: run_id 不能为空")
		return ERR_INVALID_PARAMETER
	var profile_id := str(config.get("profile_id", ""))
	if profile_id != "eco" and profile_id != "balanced":
		return ERR_INVALID_PARAMETER
	var route_id := str(config.get("route_id", ""))
	if not PerfRoutes.ROUTES.has(route_id):
		return ERR_INVALID_PARAMETER
	var mode := str(config.get("mode", "capped"))
	if mode != "capped" and mode != "headroom":
		return ERR_INVALID_PARAMETER
	var duration := float(config.get("duration_seconds", 60.0))
	if not is_finite(duration):
		return ERR_INVALID_PARAMETER
	if mode == "capped" and absf(duration - 60.0) > 0.001:
		push_error("BenchmarkRunner: 正常路线 duration_seconds 必须为 60")
		return ERR_INVALID_PARAMETER
	if mode == "headroom" and (duration < 1.0 or duration > 60.0):
		return ERR_INVALID_PARAMETER
	var warmup := float(config.get("warmup_seconds", 15.0))
	if not is_finite(warmup) or warmup < 0.0 or warmup > 30.0:
		return ERR_INVALID_PARAMETER
	var occ := str(config.get("occlusion_override", "default"))
	if occ != "default" and occ != "on" and occ != "off":
		return ERR_INVALID_PARAMETER
	var out_dir := str(config.get("output_directory", ""))
	if not out_dir.begins_with(OUTPUT_ROOT):
		push_error("BenchmarkRunner: 输出目录仅允许 %s 下" % OUTPUT_ROOT)
		return ERR_INVALID_PARAMETER
	return OK


func _process(_delta: float) -> void:
	if not _running:
		set_process(false)
		return
	var now_us := Time.get_ticks_usec()
	var interval_ms := float(now_us - _last_us) / 1000.0
	_last_us = now_us
	_elapsed = float(now_us - _start_us) / 1_000_000.0
	var warmup := float(_config.get("warmup_seconds", 15.0))
	var duration := float(_config.get("duration_seconds", 60.0))
	var route_id := str(_config.get("route_id", PerfRoutes.ROUTE_LEGACY))
	if _phase == "warmup" and _elapsed >= warmup:
		_phase = "steady"
	if _phase == "steady":
		_samples.append({
			"sample_index": _samples.size(),
			"timestamp_us": now_us - _start_us,
			"frame_interval_ms": snappedf(interval_ms, 0.001),
			"phase": "steady",
			"segment_id": PerfRoutes.segment_id(route_id, _elapsed - warmup),
		})
		var dc := int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
		if dc > _draw_call_peak:
			_draw_call_peak = dc
		var prim := int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
		if prim > _primitives_peak:
			_primitives_peak = prim
		var vm := Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / (1024.0 * 1024.0)
		if vm > _video_mem_peak:
			_video_mem_peak = vm
	# 失焦/最小化即中止（保持正常节流逻辑，不混入有效结果）
	if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_MINIMIZED or not DisplayServer.window_is_focused():
		_invalid_reason = "采样期窗口失焦/最小化"
		_finish(true)
		return
	# 驱动相机（仅稳态阶段推进路线时间；预热停在路线起点附近微移）
	var route_t := maxf(0.0, _elapsed - warmup) if _phase == "steady" else 0.0
	_camera.set_route_transform(PerfRoutes.route_transform(route_id, route_t))
	if _phase == "steady" and route_t >= duration:
		_finish(false)


func _finish(aborted: bool) -> void:
	set_process(false)
	_running = false
	var out_dir := str(_config.get("output_directory", OUTPUT_ROOT + "/run"))
	# 有效性判定
	var valid := _invalid_reason.is_empty()
	var steady_count := _samples.size()
	if valid and steady_count < 30:
		valid = false
		_invalid_reason = "有效稳态样本不足（%d < 30）" % steady_count
	if _quality != null:
		_quality.restore_runtime_state(_saved_quality)
	if str(_config.get("mode", "capped")) == "headroom":
		DisplayServer.window_set_vsync_mode(_saved_vsync)
		Engine.max_fps = _saved_max_fps
	var vp := get_viewport()
	vp.use_occlusion_culling = true  # 恢复默认（非覆盖状态）
	if _camera != null:
		_camera.set_input_enabled(true)
		if _saved_camera_pose != null:
			_camera.apply_pose(_saved_camera_pose, true)
	if _map_manager != null and not _saved_ambient.is_empty():
		_map_manager.restore_map_ambient_state(_saved_ambient)
	if _main != null:
		_main.set_automation_measure(false)
	if _guard != null and _token != 0:
		_guard.end(_token)
		_token = 0
	var dir := out_dir.path_join(_run_id)
	_write_outputs(dir, valid)
	if aborted or not valid:
		benchmark_aborted.emit(_run_id, _invalid_reason if not _invalid_reason.is_empty() else "aborted")
	else:
		benchmark_completed.emit(_run_id, dir)


# ============================ 输出 ============================

func _write_outputs(dir: String, valid: bool) -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	var stats := _compute_stats()
	var env := _environment_info()
	var run_json := {
		"schema_version": 1,
		"run_id": _run_id,
		"config": _config,
		"valid": valid,
		"invalid_reason": _invalid_reason,
		"environment": env,
		"map_state": _map_manager.get_state_snapshot() if _map_manager != null else {},
	}
	_write_json(dir.path_join("run.json"), run_json)
	_write_frames_csv(dir.path_join("frames.csv"))
	var summary := {
		"schema_version": 1,
		"run_id": _run_id,
		"valid": valid,
		"invalid_reason": _invalid_reason,
		"stats": stats,
		"environment": env,
	}
	_write_json(dir.path_join("summary.json"), summary)
	_append_summary_csv(valid, stats, env)


func _compute_stats() -> Dictionary:
	## 首个无前驱样本天然丢弃（interval 以进入稳态后第二帧起有效）；
	## FPS = 样本数 / 实际墙钟时长，不平均 1/delta。
	var out := {
		"sample_count": _samples.size(), "average_fps": 0.0,
		"p50_ms": 0.0, "p95_ms": 0.0, "p99_ms": 0.0,
		"stutters_over_100ms": 0, "elapsed_seconds": 0.0,
	}
	if _samples.size() < 2:
		return out
	var intervals := PackedFloat64Array()
	var first_us: float = _samples[0]["timestamp_us"]
	var last_us: float = _samples[_samples.size() - 1]["timestamp_us"]
	# 第一个样本无前驱（其 interval 跨预热边界），丢弃
	for i in range(1, _samples.size()):
		intervals.append(float(_samples[i]["frame_interval_ms"]))
	var wall_sec := (last_us - first_us) / 1_000_000.0
	out["elapsed_seconds"] = snappedf(wall_sec, 0.001)
	out["average_fps"] = snappedf(intervals.size() / wall_sec, 0.01) if wall_sec > 0.0 else 0.0
	var sorted := intervals.duplicate()
	sorted.sort()
	out["p50_ms"] = snappedf(_nearest_rank(sorted, 0.50), 0.001)
	out["p95_ms"] = snappedf(_nearest_rank(sorted, 0.95), 0.001)
	out["p99_ms"] = snappedf(_nearest_rank(sorted, 0.99), 0.001)
	var stutters := 0
	for ms in intervals:
		if ms > 100.0:
			stutters += 1
	out["stutters_over_100ms"] = stutters
	return out


static func _nearest_rank(sorted: PackedFloat64Array, q: float) -> float:
	if sorted.is_empty():
		return 0.0
	var idx := ceili(q * float(sorted.size())) - 1
	idx = clampi(idx, 0, sorted.size() - 1)
	return sorted[idx]


func _write_json(path: String, data: Dictionary) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("BenchmarkRunner: 写盘失败 %s" % path)
		return
	f.store_string(JSON.stringify(data, "  "))
	f.close()


func _write_frames_csv(path: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return
	f.store_line("sample_index,timestamp_us,frame_interval_ms,phase,segment_id")
	for s in _samples:
		f.store_line("%d,%d,%.3f,%s,%s" % [s["sample_index"], s["timestamp_us"], s["frame_interval_ms"], s["phase"], s["segment_id"]])
	f.close()


func _environment_info() -> Dictionary:
	var roots := get_tree().get_nodes_in_group("active_map_root")
	var node_count := 0
	if roots.size() > 0 and _main != null:
		node_count = _main.count_map_nodes(roots[0])
	var adapter := "unknown"
	if RenderingServer.has_method("get_video_adapter_name"):
		adapter = str(RenderingServer.call("get_video_adapter_name"))
	var vsync := "unknown"
	match DisplayServer.window_get_vsync_mode():
		DisplayServer.VSYNC_ENABLED: vsync = "enabled"
		DisplayServer.VSYNC_DISABLED: vsync = "disabled"
		DisplayServer.VSYNC_ADAPTIVE: vsync = "adaptive"
		DisplayServer.VSYNC_MAILBOX: vsync = "mailbox"
	var eff: Dictionary = _quality.get_effective_state() if _quality != null else {}
	return {
		"engine_version": str(Engine.get_version_info().get("string", "")),
		"build_type": "project_run" if OS.has_feature("editor") else "release",
		"renderer": str(eff.get("renderer", "unknown")),
		"gpu_name": adapter,
		"cpu_name": "",       # 运行时无可靠来源；由外部系统采样工具补充
		"system_ram_mib": null,
		"window_width": int(get_window().size.x),
		"window_height": int(get_window().size.y),
		"render_scale": float(eff.get("render_scale", 1.0)),
		"frame_cap": int(eff.get("frame_cap", 0)),
		"vsync_mode": vsync,
		"occlusion_enabled": bool(eff.get("occlusion_enabled", false)),
		"draw_calls_peak": _draw_call_peak,
		"visible_primitives_peak": _primitives_peak,
		"map_node_count": node_count,
		"engine_video_memory_mib_peak": snappedf(_video_mem_peak, 1.0),
		"resource_load_ms": float(_map_manager.last_resource_load_ms) if _map_manager != null else 0.0,
		"activation_ms": float(_map_manager.last_activation_ms) if _map_manager != null else 0.0,
	}


func _append_summary_csv(valid: bool, stats: Dictionary, env: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(OUTPUT_ROOT)
	var exists := FileAccess.file_exists(SUMMARY_CSV)
	var f := FileAccess.open(SUMMARY_CSV, FileAccess.READ_WRITE if exists else FileAccess.WRITE)
	if not exists:
		f.store_line(CSV_HEADER)
	f.seek_end()
	var content_revision := ""
	if _map_manager != null:
		content_revision = _map_manager.get_current_content_revision()
	var cols := [
		_run_id,
		String(_map_manager.get_current_map_id()) if _map_manager != null else "",
		content_revision,
		str(_config.get("route_id", "")),
		str(_config.get("profile_id", "")),
		str(_config.get("mode", "")),
		"1" if valid else "0",
		'"%s"' % _invalid_reason,
		str(env.get("engine_version", "")),
		str(env.get("build_type", "")),
		str(env.get("renderer", "")),
		str(env.get("gpu_name", "")),
		"",  # cpu_name：外部工具补充
		"",  # system_ram_mib：外部工具补充
		str(env.get("window_width", "")), str(env.get("window_height", "")),
		str(env.get("render_scale", "")), str(env.get("frame_cap", "")),
		str(env.get("vsync_mode", "")), str(env.get("occlusion_enabled", "")),
		str(stats.get("sample_count", 0)), str(stats.get("elapsed_seconds", 0)),
		str(stats.get("average_fps", 0)), str(stats.get("p50_ms", 0)),
		str(stats.get("p95_ms", 0)), str(stats.get("p99_ms", 0)),
		str(stats.get("stutters_over_100ms", 0)),
		str(env.get("draw_calls_peak", "")), str(env.get("visible_primitives_peak", "")),
		str(env.get("map_node_count", "")),
		"",  # process_working_set_mib_peak：外部工具
		"",  # process_private_bytes_mib_peak：外部工具
		str(env.get("engine_video_memory_mib_peak", "")),
		"",  # os_gpu_memory_mib_peak：不可靠来源留空
		"", "",  # cpu/gpu frame ms：无可靠来源留空（notes 说明）
		str(env.get("resource_load_ms", "")), str(env.get("activation_ms", "")),
		'"frame_interval=主循环间隔;引擎显存=估计值;工作集/私有内存/CPU=外部采样工具"',
	]
	f.store_line(",".join(cols))
	f.close()
