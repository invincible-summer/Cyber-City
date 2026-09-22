## 画质档与用户设置（chapter1-1 §7.5 QualityController 合同）。
## 配置权威：data/quality/*.json（保持 JSON）；用户选择存 user://settings.cfg，非法值回落 Eco。
## 有效帧率优先级：最小化 5 → 失焦 10 → 正常所选档位；最小化同时暂停地图环境动画（由 main 编排）。
extends Node

const SETTINGS_PATH := "user://settings.cfg"
const QUALITY_DIR := "res://data/quality"

signal quality_changed(requested_id: StringName, effective_state: Dictionary)

var profiles: Dictionary = {}       # id -> Dictionary
var current_quality: String = "eco"
var current_profile: Dictionary = {}
var _focused := true
var _minimized := false

## 兼容别名：旧调用方（tool_ui / main / tests）使用的方法保留为薄适配。


func _ready() -> void:
	_load_profiles()
	_load_settings()
	_apply_profile(current_quality, false)


func get_quality_ids() -> Array[String]:
	var ids: Array[String] = []
	for k in profiles:
		ids.append(str(k))
	ids.sort()
	return ids


func set_profile(profile_id: StringName, persist: bool = true) -> Error:
	var id := String(profile_id)
	if not profiles.has(id):
		push_warning("SettingsManager: 未知画质档 %s" % id)
		return ERR_INVALID_PARAMETER
	_apply_profile(id, persist)
	return OK


func get_profile_id() -> StringName:
	return StringName(current_quality)


## 兼容适配：旧签名（无返回值）。
func set_quality(id: String) -> void:
	set_profile(StringName(id), true)


## 兼容适配：自动化测量用，强制应用（跳过相同档位短路）。
func force_apply(id: String) -> void:
	set_profile(StringName(id), false)


func get_profile() -> Dictionary:
	return current_profile


## 实际生效状态（来自应用后的真实状态，不是配置回显）。
func get_effective_state() -> Dictionary:
	var vp := get_viewport()
	var aa_mode := "disabled"
	if vp != null:
		if vp.screen_space_aa == Viewport.SCREEN_SPACE_AA_FXAA:
			aa_mode = "fxaa"
		elif vp.msaa_3d != Viewport.MSAA_DISABLED:
			aa_mode = "msaa_%dx" % (2 if vp.msaa_3d == Viewport.MSAA_2X else 4)
	return {
		"profile_id": StringName(current_quality),
		"frame_cap": Engine.max_fps,
		"render_scale": vp.scaling_3d_scale if vp != null else 1.0,
		"aa_mode": aa_mode,
		"glow_enabled": _map_glow_enabled(),
		"probe_count": _count_group_in_active_map("optional_probe"),
		"particle_emitter_count": _count_group_in_active_map("optional_particle"),
		"runtime_fill_count": _count_group_in_active_map("runtime_fill_light"),
		"occlusion_enabled": vp.use_occlusion_culling if vp != null else false,
		"focused": _focused,
		"minimized": _minimized,
		"renderer": _renderer_name(),
	}


## 将当前档位应用到指定地图根（§8.3）：地图质量项 + 地图默认 occlusion 一次落值。
## 应用后不保留 map_root 强引用。
func apply_to_map(map_root) -> Error:
	if map_root == null:
		return ERR_INVALID_PARAMETER
	if not map_root is MapRoot:
		return ERR_INVALID_PARAMETER
	var err := (map_root as MapRoot).apply_quality(current_profile)
	var vp := get_viewport()
	if vp != null:
		vp.use_occlusion_culling = (map_root as MapRoot).get_occlusion_enabled()
	return err


## §8.6：离开任何地图后恢复"不属于地图"的全局视口覆盖（当前为工程默认 occlusion）。
## 只由 MapManager 在真正回到 EMPTY 的两条路径调用。
func apply_no_map_defaults() -> void:
	var vp := get_viewport()
	if vp != null:
		vp.use_occlusion_culling = bool(ProjectSettings.get_setting(
			"rendering/occlusion_culling/use_occlusion_culling", true))


## 兼容适配：旧签名。
func apply_focus_throttle(unfocused: bool, minimized: bool) -> void:
	set_window_state(not unfocused, minimized)


func capture_runtime_state() -> Dictionary:
	## 只存值：请求档位、用户帧率与窗口状态。基准/截图恢复用。
	return {
		"profile_id": String(current_quality),
		"user_max_fps": int(current_profile.get("max_fps", 30)),
	}


func restore_runtime_state(snapshot: Dictionary) -> Error:
	if not snapshot is Dictionary or snapshot.is_empty():
		return ERR_INVALID_PARAMETER
	var id := str(snapshot.get("profile_id", "eco"))
	if not profiles.has(id):
		id = "eco"
	_apply_profile(id, false)
	# 重新读取真实窗口状态计算有效帧率，不沿用快照中的旧前台状态
	_focused = DisplayServer.window_is_focused()
	_minimized = DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_MINIMIZED
	_apply_effective_frame_cap()
	return OK


# ============================ 内部 ============================

func _load_profiles() -> void:
	for id in ["eco", "balanced"]:
		var path := "%s/%s.json" % [QUALITY_DIR, id]
		var txt := FileAccess.get_file_as_string(path)
		if txt.is_empty():
			push_error("SettingsManager: 画质配置缺失 %s" % path)
			continue
		var parsed = JSON.parse_string(txt)
		if parsed is Dictionary:
			profiles[id] = parsed
	if profiles.is_empty():
		# 兜底：配置文件全部缺失时使用内置 Eco（不写回 res://）
		profiles["eco"] = {
			"id": "eco", "label": "经济", "render_scale": 0.8, "max_fps": 30,
			"msaa": 0, "fxaa": true, "glow": false, "particles": false,
			"probes": false, "extra_lights": false, "detail_prop_range": 55.0,
			"focus_fps": 10, "minimized_fps": 5,
		}


func _load_settings() -> void:
	var cf := ConfigFile.new()
	var err := cf.load(SETTINGS_PATH)
	if err != OK:
		current_quality = "eco"  # 无配置或损坏：回落默认
		return
	var q := str(cf.get_value("quality", "selected", "eco"))
	if profiles.has(q):
		current_quality = q
	else:
		push_warning("SettingsManager: 用户配置含非法档位 %s，回落 eco" % q)
		current_quality = "eco"


func save_settings() -> void:
	var cf := ConfigFile.new()
	cf.set_value("quality", "selected", current_quality)
	cf.save(SETTINGS_PATH)


func _apply_profile(id: String, save: bool) -> void:
	## §8.3 完整顺序：档位 → 视口 → 帧率 → 活动地图（含 occlusion）→ 最后才发信号。
	current_quality = id
	current_profile = profiles.get(id, {})
	var vp := get_viewport()
	var p := current_profile
	vp.scaling_3d_scale = clampf(float(p.get("render_scale", 1.0)), 0.5, 1.0)
	match int(p.get("msaa", 0)):
		2: vp.msaa_3d = Viewport.MSAA_2X
		4: vp.msaa_3d = Viewport.MSAA_4X
		_: vp.msaa_3d = Viewport.MSAA_DISABLED
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if bool(p.get("fxaa", false)) else Viewport.SCREEN_SPACE_AA_DISABLED
	if save:
		save_settings()
	_apply_effective_frame_cap()
	_apply_to_active_map_if_present()
	quality_changed.emit(StringName(id), get_effective_state())


## §8.3：档位变化时把当前档位作用到活动地图；>1 个活动根是生命周期违约。
func _apply_to_active_map_if_present() -> void:
	var roots := get_tree().get_nodes_in_group("active_map_root")
	if roots.is_empty():
		return
	if roots.size() > 1:
		push_error("SettingsManager: active_map_root=%d（应为 1），跳过地图档位应用" % roots.size())
		return
	var r := roots[0]
	if r is MapRoot:
		apply_to_map(r)


## 窗口状态变化（焦点/最小化）只影响帧率，不影响地图内质量项。
func set_window_state(focused: bool, minimized: bool) -> void:
	_focused = focused
	_minimized = minimized
	_apply_effective_frame_cap()


func _apply_effective_frame_cap() -> void:
	## 有效帧率优先级：最小化 5 → 失焦 10 → 正常档位。
	if _minimized:
		Engine.max_fps = int(current_profile.get("minimized_fps", 5))
	elif not _focused:
		Engine.max_fps = int(current_profile.get("focus_fps", 10))
	else:
		Engine.max_fps = int(current_profile.get("max_fps", 30))


func _map_glow_enabled() -> bool:
	## Glow 由地图 WorldEnvironment 承载；活动地图不存在时以档位配置为准。
	var roots := get_tree().get_nodes_in_group("active_map_root")
	for r in roots:
		if r is MapRoot:
			var env := (r as MapRoot).get_node_or_null("Environment") as WorldEnvironment
			if env != null and env.environment != null:
				return env.environment.glow_enabled
	return bool(current_profile.get("glow", false))


func _count_group_in_active_map(group_name: String) -> int:
	var count := 0
	for node in get_tree().get_nodes_in_group(group_name):
		for r in get_tree().get_nodes_in_group("active_map_root"):
			if (r as Node).is_ancestor_of(node) and node is Node3D and (node as Node3D).visible:
				count += 1
				break
	return count


func _renderer_name() -> String:
	if RenderingServer.has_method("get_current_rendering_method"):
		return str(RenderingServer.call("get_current_rendering_method"))
	return "unknown"
