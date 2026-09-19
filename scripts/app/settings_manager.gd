## 画质档与用户设置。配置保存到 user://settings.cfg，非法值回落默认（Eco）。
extends Node

const SETTINGS_PATH := "user://settings.cfg"
const QUALITY_DIR := "res://data/quality"

signal quality_changed(profile: Dictionary)

var profiles: Dictionary = {}       # id -> Dictionary
var current_quality: String = "eco"
var current_profile: Dictionary = {}
## 失焦/最小化前的用户帧率上限，恢复时使用。
var _user_max_fps: int = 30


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


func set_quality(id: String) -> void:
	if not profiles.has(id):
		return
	_apply_profile(id, true)


## 自动化测量用：强制应用（跳过相同档位短路），保证档位确定生效。
func force_apply(id: String) -> void:
	if not profiles.has(id):
		return
	_apply_profile(id, true)


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
	current_quality = q if profiles.has(q) else "eco"


func save_settings() -> void:
	var cf := ConfigFile.new()
	cf.set_value("quality", "selected", current_quality)
	cf.save(SETTINGS_PATH)


func _apply_profile(id: String, save: bool) -> void:
	current_quality = id
	current_profile = profiles.get(id, {})
	var vp := get_viewport()
	var p := current_profile
	vp.scaling_3d_scale = clampf(float(p.get("render_scale", 1.0)), 0.5, 1.0)
	_user_max_fps = int(p.get("max_fps", 60))
	Engine.max_fps = _user_max_fps
	match int(p.get("msaa", 0)):
		2: vp.msaa_3d = Viewport.MSAA_2X
		4: vp.msaa_3d = Viewport.MSAA_4X
		_: vp.msaa_3d = Viewport.MSAA_DISABLED
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if bool(p.get("fxaa", false)) else Viewport.SCREEN_SPACE_AA_DISABLED
	if save:
		save_settings()
	quality_changed.emit(current_profile)


## 失焦节流 / 最小化节流。恢复时回到用户选择的帧率。
func apply_focus_throttle(unfocused: bool, minimized: bool) -> void:
	if minimized:
		Engine.max_fps = int(current_profile.get("minimized_fps", 5))
	elif unfocused:
		Engine.max_fps = int(current_profile.get("focus_fps", 10))
	else:
		Engine.max_fps = _user_max_fps


func get_profile() -> Dictionary:
	return current_profile
