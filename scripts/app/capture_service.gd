## 截图服务（chapter1-1 §8.1 CaptureService 合同）。
## 流程：capture token → 保存并隐藏 capture_ui → 等待真实绘制 → 读视口 →
## 写 PNG + 同名 JSON 元数据 → 恢复状态 → 释放 token → 发完成信号。
## 失败/abort/退出共用同一幂等清理；每个 await 继续点检查 request_id 有效性。
extends Node

signal capture_completed(request_id: int, image_path: String, metadata_path: String)
signal capture_failed(request_id: int, error: Error, message: String)

const OUT_DIR := "user://captures"
const THROTTLE_MSEC := 500

var _guard: ActivityGuard = null
var _map_manager = null       # map_manager.gd
var _quality = null           # settings_manager.gd
var _camera = null            # camera_controller.gd
var _build_id := ""
var _busy := false
var _active_id := 0           # 当前请求上下文（C13-15 §17.2：收敛到字段，不再散落局部变量）
var _active_token := 0
var _saved_ui: Dictionary = {}
var _next_request_id := 1
var _last_capture_msec := -100000


func setup(guard: ActivityGuard, map_manager, quality, camera, build_id: String = "") -> void:
	_guard = guard
	_map_manager = map_manager
	_quality = quality
	_camera = camera
	_build_id = build_id


func is_busy() -> bool:
	return _busy


func abort_capture(reason: String) -> void:
	## §17.2：立即取消并走统一 finish（恢复 UI/输入、释放 guard、_busy=false、
	## failed 只发一次）；不依赖"下一帧一定会到来"。已挂起的旧 continuation
	## 恢复后只看到 request 已失效并 return，不能再次 cleanup/emit。
	if not _busy or _active_id == 0:
		return
	var rid := _active_id
	push_warning("CaptureService: 截图中止 (%s)" % reason)
	_finish(rid, ERR_UNAVAILABLE, "截图已中止: %s" % reason, "", "")


## 受理一次截图请求。忙碌/节流返回 ERR_BUSY；非法标签返回 ERR_INVALID_PARAMETER。
func request_capture(label: String = "") -> Error:
	if _busy:
		return ERR_BUSY
	if _map_manager != null and _map_manager.is_transitioning():
		return ERR_BUSY  # 截图到一半切图被禁止
	var now := Time.get_ticks_msec()
	if now - _last_capture_msec < THROTTLE_MSEC:
		return ERR_BUSY
	var safe_label := _sanitize_label(label)
	if not label.is_empty() and safe_label.is_empty():
		return ERR_INVALID_PARAMETER
	var token := 0
	if _guard != null:
		token = _guard.try_begin(ActivityGuard.KIND_CAPTURE)
		if token == 0:
			return ERR_BUSY
	var request_id := _next_request_id
	_next_request_id += 1
	_last_capture_msec = now
	_run_capture(request_id, safe_label, token)
	return OK


func _run_capture(request_id: int, label: String, token: int) -> void:
	_busy = true
	_active_id = request_id
	_active_token = token
	_saved_ui = _save_ui_state()
	_apply_ui_state(false)
	for i in 2:
		await RenderingServer.frame_post_draw
		if not _is_active(request_id):
			return  # abort 已统一收尾；旧 continuation 只能退出
	var img := get_viewport().get_texture().get_image()
	if img == null or img.is_empty():
		_finish(request_id, ERR_CANT_CREATE, "视口图像不可用（headless 无 GPU 渲染结果）", "", "")
		return
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	var stamp := Time.get_datetime_string_from_system(false, true)
	stamp = stamp.replace(":", "").replace("-", "").replace("T", "_").replace(" ", "")
	var base := "cap_%s_%s" % [stamp, str(request_id)]
	if not label.is_empty():
		base = "%s_%s" % [label, base]
	var png_path := "%s/%s.png" % [OUT_DIR, base]
	var json_path := "%s/%s.json" % [OUT_DIR, base]
	var png_err := img.save_png(png_path)
	if png_err != OK:
		_finish(request_id, png_err, "PNG 写盘失败 (err=%d)" % png_err, "", "")
		return
	var meta := _build_metadata(request_id, label, img)
	var jf := FileAccess.open(json_path, FileAccess.WRITE)
	if jf == null:
		DirAccess.remove_absolute(png_path)
		_finish(request_id, ERR_CANT_OPEN, "元数据写盘失败", "", "")
		return
	jf.store_string(JSON.stringify(meta, "  "))
	jf.close()
	if not FileAccess.file_exists(json_path):
		DirAccess.remove_absolute(png_path)
		DirAccess.remove_absolute(json_path)
		_finish(request_id, ERR_CANT_OPEN, "元数据校验失败", "", "")
		return
	_finish(request_id, OK, "", png_path, json_path)


func _is_active(request_id: int) -> bool:
	return _busy and _active_id == request_id


## §17.2 统一幂等 finish：恢复 UI/输入、释放 guard、清上下文、_busy=false、
## 成功发 completed（一次）、失败/取消发 failed（一次）。半成品文件由调用方清理。
func _finish(request_id: int, err: Error, msg: String, png_path: String, json_path: String) -> void:
	if not _busy or _active_id != request_id:
		return  # 已被 abort 等路径收尾；不得二次 cleanup/emit
	_apply_ui_state(true, _saved_ui)
	if _guard != null and _active_token != 0:
		_guard.end(_active_token)
	_busy = false
	_active_id = 0
	_active_token = 0
	_saved_ui = {}
	if err == OK:
		capture_completed.emit(request_id, png_path, json_path)
	else:
		capture_failed.emit(request_id, err, msg)


## 保存/恢复 UI 与输入状态；只恢复被保存过状态的项，不强制全部 visible=true。
func _save_ui_state() -> Dictionary:
	var state := {"layers": [], "camera_input": true}
	for node in get_tree().get_nodes_in_group("capture_ui"):
		if node is CanvasItem:
			state["layers"].append({"node": node, "visible": (node as CanvasItem).visible})
	if _camera != null:
		state["camera_input"] = _camera.enabled
	return state


func _apply_ui_state(show: bool, saved: Dictionary = {}) -> void:
	if show and not saved.is_empty():
		for entry in saved.get("layers", []):
			var node = entry.get("node")
			if node != null and is_instance_valid(node):
				(node as CanvasItem).visible = bool(entry.get("visible", false))
		if _camera != null:
			_camera.enabled = bool(saved.get("camera_input", true))
		return
	# 隐藏：整层临时隐藏（诊断层与其面板一起隐藏）
	for node in get_tree().get_nodes_in_group("capture_ui"):
		if node is CanvasItem:
			(node as CanvasItem).visible = false
	if _camera != null:
		_camera.enabled = false


func _sanitize_label(label: String) -> String:
	## 只保留安全字符作文件名片段；过滤路径分隔符与保留字符，防目录穿越。
	var out := ""
	for ch in label:
		var c := str(ch)
		if c == "/" or c == "\\" or c == ":" or c == "*" or c == "?" or c == "\"" or c == "<" or c == ">" or c == "|" or c == "." or c == " ":
			out += "_"
		elif c.unicode_at(0) < 32:
			continue
		else:
			out += c
	return out.substr(0, 32)


func _build_metadata(request_id: int, label: String, img: Image) -> Dictionary:
	var meta := {
		"schema_version": 1,
		"request_id": request_id,
		"label": label,
		"map_id": "",
		"content_revision": "",
		"anchor_id": "",
		"camera_pose": {},
		"profile_id": "",
		"effective_state": {},
		"image_width": img.get_width(),
		"image_height": img.get_height(),
		"utc_time": Time.get_datetime_string_from_system(true),
		"engine_version": str(Engine.get_version_info().get("string", "")),
		"gpu_adapter": _gpu_adapter(),
		"build_id": _build_id,
	}
	if _map_manager != null:
		meta["map_id"] = String(_map_manager.get_current_map_id())
		meta["content_revision"] = _map_manager.get_current_content_revision()
	if _quality != null:
		meta["profile_id"] = String(_quality.get_profile_id())
		meta["effective_state"] = _quality.get_effective_state()
	if _camera != null:
		var pose: CameraPose = _camera.get_pose()
		if pose != null:
			meta["camera_pose"] = pose.to_dict()
			meta["anchor_id"] = String(pose.anchor_id)
	# chapter1-2 §9.4：截图瞬间的渲染计数（与诊断面板同源），随 JSON 可读
	meta["render_stats"] = {
		"fps": Engine.get_frames_per_second(),
		"draw_calls": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
		"primitives": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME),
		"video_mem_mb": roundf(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED) / 1048576.0),
	}
	return meta


func _gpu_adapter() -> String:
	if RenderingServer.has_method("get_video_adapter_name"):
		return str(RenderingServer.call("get_video_adapter_name"))
	return "unknown"
