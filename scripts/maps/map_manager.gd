## 地图管理器：严格单活动地图的异步加载/卸载状态机（AGENTS.md §6）。
##
## 状态：EMPTY → LOADING → ACTIVATING → READY → UNLOADING → EMPTY
## 卸载前的参数验证失败保持原状态；卸载后的失败进入 ERROR 并清理部分实例。
extends Node

signal map_loading(map_id: String, progress: float)
signal map_loaded(map_id: String)
signal map_failed(map_id: String, reason: String)
signal state_changed(new_state: int)

enum State { EMPTY, READY, UNLOADING, LOADING, ACTIVATING, ERROR }

const STATE_NAMES: Dictionary = {
	State.EMPTY: "EMPTY", State.READY: "READY", State.UNLOADING: "UNLOADING",
	State.LOADING: "LOADING", State.ACTIVATING: "ACTIVATING", State.ERROR: "ERROR",
}

var state: State = State.EMPTY
var current_map_id: String = ""

var _map_slot: Node3D = null
var _registry: Dictionary = {}          # map_id -> definition_path (String)
var _definitions: Dictionary = {}       # map_id -> MapDefinition（轻量数据，允许缓存）
var _packed_scene: PackedScene = null
var _loading_id: String = ""
var _loading_scene_path: String = ""
var _last_weak_ref: WeakRef = null
var _pending_reload_after_unload: String = ""
var _load_request_msec: int = 0

## 计时与统计（供诊断/性能记录）。
var last_resource_load_ms: float = 0.0
var last_activation_ms: float = 0.0


func setup(map_slot: Node3D) -> void:
	_map_slot = map_slot


func load_registry_file(path: String) -> bool:
	## 从 JSON 注册表加载 map_id -> definition_path。只保存字符串。
	var txt := FileAccess.get_file_as_string(path)
	if txt.is_empty():
		push_error("MapManager: 注册表不可读 %s" % path)
		return false
	var parsed = JSON.parse_string(txt)
	if parsed == null or not parsed is Dictionary:
		push_error("MapManager: 注册表 JSON 非法 %s" % path)
		return false
	var maps: Array = parsed.get("maps", [])
	for entry in maps:
		if entry is Dictionary:
			var mid: String = str(entry.get("map_id", ""))
			var dpath: String = str(entry.get("definition_path", ""))
			if not mid.is_empty() and not dpath.is_empty():
				_registry[mid] = dpath
	return not _registry.is_empty()


func inject_registry(entries: Dictionary) -> void:
	## 测试入口：直接注入 {map_id: definition_path}。
	for k in entries:
		_registry[str(k)] = str(entries[k])


func get_available_map_ids() -> Array[String]:
	var ids: Array[String] = []
	for mid in _registry:
		var def := _get_definition(str(mid))
		if def != null and def.available:
			ids.append(str(mid))
	ids.sort()
	return ids


func get_definition(mid: String) -> MapDefinition:
	return _get_definition(mid)


func get_active_root_count() -> int:
	## 场景树中 active_map_root 组的节点数。稳态必须为 1，切换中可为 0。
	return get_tree().get_nodes_in_group("active_map_root").size()


func is_busy() -> bool:
	return state == State.UNLOADING or state == State.LOADING or state == State.ACTIVATING


## 请求切换地图。只允许一个切换事务；无效请求在卸载前被拒绝。
func request_map(map_id: String) -> bool:
	if is_busy():
		push_warning("MapManager: 切换进行中(%s)，忽略重复请求 %s" % [STATE_NAMES[state], map_id])
		map_failed.emit(map_id, "已有切换事务在进行")
		return false
	if map_id == current_map_id and state == State.READY:
		push_warning("MapManager: 地图 %s 已是当前活动地图" % map_id)
		return false
	var def := _validate_request(map_id)
	if def == null:
		return false  # 验证失败：保持原状态、原地图
	if state == State.READY and current_map_id != "":
		_pending_reload_after_unload = map_id
		_begin_unload()
		return true
	_begin_load(def)
	return true


func unload_current_map() -> bool:
	if is_busy():
		return false
	if state != State.READY or current_map_id == "":
		return false
	_pending_reload_after_unload = ""
	_begin_unload()
	return true


func _validate_request(map_id: String) -> MapDefinition:
	if not _registry.has(map_id):
		map_failed.emit(map_id, "未知地图 ID: %s" % map_id)
		return null
	var def := _get_definition(map_id)
	if def == null:
		map_failed.emit(map_id, "地图定义不可加载: %s" % str(_registry.get(map_id)))
		return null
	var reason := def.validate()
	if not reason.is_empty():
		map_failed.emit(map_id, "定义非法: %s" % reason)
		return null
	if not def.available:
		map_failed.emit(map_id, "地图标记为不可用")
		return null
	if not ResourceLoader.exists(def.scene_path):
		map_failed.emit(map_id, "场景路径不存在: %s" % def.scene_path)
		return null
	return def


func _get_definition(map_id: String) -> MapDefinition:
	if _definitions.has(map_id):
		return _definitions[map_id]
	if not _registry.has(map_id):
		return null
	var dpath: String = _registry[map_id]
	var def := load(dpath) as MapDefinition
	if def == null:
		push_error("MapManager: MapDefinition 加载失败 %s" % dpath)
		return null
	_definitions[map_id] = def
	return def


func _set_state(s: State) -> void:
	state = s
	state_changed.emit(s)


func _begin_unload() -> void:
	_set_state(State.UNLOADING)
	if _map_slot.get_child_count() > 0:
		var map_root := _map_slot.get_child(0)
		if map_root is MapRoot:
			(map_root as MapRoot).shutdown()
		_last_weak_ref = weakref(map_root)
		map_root.name = "OldMapRoot"
		_map_slot.remove_child(map_root)
		map_root.queue_free()
		# 等待删除真正生效（tree_exited 在 remove_child 时已同步发出，不能 await 它）
		while _last_weak_ref.get_ref() != null:
			await get_tree().process_frame
	else:
		_last_weak_ref = null
	# 清空本管理器持有的强引用
	_packed_scene = null
	current_map_id = ""
	_after_unload()


func _after_unload() -> void:
	if not _pending_reload_after_unload.is_empty():
		var next_id := _pending_reload_after_unload
		_pending_reload_after_unload = ""
		var def := _validate_request(next_id)
		if def == null:
			# 卸载后验证失败：进入 ERROR，随后回到 EMPTY 允许重试
			_set_state(State.ERROR)
			_set_state(State.EMPTY)
			return
		_begin_load(def)
	else:
		_set_state(State.EMPTY)


func _begin_load(def: MapDefinition) -> void:
	_set_state(State.LOADING)
	_loading_id = def.map_id
	_loading_scene_path = def.scene_path
	_load_request_msec = Time.get_ticks_msec()
	var err := ResourceLoader.load_threaded_request(_loading_scene_path, "", true)
	if err != OK:
		_set_state(State.ERROR)
		map_failed.emit(_loading_id, "后台加载请求失败: %s" % _loading_scene_path)
		_loading_id = ""
		_set_state(State.EMPTY)
		return
	set_process(true)


func _process(_delta: float) -> void:
	if state != State.LOADING:
		set_process(false)
		return
	var progress: Array = []
	var status := ResourceLoader.load_threaded_get_status(_loading_scene_path, progress)
	match status:
		ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			map_loading.emit(_loading_id, float(progress[0]) if progress.size() > 0 else 0.0)
		ResourceLoader.THREAD_LOAD_LOADED:
			last_resource_load_ms = float(Time.get_ticks_msec() - _load_request_msec)
			_packed_scene = ResourceLoader.load_threaded_get(_loading_scene_path)
			_activate_loaded_scene()
		_:
			_set_state(State.ERROR)
			map_failed.emit(_loading_id, "资源加载失败或无效 (status=%d)" % status)
			_loading_id = ""
			set_process(false)
			_set_state(State.EMPTY)


func _activate_loaded_scene() -> void:
	_set_state(State.ACTIVATING)
	var act_start := Time.get_ticks_msec()
	var map_id := _loading_id
	_loading_id = ""
	set_process(false)
	if _packed_scene == null:
		_fail_activation(map_id, "PackedScene 为空")
		return
	var instance := _packed_scene.instantiate()
	if not instance is MapRoot:
		if instance is Node:
			instance.queue_free()
		_fail_activation(map_id, "地图根节点未使用 MapRoot 脚本")
		return
	var def := _get_definition(map_id)
	if def != null:
		var missing: PackedStringArray = []
		for anchor in def.anchor_names:
			if not (instance as MapRoot).has_anchor(anchor):
				missing.append(anchor)
		if missing.size() > 0:
			instance.queue_free()
			var weak: WeakRef = weakref(instance)
			while weak.get_ref() != null:
				await get_tree().process_frame
			_fail_activation(map_id, "缺少锚点: %s" % ", ".join(missing))
			return
	_map_slot.add_child(instance)
	_map_slot.move_child(instance, 0)
	current_map_id = map_id
	_packed_scene = null  # 不长期持有地图 PackedScene
	last_activation_ms = float(Time.get_ticks_msec() - act_start)
	_set_state(State.READY)
	map_loaded.emit(map_id)


func _fail_activation(map_id: String, reason: String) -> void:
	_set_state(State.ERROR)
	map_failed.emit(map_id, reason)
	# 清理任何部分实例后回到 EMPTY，允许重试
	for child in _map_slot.get_children():
		child.queue_free()
	current_map_id = ""
	_packed_scene = null
	_set_state(State.EMPTY)


func get_last_unloaded_weak_ref() -> WeakRef:
	return _last_weak_ref
