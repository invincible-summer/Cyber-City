## 地图管理器：严格单活动地图的异步加载/卸载状态机。
## chapter1-1 §7.3 合同：事务 ID、Error 返回值、阶段化进度、环境转发、相机合同编排。
##
## 状态：EMPTY → LOADING → ACTIVATING → READY；切换 READY → UNLOADING → LOADING → …；
## 独立卸载 READY → UNLOADING → EMPTY；卸载后失败进入 ERROR 并清理回 EMPTY。
extends Node

signal map_loading(map_id: StringName, transaction_id: int, stage: StringName, progress: float)
signal map_loaded(map_id: StringName, transaction_id: int)
signal map_unloaded(map_id: StringName, transaction_id: int)
signal map_failed(map_id: StringName, transaction_id: int, error: Error, message: String)
signal state_changed(new_state: int)

enum State { EMPTY, READY, UNLOADING, LOADING, ACTIVATING, ERROR }

const STATE_NAMES: Dictionary = {
	State.EMPTY: "EMPTY", State.READY: "READY", State.UNLOADING: "UNLOADING",
	State.LOADING: "LOADING", State.ACTIVATING: "ACTIVATING", State.ERROR: "ERROR",
}
const STAGE_UNLOADING := &"unloading"
const STAGE_RESOURCE := &"resource_loading"
const STAGE_ACTIVATING := &"activating"
const LOAD_TIMEOUT_SEC := 30.0

var state: State = State.EMPTY
var current_map_id: StringName = &""

var _map_slot: Node3D = null
var _guard: ActivityGuard = null
var _quality = null          # settings_manager.gd（QualityController 合同）
var _camera = null           # camera_controller.gd（ObserverCamera 合同）
var _registry: Dictionary = {}          # map_id -> definition_path (String)
var _definitions: Dictionary = {}       # map_id -> MapDefinition（轻量数据，允许缓存）
var _packed_scene: PackedScene = null
var _transaction_id: int = 0
var _next_transaction_id: int = 1
var _loading_id: StringName = &""
var _loading_scene_path: String = ""
var _load_start_usec: int = 0
var _load_token: int = 0                # 本事务持有的活动 token；0 = 无
var _tx_valid := false                  # 异步继续点检查事务是否仍有效
var _orphan_paths: Dictionary = {}      # 放弃但线程尚未终结的加载路径 -> true
var _pending_reload_after_unload: StringName = &""
var _last_error: String = ""
var _load_request_msec: int = 0

## 计时与统计（供诊断/性能记录）。
var last_resource_load_ms: float = 0.0
var last_activation_ms: float = 0.0


## 组合根（main.gd）注入依赖。quality/camera 允许为 null（纯生命周期测试）。
func setup(map_slot: Node3D, guard: ActivityGuard = null, quality = null, camera = null) -> void:
	_map_slot = map_slot
	_guard = guard
	_quality = quality
	_camera = camera


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


func is_transitioning() -> bool:
	return is_busy()


func get_current_map_id() -> StringName:
	return current_map_id if state == State.READY else &""


func get_current_content_revision() -> String:
	if state != State.READY or current_map_id == &"":
		return ""
	var def := _get_definition(String(current_map_id))
	return def.content_revision if def != null else ""


func get_state_snapshot() -> Dictionary:
	return {
		"state": STATE_NAMES.get(state, str(state)),
		"map_id": String(current_map_id),
		"transaction_id": _transaction_id,
		"active_map_count": get_active_root_count(),
		"content_revision": get_current_content_revision(),
		"last_error": _last_error,
	}


func get_camera_contract() -> Dictionary:
	## 值副本：{map_id, bounds, exclusions, anchor_ids, default_anchor}；无图返回空 Dictionary。
	if state != State.READY or current_map_id == &"":
		return {}
	var def := _get_definition(String(current_map_id))
	if def == null:
		return {}
	var anchor_ids: Array[StringName] = []
	for a in def.anchor_names:
		anchor_ids.append(StringName(str(a)))
	return {
		"map_id": StringName(def.map_id),
		"bounds": AABB(def.camera_bounds),
		"exclusions": def.camera_exclusion_bounds.duplicate(),
		"anchor_ids": anchor_ids,
		"default_anchor": StringName(def.default_anchor),
	}


# ============================ 请求入口 ============================

## 请求切换地图。只允许一个切换事务；无效请求在卸载前被拒绝（状态不变）。
## 相同地图且 force_reload=false：幂等返回 OK，不启动新事务、不发布 loaded。
func request_map(map_id: StringName, force_reload: bool = false) -> Error:
	var mid := String(map_id)
	if is_busy():
		push_warning("MapManager: 切换进行中(%s)，忽略重复请求 %s" % [STATE_NAMES[state], mid])
		return ERR_BUSY
	if _guard != null and _guard.is_busy() and _guard.get_active_kind() != ActivityGuard.KIND_MAP_TRANSITION:
		return ERR_BUSY  # 截图/基准进行中
	if mid == current_map_id and state == State.READY and not force_reload:
		return OK
	var def := _validate_request(mid)
	if def == null:
		return ERR_INVALID_PARAMETER  # 已发 map_failed；状态保持原状
	if _orphan_paths.has(def.scene_path):
		push_warning("MapManager: 同路径存在未收尾的孤儿加载 %s" % def.scene_path)
		return ERR_BUSY
	# 受理事务
	_transaction_id = _next_transaction_id
	_next_transaction_id += 1
	_tx_valid = true
	if _guard != null and _guard.get_active_kind() != ActivityGuard.KIND_MAP_TRANSITION:
		_load_token = _guard.try_begin(ActivityGuard.KIND_MAP_TRANSITION)
		if _load_token == 0:
			_tx_valid = false
			return ERR_BUSY
	if state == State.READY and current_map_id != &"" and current_map_id != StringName(mid):
		_pending_reload_after_unload = StringName(mid)
		_begin_unload()
		return OK
	if state == State.READY and current_map_id == StringName(mid) and force_reload:
		_pending_reload_after_unload = StringName(mid)
		_begin_unload()
		return OK
	_begin_load(def)
	return OK


## 卸载当前地图。EMPTY 幂等 OK；READY 启动卸载；其余返回 ERR_BUSY。
func request_unload() -> Error:
	if state == State.EMPTY:
		return OK
	if is_busy():
		return ERR_BUSY
	if state != State.READY or current_map_id == &"":
		return ERR_INVALID_PARAMETER
	if _guard != null and _guard.is_busy() and _guard.get_active_kind() != ActivityGuard.KIND_MAP_TRANSITION:
		return ERR_BUSY
	_transaction_id = _next_transaction_id
	_next_transaction_id += 1
	_tx_valid = true
	if _guard != null and _guard.get_active_kind() != ActivityGuard.KIND_MAP_TRANSITION:
		_load_token = _guard.try_begin(ActivityGuard.KIND_MAP_TRANSITION)
		if _load_token == 0:
			_tx_valid = false
			return ERR_BUSY
	_pending_reload_after_unload = &""
	_begin_unload()
	return OK


func _validate_request(map_id: String) -> MapDefinition:
	var fail := func(err: Error, message: String) -> MapDefinition:
		_last_error = message
		map_failed.emit(StringName(map_id), 0, err, message)
		return null
	if not _registry.has(map_id):
		return fail.call(ERR_INVALID_PARAMETER, "未知地图 ID: %s" % map_id)
	var def := _get_definition(map_id)
	if def == null:
		return fail.call(ERR_FILE_NOT_FOUND, "地图定义不可加载: %s" % str(_registry.get(map_id)))
	var reason := def.validate()
	if not reason.is_empty():
		return fail.call(ERR_INVALID_PARAMETER, "定义非法: %s" % reason)
	if not def.available:
		return fail.call(ERR_INVALID_PARAMETER, "地图标记为不可用")
	if not ResourceLoader.exists(def.scene_path):
		return fail.call(ERR_FILE_NOT_FOUND, "场景路径不存在: %s" % def.scene_path)
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


func _release_token() -> void:
	if _guard != null and _load_token != 0:
		_guard.end(_load_token)
	_load_token = 0


# ============================ 卸载 ============================

func _begin_unload() -> void:
	_set_state(State.UNLOADING)
	map_loading.emit(current_map_id, _transaction_id, STAGE_UNLOADING, -1.0)
	var map_id := current_map_id
	var tx := _transaction_id
	if _map_slot.get_child_count() > 0:
		var map_root := _map_slot.get_child(0)
		if map_root is MapRoot:
			(map_root as MapRoot).begin_deactivation()
		var weak: WeakRef = weakref(map_root)
		map_root.name = "OldMapRoot"
		_map_slot.remove_child(map_root)
		map_root.queue_free()
		# 等待删除真正生效（tree_exited 在 remove_child 时已同步发出，不能 await 它）
		while weak.get_ref() != null:
			await get_tree().process_frame
	# 清空本管理器持有的强引用
	_packed_scene = null
	current_map_id = &""
	if not _tx_valid:
		return  # 事务已失效（理论上卸载路径不发生；防御）
	map_unloaded.emit(map_id, tx)
	if _pending_reload_after_unload == &"":
		_release_token()
		_tx_valid = false
	_after_unload()


func _after_unload() -> void:
	if _pending_reload_after_unload != &"":
		var next_id := _pending_reload_after_unload
		_pending_reload_after_unload = &""
		var def := _validate_request(String(next_id))
		if def == null:
			# 卸载后验证失败：进入 ERROR，随后回到 EMPTY 允许重试
			_release_token()
			_tx_valid = false
			_set_state(State.ERROR)
			_set_state(State.EMPTY)
			return
		_begin_load(def)
	else:
		_set_state(State.EMPTY)


# ============================ 加载 ============================

func _begin_load(def: MapDefinition) -> void:
	if _load_token == 0 and _guard != null:
		# 首次加载或上一段事务未持锁；切换流程已在 request_map 持锁。
		_load_token = _guard.try_begin(ActivityGuard.KIND_MAP_TRANSITION)
		if _load_token == 0:
			_set_state(State.ERROR)
			_last_error = "活动互斥被占用（capture/benchmark）"
			map_failed.emit(StringName(def.map_id), _transaction_id, ERR_BUSY, _last_error)
			_set_state(State.EMPTY)
			return
	_set_state(State.LOADING)
	_loading_id = StringName(def.map_id)
	_loading_scene_path = def.scene_path
	_load_start_usec = Time.get_ticks_usec()
	_load_request_msec = Time.get_ticks_msec()
	var err := ResourceLoader.load_threaded_request(_loading_scene_path, "", true)
	if err != OK:
		_fail_load(ERR_CANT_OPEN, "后台加载请求失败: %s" % _loading_scene_path)
		return
	set_process(true)


func _process(_delta: float) -> void:
	if state != State.LOADING and _orphan_paths.is_empty():
		set_process(false)
		return
	# 孤儿路径轮询：只等待线程终结并丢弃结果，不激活。
	for path in _orphan_paths.keys():
		var st := ResourceLoader.load_threaded_get_status(path)
		if st != ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			_orphan_paths.erase(path)
	if state != State.LOADING:
		set_process(false)
		return
	if not _tx_valid:
		return
	var elapsed := float(Time.get_ticks_usec() - _load_start_usec) / 1_000_000.0
	if elapsed > LOAD_TIMEOUT_SEC:
		# 超时不取消线程：事务失效，路径转入孤儿轮询，终结后自然丢弃。
		_orphan_paths[_loading_scene_path] = true
		_fail_load(ERR_TIMEOUT, "加载超时（%.0f 秒）: %s" % [elapsed, _loading_scene_path])
		return
	var progress: Array = []
	var status := ResourceLoader.load_threaded_get_status(_loading_scene_path, progress)
	match status:
		ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			map_loading.emit(_loading_id, _transaction_id, STAGE_RESOURCE, float(progress[0]) if progress.size() > 0 else 0.0)
		ResourceLoader.THREAD_LOAD_LOADED:
			last_resource_load_ms = float(Time.get_ticks_msec() - _load_request_msec)
			_packed_scene = ResourceLoader.load_threaded_get(_loading_scene_path)
			_activate_loaded_scene()
		_:
			_fail_load(ERR_FILE_CANT_READ, "资源加载失败或无效 (status=%d)" % status)


func _fail_load(err: Error, message: String) -> void:
	_set_state(State.ERROR)
	var map_id := _loading_id
	var tx := _transaction_id
	_tx_valid = false
	_loading_id = &""
	set_process(false)
	_last_error = message
	map_failed.emit(map_id, tx, err, message)
	_release_token()
	_set_state(State.EMPTY)


func _activate_loaded_scene() -> void:
	_set_state(State.ACTIVATING)
	map_loading.emit(_loading_id, _transaction_id, STAGE_ACTIVATING, -1.0)
	var act_start := Time.get_ticks_msec()
	var map_id := _loading_id
	var tx := _transaction_id
	set_process(false)
	if not _tx_valid:
		return
	if _packed_scene == null:
		_fail_activation(map_id, tx, ERR_CANT_CREATE, "PackedScene 为空")
		return
	var instance := _packed_scene.instantiate()
	if not instance is MapRoot:
		if instance is Node:
			instance.queue_free()
		_fail_activation(map_id, tx, ERR_CANT_CREATE, "地图根节点未使用 MapRoot 脚本")
		return
	var map_root := instance as MapRoot
	var def := _get_definition(String(map_id))
	if def == null:
		_fail_activation(map_id, tx, ERR_INVALID_PARAMETER, "定义在激活阶段不可用")
		return
	map_root.definition = def
	_map_slot.add_child(map_root)
	_map_slot.move_child(map_root, 0)
	# 运行时合同校验（锚点/环境/烘焙/区域路径）
	var contract_errors := map_root.validate_runtime_contract()
	if not contract_errors.is_empty():
		_fail_activation(map_id, tx, ERR_CANT_CREATE, "运行时合同校验失败: %s" % "; ".join(contract_errors))
		return
	current_map_id = map_id
	_packed_scene = null  # 不长期持有地图 PackedScene
	# 质量档 → 相机合同 → 默认机位；任一步失败都不能先发 map_loaded
	if _quality != null:
		var qerr: Error = _quality.apply_to_map(map_root)
		if qerr != OK:
			_fail_activation(map_id, tx, qerr, "质量档应用失败")
			return
	if _camera != null:
		_camera.bind_map_contract(StringName(def.map_id), map_root.get_camera_bounds(), map_root.get_camera_exclusion_bounds())
		var default_pose := map_root.get_anchor_pose(StringName(def.default_anchor))
		if default_pose == null:
			_fail_activation(map_id, tx, ERR_CANT_CREATE, "默认锚点不可用: %s" % def.default_anchor)
			return
		var perr: Error = _camera.apply_pose(default_pose, true)
		if perr != OK:
			_fail_activation(map_id, tx, perr, "默认机位应用失败")
			return
	last_activation_ms = float(Time.get_ticks_msec() - act_start)
	_tx_valid = false
	_release_token()
	_set_state(State.READY)
	map_loaded.emit(map_id, tx)


func _fail_activation(map_id: StringName, tx: int, err: Error, reason: String) -> void:
	_set_state(State.ERROR)
	_tx_valid = false
	_last_error = reason
	map_failed.emit(map_id, tx, err, reason)
	# 清理任何部分实例后回到 EMPTY，允许重试
	for child in _map_slot.get_children():
		child.queue_free()
	current_map_id = &""
	_packed_scene = null
	if _camera != null:
		_camera.unbind_map()
	_release_token()
	_set_state(State.EMPTY)


# ============================ 环境转发（chapter1-1 §7.3） ============================

func _ready_map_root() -> MapRoot:
	if state != State.READY or _map_slot == null or _map_slot.get_child_count() == 0:
		return null
	return _map_slot.get_child(0) as MapRoot


func get_anchor_pose(anchor_id: StringName) -> CameraPose:
	var root := _ready_map_root()
	if root == null:
		return null
	return root.get_anchor_pose(anchor_id)


func get_map_ambient_state() -> Dictionary:
	var root := _ready_map_root()
	if root == null:
		return {}
	return root.get_ambient_state()


func set_map_ambient_paused(paused: bool) -> Error:
	var root := _ready_map_root()
	if root == null:
		return ERR_UNCONFIGURED
	root.set_ambient_paused(paused)
	return OK


func set_map_ambient_time(seconds: float) -> Error:
	var root := _ready_map_root()
	if root == null:
		return ERR_UNCONFIGURED
	root.set_ambient_time(seconds)
	return OK


func restore_map_ambient_state(snapshot: Dictionary) -> Error:
	var root := _ready_map_root()
	if root == null:
		return ERR_UNCONFIGURED
	return root.restore_ambient_state(snapshot)
