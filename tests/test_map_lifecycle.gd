## 地图生命周期测试（headless 可运行）。chapter1-1 §12：T03/T04/T05 + 泄漏指标。
## 运行：godot --headless --path . --script res://tests/test_map_lifecycle.gd
## 覆盖：单活动地图、A→B→A 完整往返×10、地图专有资源弱引用失效、对象计数、内存趋势、
##       重复请求、force_reload、无效 ID、缺失路径、缺锚点、失败恢复。
extends SceneTree

const MM_SCRIPT := preload("res://scripts/maps/map_manager.gd")
const MAP_DEF_SCRIPT := preload("res://scripts/maps/map_definition.gd")

const ROUND_TRIPS := 10
const READY := 1

var mm: Node
var slot: Node3D
var failures: Array[String] = []
var _last_event := ""
var _failed_ids: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	print("=== 生命周期测试开始 ===")
	slot = Node3D.new()
	slot.name = "MapSlot"
	root.add_child(slot)
	mm = Node.new()
	mm.name = "MapManager"
	mm.set_script(MM_SCRIPT)
	root.add_child(mm)
	mm.setup(slot)  # 纯生命周期测试：无 guard/quality/camera
	mm.map_loaded.connect(func(id: StringName, _tx: int) -> void: _last_event = "loaded:" + String(id); print("[%.1fs] loaded %s" % [Time.get_ticks_msec() / 1000.0, String(id)]))
	mm.map_unloaded.connect(func(id: StringName, _tx: int) -> void: _last_event = "unloaded:" + String(id))
	mm.map_failed.connect(func(id: StringName, _tx: int, _err: Error, reason: String) -> void: _last_event = "failed:" + String(id) + ":" + reason; _failed_ids.append(String(id)); print("[%.1fs] FAILED %s: %s" % [Time.get_ticks_msec() / 1000.0, String(id), reason]))
	mm.state_changed.connect(func(s: int) -> void: _last_event = "state:%d" % s)

	# 负面用例的破损定义（写入 user://，不进生产注册表）
	var broken_scene_def := MAP_DEF_SCRIPT.new()
	broken_scene_def.schema_version = 2
	broken_scene_def.map_id = "broken_scene"
	broken_scene_def.display_name = "坏路径"
	broken_scene_def.scene_path = "res://tests/fixtures/does_not_exist.tscn"
	broken_scene_def.anchor_names = PackedStringArray(["test_anchor"])
	broken_scene_def.default_anchor = "test_anchor"
	ResourceSaver.save(broken_scene_def, "user://broken_scene_def.tres")
	var broken_anchor_def := MAP_DEF_SCRIPT.new()
	broken_anchor_def.schema_version = 2
	broken_anchor_def.map_id = "broken_anchor"
	broken_anchor_def.display_name = "缺锚点"
	broken_anchor_def.scene_path = "res://tests/fixtures/mini_test_map.tscn"
	broken_anchor_def.anchor_names = PackedStringArray(["wrong_anchor"])
	broken_anchor_def.default_anchor = "wrong_anchor"
	ResourceSaver.save(broken_anchor_def, "user://broken_anchor_def.tres")
	# T02：未来版本定义
	var future_def := MAP_DEF_SCRIPT.new()
	future_def.schema_version = 3
	future_def.map_id = "future_schema"
	future_def.display_name = "未来版本"
	future_def.scene_path = "res://tests/fixtures/mini_test_map.tscn"
	future_def.anchor_names = PackedStringArray(["test_anchor"])
	future_def.default_anchor = "test_anchor"
	ResourceSaver.save(future_def, "user://future_schema_def.tres")

	mm.inject_registry({
		"m01_afterglow": "res://maps/m01_afterglow/map_definition.tres",
		"m01_repair_interior": "res://maps/m01_repair_interior/map_definition.tres",
		"test_mini_map": "res://tests/fixtures/mini_test_map_definition.tres",
		"broken_scene": "user://broken_scene_def.tres",
		"broken_anchor": "user://broken_anchor_def.tres",
		"future_schema": "user://future_schema_def.tres",
	})

	_check(mm.state == 0, "初始状态为 EMPTY")

	# 1. 无效 ID：卸载前拒绝，状态不变
	_last_event = ""
	mm.request_map(StringName("no_such_map"))
	_check(_last_event.begins_with("failed:no_such_map"), "无效 ID 发出 map_failed")
	_check(mm.state == 0, "无效 ID 后状态保持 EMPTY")
	_check(mm.request_map(StringName("no_such_map")) == ERR_INVALID_PARAMETER, "无效 ID 返回 ERR_INVALID_PARAMETER")

	# 2. T02 未来版本：明确拒绝
	_last_event = ""
	mm.request_map(StringName("future_schema"))
	_check(_last_event.begins_with("failed:future_schema"), "未来 schema_version 发出 map_failed")
	_check(mm.state == 0, "未来版本后状态保持 EMPTY")

	# 3. 加载正式地图
	_check(mm.request_map(StringName("m01_afterglow")) == OK, "请求 m01 被接受")
	_check(await _await_loaded("m01_afterglow", 30.0), "m01 加载完成")
	_check(mm.state == READY, "加载后 READY")
	_check(mm.get_active_root_count() == 1, "稳态活动地图数为 1")

	# 4. T05：请求当前地图（幂等）与 force_reload（重载）
	var tx_before: int = mm.get_state_snapshot()["transaction_id"]
	_check(mm.request_map(StringName("m01_afterglow")) == OK, "相同地图幂等返回 OK")
	_check(mm.get_state_snapshot()["transaction_id"] == tx_before, "幂等请求不启动新事务")
	_check(mm.request_map(StringName("m01_afterglow"), true) == OK, "force_reload 受理")
	_check(await _await_loaded("m01_afterglow", 30.0), "force_reload 后重新加载完成")
	_check(mm.get_state_snapshot()["transaction_id"] != tx_before, "force_reload 启动了新事务")

	# 5. 缺失路径：卸载前拒绝，当前地图不变
	_last_event = ""
	mm.request_map(StringName("broken_scene"))
	_check(_last_event.begins_with("failed:broken_scene"), "缺失路径发出 map_failed")
	_check(mm.state == READY and mm.current_map_id == StringName("m01_afterglow"), "缺失路径后仍为 m01 READY")

	# 6. A→B→A 完整往返 ×10 + 泄漏指标
	var base_mem := 0.0
	var m01_mesh_res: Resource = load("res://maps/m01_afterglow/meshes/baked_static.res")
	var mem_trend: Array[float] = []
	for i in ROUND_TRIPS:
		var weak_a := _root_weak()
		var res_weak_a: WeakRef = weakref(m01_mesh_res)
		m01_mesh_res = null  # 释放本地强引用，只留弱引用观察回收
		mm.request_map(StringName("test_mini_map"))
		_check(await _await_loaded("test_mini_map", 30.0), "第 %d 轮 B 加载完成" % (i + 1))
		_check(mm.get_active_root_count() <= 1, "切换中任意时刻活动地图 ≤1")
		_check(await _weak_dead(weak_a), "A 根弱引用失效 (轮 %d)" % (i + 1))
		_check(await _weak_dead(res_weak_a), "A 地图专有网格资源引用失效 (轮 %d)" % (i + 1))
		var weak_b := _root_weak()
		mm.request_map(StringName("m01_afterglow"))
		_check(await _await_loaded("m01_afterglow", 30.0), "第 %d 轮 A 加载完成" % (i + 1))
		_check(mm.get_active_root_count() <= 1, "切回后活动地图 ≤1")
		_check(await _weak_dead(weak_b), "B 根弱引用失效 (轮 %d)" % (i + 1))
		m01_mesh_res = load("res://maps/m01_afterglow/meshes/baked_static.res")
		var mem := float(OS.get_memory_info().get("available", 0)) / (1024.0 * 1024.0)
		mem_trend.append(mem)
		if i == 4:
			base_mem = mem  # 预热 5 轮后取基准
		if i >= 4:
			print("  内存趋势轮 %d: 可用 %.0f MiB (基准 %.0f)" % [i + 1, mem, base_mem])
	var end_mem := float(OS.get_memory_info().get("available", 0)) / (1024.0 * 1024.0)
	if base_mem > 0.0:
		_check(base_mem - end_mem < maxf(150.0, 0.0),
			"预热后可用内存下降 %.0f MiB 在阈值内（<150 MiB）" % (base_mem - end_mem))

	# 6b. chapter1-2 T10：生产双图（街区 ↔ 室内）完整往返 ×10 + 资源隔离
	var interior_mesh_res: Resource = load("res://maps/m01_repair_interior/meshes/interior_static.res")
	var street_mesh_weak: WeakRef = weakref(m01_mesh_res)
	var prod_base_mem := 0.0
	var prod_mem_trend: Array[float] = []
	for i in ROUND_TRIPS:
		var weak_street := _root_weak()
		m01_mesh_res = null  # 只留弱引用观察街区资源回收
		mm.request_map(StringName("m01_repair_interior"))
		_check(await _await_loaded("m01_repair_interior", 30.0), "双图轮 %d：室内加载完成" % (i + 1))
		_check(mm.get_active_root_count() <= 1, "双图轮 %d：切换中活动地图 ≤1" % (i + 1))
		_check(await _weak_dead(weak_street), "双图轮 %d：街区根弱引用失效" % (i + 1))
		_check(await _weak_dead(street_mesh_weak), "双图轮 %d：街区网格资源引用失效" % (i + 1))
		var weak_interior := _root_weak()
		var interior_mesh_weak: WeakRef = weakref(interior_mesh_res)
		interior_mesh_res = null
		mm.request_map(StringName("m01_afterglow"))
		_check(await _await_loaded("m01_afterglow", 30.0), "双图轮 %d：街区加载完成" % (i + 1))
		_check(await _weak_dead(weak_interior), "双图轮 %d：室内根弱引用失效" % (i + 1))
		_check(await _weak_dead(interior_mesh_weak), "双图轮 %d：室内网格资源引用失效" % (i + 1))
		m01_mesh_res = load("res://maps/m01_afterglow/meshes/baked_static.res")
		interior_mesh_res = load("res://maps/m01_repair_interior/meshes/interior_static.res")
		var mem2 := float(OS.get_memory_info().get("available", 0)) / (1024.0 * 1024.0)
		prod_mem_trend.append(mem2)
		if i == 4:
			prod_base_mem = mem2
		if i >= 4:
			print("  双图内存趋势轮 %d: 可用 %.0f MiB (基准 %.0f)" % [i + 1, mem2, prod_base_mem])
	var prod_end_mem := float(OS.get_memory_info().get("available", 0)) / (1024.0 * 1024.0)
	if prod_base_mem > 0.0:
		_check(prod_base_mem - prod_end_mem < 150.0,
			"双图预热后可用内存下降 %.0f MiB 在阈值内（<150 MiB）" % (prod_base_mem - prod_end_mem))
	interior_mesh_res = null

	# 7. T04 切换中重复请求被拒
	mm.request_map(StringName("test_mini_map"))
	_check(mm.request_map(StringName("m01_afterglow")) == ERR_BUSY, "切换中重复请求返回 ERR_BUSY")
	_check(await _await_loaded("test_mini_map", 30.0), "切换中的重复请求未破坏原事务")

	# 8. 单独卸载 → 空外壳
	_check(mm.request_unload() == OK, "request_unload 受理")
	_check(await _await_state(0, 10.0), "卸载后回到 EMPTY")
	_check(mm.get_active_root_count() == 0, "卸载后活动地图数为 0")
	_check(slot.get_child_count() == 0, "MapSlot 无残留子节点")
	_check(mm.request_unload() == OK, "EMPTY 时 request_unload 幂等返回 OK")

	# 9. 重新加载恢复
	mm.request_map(StringName("m01_afterglow"))
	_check(await _await_loaded("m01_afterglow", 30.0), "重新加载 m01 成功")
	_check(mm.get_active_root_count() == 1, "恢复后活动地图数为 1")
	var snap: Dictionary = mm.get_state_snapshot()
	_check(snap.get("state", "") == "READY" and snap.get("active_map_count", 0) == 1, "状态快照字段正确")

	# 10. 缺锚点：卸载后失败 → 清理 → EMPTY → 可重试
	_last_event = ""
	_failed_ids.clear()
	mm.request_map(StringName("broken_anchor"))
	_check(await _await_cond(func() -> bool: return _failed_ids.has("broken_anchor"), 30.0), "缺锚点发出 map_failed")
	_check(await _await_state(0, 5.0), "失败清理后回到 EMPTY")
	_check(mm.get_active_root_count() == 0, "失败后无残留地图")

	# 11. 失败后重试成功
	mm.request_map(StringName("m01_afterglow"))
	_check(await _await_loaded("m01_afterglow", 30.0), "失败后重试 m01 成功")

	# 结果
	if failures.is_empty():
		print("=== 生命周期测试全部通过 ===")
		quit(0)
	else:
		for f in failures:
			printerr("FAIL: ", f)
		print("=== 生命周期测试失败 %d 项 ===" % failures.size())
		quit(1)


func _check(cond: bool, label: String) -> void:
	if cond:
		print("PASS: ", label)
	else:
		failures.append(label)
		printerr("FAIL: ", label)


func _count_all_nodes() -> int:
	return mm.get_state_snapshot().get("active_map_count", 0)


func _await_loaded(map_id: String, timeout: float) -> bool:
	var target := "loaded:" + map_id
	return await _await_cond(func() -> bool: return _last_event == target, timeout)


func _await_state(s: int, timeout: float) -> bool:
	return await _await_cond(func() -> bool: return mm.state == s, timeout)


func _await_cond(cond: Callable, timeout: float) -> bool:
	var t := 0.0
	while t < timeout:
		if cond.call():
			return true
		await create_timer(0.03).timeout
		t += 0.03
	return cond.call()


func _root_weak() -> WeakRef:
	var roots := get_nodes_in_group("active_map_root")
	return weakref(roots[0]) if roots.size() > 0 else weakref(null)


func _weak_dead(ref: WeakRef) -> bool:
	## 释放可能延迟若干帧；轮询确认。
	var t := 0.0
	while t < 2.0:
		if ref.get_ref() == null:
			return true
		await create_timer(0.05).timeout
		t += 0.05
	return ref.get_ref() == null
